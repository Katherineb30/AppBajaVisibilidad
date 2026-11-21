// ==========================================================================
// Detector de billetes
// Capa MVVM: Datos
//
// Inferencia del modelo YOLO con TensorFlow Lite en el dispositivo, con
// post-procesado y supresion de duplicados.
//
// Requisitos de la ERS que atiende:
//   - RF03 billetes
//   - RF04 procesamiento local
//   - RNF-R2 tiempo de respuesta
// ==========================================================================

import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../core/utils/image_converter.dart';
import '../models/banknote_detection.dart';
import 'model_storage_service.dart';

/// Detector de billetes colombianos (RF03).
///
/// Ejecuta con TensorFlow Lite el modelo YOLO entrenado en Google Colab. Todo
/// el calculo ocurre en el dispositivo: la aplicacion funciona sin conexion
/// (RF04, RNF-S1).
///
/// La entrada y la salida se escriben y se leen **directamente sobre la
/// memoria del tensor**, sin pasar por listas anidadas de Dart. Esa conversion
/// intermedia recorria casi cinco millones de valores por fotograma: bloqueaba
/// el hilo de interfaz, entrecortaba la voz y dejaba el tensor mal formado
/// ("Input tensor lacks data").
///
/// Formatos admitidos, detectados solos:
///   entrada : [1, 3, S, S] (NCHW) o [1, S, S, 3] (NHWC), float32 0..1
///   salida  : [1, 4+C, A] o [1, A, 4+C]  (YOLO clasico, cx cy w h)
///             [1, N, 6]                  (end to end: x1 y1 x2 y2 score clase)
class BanknoteDetectorService {
  BanknoteDetectorService({
    ModelStorageService? storage,
    this.modelAsset = 'assets/models/billetes_yolov8.tflite',
    this.labelsAsset = 'assets/labels/billetes.txt',
    this.confidenceThreshold = 0.40,
    // 0.35 en lugar del habitual 0.45: sobre un mismo billete el modelo emite
    // cajas casi identicas de varias clases, y con un umbral alto sobrevivian
    // las dos. Al colapsarlas, se queda la de mayor confianza.
    this.iouThreshold = 0.35,
  }) : storage = storage ?? ModelStorageService();

  /// Resuelve si se usa el modelo empaquetado o uno actualizado (RF07).
  final ModelStorageService storage;

  final String modelAsset;
  final String labelsAsset;

  /// Umbral para quedarse con una caja del modelo. El umbral de ANUNCIO por
  /// voz es mas alto y vive en DetectBanknoteUseCase (RNF-F4).
  final double confidenceThreshold;
  final double iouThreshold;

  Interpreter? _interpreter;
  List<String> _labels = const [];
  List<int> _outputShape = const [];
  final LetterboxMeta _meta = LetterboxMeta();

  int _inputSide = 640;
  bool _channelsFirst = false;
  int _debugTick = 0;
  int _failures = 0;

  /// Fallos de inferencia seguidos tras los cuales se da el modelo por
  /// inservible. Sirve para avisar al usuario en lugar de quedarse en
  /// silencio: un .tflite sin pesos carga bien pero falla siempre al ejecutar.
  static const int _maxFailures = 5;
  bool _ready = false;
  bool _usingUpdatedModel = false;
  String? _loadError;

  bool get isReady => _ready;
  bool get usingUpdatedModel => _usingUpdatedModel;
  String? get loadError => _loadError;
  List<String> get labels => _labels;

  Future<void> load() async {
    if (_ready) return;
    try {
      _labels = await _loadLabels();

      // 4 hilos: suficiente en gama media sin dejar sin CPU al hilo de audio.
      final options = InterpreterOptions()..threads = 4;

      // RF07: si hay un modelo instalado por actualizacion se usa ese; si no,
      // el que viaja dentro del APK.
      final source = await storage.resolve();
      final interpreter = source.isUpdated
          ? Interpreter.fromFile(source.file!, options: options)
          : await Interpreter.fromAsset(modelAsset, options: options);
      interpreter.allocateTensors();
      _usingUpdatedModel = source.isUpdated;

      final inputShape = interpreter.getInputTensor(0).shape;
      if (inputShape.length == 4) {
        _channelsFirst = inputShape[1] == 3;
        _inputSide = _channelsFirst ? inputShape[2] : inputShape[1];
      }
      _outputShape = interpreter.getOutputTensor(0).shape;

      _interpreter = interpreter;
      _ready = true;
      _loadError = null;
      debugPrint(
        'BanknoteDetector listo. entrada=$inputShape '
        '(${_channelsFirst ? "NCHW" : "NHWC"}, lado $_inputSide) '
        'salida=$_outputShape clases=${_labels.length}',
      );
    } catch (e) {
      _ready = false;
      _loadError = e.toString();
      debugPrint('BanknoteDetector: no se pudo cargar el modelo -> $e');
    }
  }

  Future<List<String>> _loadLabels() async {
    try {
      final raw = await rootBundle.loadString(labelsAsset);
      return raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Analiza un fotograma de camara y devuelve las detecciones.
  List<BanknoteDetection> detectFrame(CameraImage image, int rotationDegrees) {
    final interpreter = _interpreter;
    if (interpreter == null || !_ready) return const [];

    try {
      final input = ImageConverter.preprocess(
        image,
        rotation: rotationDegrees,
        side: _inputSide,
        channelsFirst: _channelsFirst,
        meta: _meta,
      );

      // Escritura directa sobre el tensor: una copia de memoria, sin recorrer
      // valor a valor.
      interpreter.getInputTensor(0).data =
          input.buffer.asUint8List(input.offsetInBytes, input.lengthInBytes);

      interpreter.invoke();

      final raw = interpreter.getOutputTensor(0).data;
      final output = Float32List.view(
        raw.buffer,
        raw.offsetInBytes,
        raw.lengthInBytes ~/ 4,
      );

      _failures = 0;
      return _nms(_parse(output));
    } catch (e) {
      _failures++;
      debugPrint('BanknoteDetector: fallo la inferencia ($_failures) -> $e');
      if (_failures >= _maxFailures) {
        _ready = false;
        _loadError = 'La inferencia falla de forma persistente: $e';
        debugPrint(
          'BanknoteDetector: modelo marcado como inservible. '
          'El archivo .tflite probablemente no contiene los pesos.',
        );
      }
      return const [];
    }
  }

  // ------------------------------------------------------------------
  // Post-procesado
  // ------------------------------------------------------------------

  /// Traduce la salida cruda del modelo a detecciones.
  ///
  /// Hay tres formatos posibles segun como se haya exportado el modelo desde
  /// YOLO, y el codigo los distingue por la forma del tensor en lugar de
  /// confiar en una convencion:
  ///
  ///   [1, 4+C, A]  un canal por fila  (lo que produce el export habitual)
  ///   [1, A, 4+C]  un ancla por fila  (transpuesto)
  ///   [1, N, 6]    "end to end", con la supresion de duplicados ya aplicada
  ///
  /// C es el numero de clases y A el de anclas. Los cuatro primeros valores de
  /// cada ancla son la caja (centro x, centro y, ancho, alto) y el resto son las
  /// puntuaciones por clase.
  List<BanknoteDetection> _parse(Float32List out) {
    if (_outputShape.length != 3) return const [];

    final dim1 = _outputShape[1];
    final dim2 = _outputShape[2];
    final numClasses =
        _labels.isNotEmpty ? _labels.length : math.min(dim1, dim2) - 4;
    if (numClasses <= 0) return const [];

    // Formato "end to end": la supresion de duplicados ya viene aplicada.
    if (dim2 == 6 && dim1 != numClasses + 4) {
      return _parseEndToEnd(out, dim1, numClasses);
    }

    final channelsFirst = dim1 == numClasses + 4;
    final anchors = channelsFirst ? dim2 : dim1;
    final channels = channelsFirst ? dim1 : dim2;
    if (channels != numClasses + 4) return const [];

    double at(int channel, int anchor) => channelsFirst
        ? out[channel * anchors + anchor]
        : out[anchor * channels + channel];

    final results = <BanknoteDetection>[];

    // Diagnostico: se sigue la puntuacion mas alta de todo el fotograma y el
    // rango de las coordenadas, para saber si el modelo esta produciendo algo
    // y si sus valores llegan normalizados o en pixeles.
    var globalMax = 0.0;
    var globalMaxClass = -1;
    var maxBoxValue = 0.0;

    for (var a = 0; a < anchors; a++) {
      var bestScore = 0.0;
      var bestClass = -1;
      for (var c = 0; c < numClasses; c++) {
        final score = at(4 + c, a);
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }
      if (bestScore > globalMax) {
        globalMax = bestScore;
        globalMaxClass = bestClass;
      }
      for (var k = 0; k < 4; k++) {
        final v = at(k, a).abs();
        if (v > maxBoxValue) maxBoxValue = v;
      }

      if (bestClass < 0 || bestScore < confidenceThreshold) continue;

      var cx = at(0, a);
      var cy = at(1, a);
      var w = at(2, a);
      var h = at(3, a);

      // Algunos exports dan pixeles en lugar de 0..1.
      if (cx > 1.5 || cy > 1.5 || w > 1.5 || h > 1.5) {
        cx /= _meta.side;
        cy /= _meta.side;
        w /= _meta.side;
        h /= _meta.side;
      }

      final rect = _undoLetterbox(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2);
      if (rect == null) continue;

      final label = bestClass < _labels.length ? _labels[bestClass] : '$bestClass';
      results.add(
        BanknoteDetection(
          label: label,
          denomination: _denominationFrom(label),
          confidence: bestScore,
          rect: rect,
          classIndex: bestClass,
        ),
      );
    }

    if (++_debugTick % 4 == 1) {
      final clase = globalMaxClass >= 0 && globalMaxClass < _labels.length
          ? _labels[globalMaxClass]
          : '$globalMaxClass';
      debugPrint(
        'DIAG salida=$_outputShape anclas=$anchors '
        'maxScore=${(globalMax * 100).toStringAsFixed(1)}% ($clase) '
        'maxCoord=${maxBoxValue.toStringAsFixed(3)} '
        'cajas=${results.length}',
      );
    }

    return results;
  }

  List<BanknoteDetection> _parseEndToEnd(
    Float32List out,
    int rows,
    int numClasses,
  ) {
    final results = <BanknoteDetection>[];

    for (var i = 0; i < rows; i++) {
      final o = i * 6;
      final score = out[o + 4];
      if (score < confidenceThreshold) continue;

      final classIndex = out[o + 5].round();
      if (classIndex < 0 || classIndex >= numClasses) continue;

      var x1 = out[o];
      var y1 = out[o + 1];
      var x2 = out[o + 2];
      var y2 = out[o + 3];

      if (x2 > 1.5 || y2 > 1.5) {
        x1 /= _meta.side;
        y1 /= _meta.side;
        x2 /= _meta.side;
        y2 /= _meta.side;
      }

      final rect = _undoLetterbox(x1, y1, x2, y2);
      if (rect == null) continue;

      final label =
          classIndex < _labels.length ? _labels[classIndex] : '$classIndex';
      results.add(
        BanknoteDetection(
          label: label,
          denomination: _denominationFrom(label),
          confidence: score,
          rect: rect,
          classIndex: classIndex,
        ),
      );
    }
    return results;
  }

  /// Pasa coordenadas 0..1 del tensor (con relleno) a coordenadas 0..1 de la
  /// imagen que ve el usuario.
  Rect? _undoLetterbox(double x1, double y1, double x2, double y2) {
    final side = _meta.side;
    final contentW = _meta.width * _meta.scale;
    final contentH = _meta.height * _meta.scale;
    if (contentW <= 0 || contentH <= 0) return null;

    final rect = Rect.fromLTRB(
      ((x1 * side - _meta.padX) / contentW).clamp(0.0, 1.0),
      ((y1 * side - _meta.padY) / contentH).clamp(0.0, 1.0),
      ((x2 * side - _meta.padX) / contentW).clamp(0.0, 1.0),
      ((y2 * side - _meta.padY) / contentH).clamp(0.0, 1.0),
    );
    if (rect.width <= 0.02 || rect.height <= 0.02) return null;
    return rect;
  }

  /// Extrae el valor en pesos: `billete_50000` -> 50000.
  static int _denominationFrom(String label) {
    final match = RegExp(r'\d{3,6}').firstMatch(label);
    if (match == null) return 0;
    return int.tryParse(match.group(0)!) ?? 0;
  }

  List<BanknoteDetection> _nms(List<BanknoteDetection> input) {
    if (input.length <= 1) return input;
    final sorted = [...input]..sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <BanknoteDetection>[];

    for (final candidate in sorted) {
      var overlaps = false;
      for (final k in kept) {
        if (_iou(candidate.rect, k.rect) > iouThreshold) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) kept.add(candidate);
      if (kept.length >= 5) break;
    }
    return kept;
  }

  static double _iou(Rect a, Rect b) {
    final interLeft = math.max(a.left, b.left);
    final interTop = math.max(a.top, b.top);
    final interRight = math.min(a.right, b.right);
    final interBottom = math.min(a.bottom, b.bottom);
    final interW = interRight - interLeft;
    final interH = interBottom - interTop;
    if (interW <= 0 || interH <= 0) return 0;
    final inter = interW * interH;
    final union = a.width * a.height + b.width * b.height - inter;
    return union <= 0 ? 0 : inter / union;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _ready = false;
  }
}
