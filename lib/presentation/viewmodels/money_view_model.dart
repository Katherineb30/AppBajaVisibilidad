// ==========================================================================
// ViewModel de DINERO
// Capa MVVM: Presentacion
//
// Orquesta el detector, el contraste con la cifra impresa y el anuncio de la
// denominacion.
//
// Requisitos de la ERS que atiende:
//   - RF03 billetes
//   - RF05 voz
//   - CU03
//   - RNF-F4
// ==========================================================================

import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_strings.dart';
import '../../data/models/banknote_detection.dart';
import '../../core/utils/banknote_text_parser.dart';
import '../../data/services/diagnostics_service.dart';
import '../../domain/usecases/detect_banknote_usecase.dart';
import '../../domain/usecases/recognize_text_usecase.dart';
import 'recognition_view_model.dart';

/// ViewModel del modulo DINERO (CU03, CU05, CU06).
class MoneyViewModel extends RecognitionViewModel {
  MoneyViewModel({
    required super.cameraService,
    required super.permissionService,
    required super.tts,
    required super.diagnostics,
    required DetectBanknoteUseCase detectBanknote,
    required RecognizeTextUseCase recognizeText,
  })  : _detectBanknote = detectBanknote,
        _recognizeText = recognizeText;

  final DetectBanknoteUseCase _detectBanknote;

  /// El mismo OCR del modulo de texto, aqui como verificador: lee la cifra
  /// impresa en el billete para contrastar lo que dice el modelo de vision.
  final RecognizeTextUseCase _recognizeText;

  List<BanknoteDetection> _candidates = const [];
  List<BanknoteDetection> get candidates => _candidates;

  BanknoteDetection? _confirmed;
  BanknoteDetection? get confirmed => _confirmed;

  /// Ultima frase anunciada. Se guarda aparte del resultado en pantalla para
  /// que REPETIR siga funcionando despues de limpiar la deteccion.
  String _lastPhrase = '';

  bool get modelReady => _detectBanknote.isModelReady;

  /// false mientras el modelo aun se esta cargando. Sirve para no mostrar el
  /// aviso de "modelo no disponible" durante el arranque normal.
  bool _modelChecked = false;
  bool get modelChecked => _modelChecked;
  String? get modelError => _detectBanknote.modelError;

  @override
  String get lastSpokenContent => _lastPhrase;

  @override
  String get moduleName => DiagnosticsService.moneyModule;

  @override
  String get searchingMessage => AppStrings.searchingMoney;

  /// La inferencia YOLOv8 es mas costosa que el OCR: se deja mas margen entre
  /// fotogramas para no competir con el hilo de audio.
  @override
  Duration get minInterval => const Duration(milliseconds: 700);

  // La linterna se enciende con mucha mas facilidad que en el modulo de texto.
  // El motivo no es la falta de luz sino el COLOR: bajo una bombilla
  // incandescente los billetes de 5, 10 y 20 mil viran a rojizo y el modelo
  // los confunde. La luz blanca del LED devuelve el color a su sitio.
  // El usuario siempre puede apagarla manteniendo pulsada la vista de camara.
  @override
  double get torchOnBelow => 125;

  @override
  double get torchOffAbove => 180;

  @override
  String get torchReason => AppStrings.torchForColor;

  @override
  Future<void> prepareModule() async {
    await _recognizeText.prepare();
    await _detectBanknote.prepare();
    _modelChecked = true;
    if (!_detectBanknote.isModelReady) {
      setHint(AppStrings.modelMissing);
    }
    notifyListeners();
  }

  @override
  Future<bool> analyze(CameraImage image, int rotation) async {
    if (!_detectBanknote.isModelReady) {
      // RNF-F3: el fallo se anuncia en voz y con una alternativa concreta.
      await announceProblem(
        '${AppStrings.modelBroken} ${AppStrings.errorAlternative}',
        tag: 'modelo-roto',
      );
      return false;
    }

    final detections = await _detectBanknote(image, rotation);
    _candidates = detections;
    notifyListeners();

    // Traza de calibracion: deja ver en consola la confianza real del modelo,
    // para ajustar con datos el umbral de anuncio por voz (RNF-F4).
    if (detections.isNotEmpty) {
      final top = detections.reduce(
        (a, b) => a.confidence >= b.confidence ? a : b,
      );
      final lista = detections
          .map((d) =>
              '#${d.classIndex} ${d.label} '
              '${(d.confidence * 100).toStringAsFixed(0)}% '
              'area=${(d.rect.width * d.rect.height * 100).toStringAsFixed(0)}%')
          .join('  |  ');
      debugPrint(
        'CANDIDATOS(${detections.length}): $lista'
        '   => elegido #${top.classIndex} ${top.label}',
      );
    }

    // Contraste con la cifra impresa. Solo se consulta el OCR cuando el
    // detector ya ve algo: asi no se paga su coste en cada fotograma.
    int? valorLeido;
    if (detections.isNotEmpty) {
      try {
        final texto = await _recognizeText(image, rotation);

        // Solo cuenta el texto que cae DENTRO de alguna caja detectada.
        //
        // Antes se analizaba el fotograma completo, de modo que la cifra del
        // billete competia con cualquier otro numero de la escena -- otro
        // billete sobre la mesa, un precio, un recibo --; al ver dos
        // denominaciones distintas el lector callaba por seguridad y la
        // verificacion no llegaba a actuar nunca. Acotar al billete es lo que
        // hace util la comprobacion justo donde mas falta hace: entre 5, 10 y
        // 20 mil, que son los que el color confunde.
        final dentro = texto.blocks
            .where((b) => detections.any((d) => _dentroDeLaCaja(d.rect, b.rect)))
            .map((b) => b.text)
            .join('\n');

        // Sin reserva al fotograma completo.
        //
        // Antes, si ningun bloque caia dentro de la caja se analizaba toda la
        // escena, y el log mostro lo que eso provoca: el texto de un documento
        // que estaba sobre la mesa -- "APROBACION", "FECHA DE", parrafos
        // enteros -- entraba a competir con la cifra del billete. Es preferible
        // no leer nada a leer el papel equivocado.
        final fuente = dentro.trim();
        valorLeido = fuente.isEmpty ? null : BanknoteTextParser.parse(fuente);

        // Se traza SIEMPRE, tambien cuando no se lee cifra: sin esta linea no
        // habia forma de saber si el OCR no veia el numero o si lo veia y el
        // analizador lo descartaba.
        debugPrint(
          'OCR-BILLETE ${valorLeido ?? "sin cifra"} '
          '(${texto.blocks.length} bloques, ${fuente.isEmpty ? 0 : fuente.split("\n").length} dentro de la caja) '
          '<- "${fuente.replaceAll('\n', ' / ')}"',
        );
      } catch (e) {
        // Si el OCR falla se sigue con el juicio del modelo, sin mas.
        diagnostics.recordError('ocr-verificacion/billetes', e);
      }
    }

    final best = _detectBanknote.confirm(detections, textValue: valorLeido);
    if (best == null) {
      if (detections.isEmpty) {
        setHint(AppStrings.searchingMoney);
      } else {
        final mayor = detections.reduce(
          (a, b) => a.rect.width * a.rect.height >= b.rect.width * b.rect.height
              ? a
              : b,
        );
        if (mayor.rect.width * mayor.rect.height < 0.06) {
          // Se ve el billete pero muy lejos: acercarlo sube la confianza.
          await announceProblem(AppStrings.moveCloser, tag: 'acercar-billete');
        } else {
          // RNF-F4: por debajo del 85 % no se anuncia un resultado incierto,
          // se pide repetir la captura.
          await announceProblem(
            AppStrings.lowConfidence,
            tag: 'confianza-baja',
          );
        }
      }
      return false;
    }

    _confirmed = best;
    setHint(AppStrings.detectedNoteLabel);
    notifyListeners();

    // Se anuncia la denominacion completa, en palabras y de una sola vez.
    // Mantener el mismo billete a la vista no repite el anuncio en bucle.
    _lastPhrase = best.spokenPhrase;
    if (shouldAnnounce(best.tag)) {
      await tts.speakResult(best.spokenPhrase, tag: best.tag);
    }
    return true;
  }

  /// true si el centro de un bloque de texto cae dentro de la caja del
  /// billete, con un margen del 10 % que absorbe el desajuste entre el
  /// recuadro que da el detector y el que da el OCR.
  ///
  /// Ambos rectangulos estan normalizados (0..1) sobre el mismo fotograma ya
  /// rotado, asi que son directamente comparables.
  static bool _dentroDeLaCaja(Rect caja, Rect bloque) {
    final mx = caja.width * 0.10;
    final my = caja.height * 0.10;
    final cx = bloque.center.dx;
    final cy = bloque.center.dy;
    return cx >= caja.left - mx &&
        cx <= caja.right + mx &&
        cy >= caja.top - my &&
        cy <= caja.bottom + my;
  }

  /// Limpia el resultado anterior antes de la siguiente deteccion.
  ///
  /// Es importante que NO se conserve: la caja del overlay y el panel inferior
  /// se quedaban congelados en el billete anterior, y como el indicador de
  /// analisis solo aparece cuando no hay resultado, la pantalla daba la
  /// impresion de haberse quedado clavada en una denominacion. La frase para
  /// REPETIR se guarda aparte, en _lastPhrase.
  @override
  void prepareNextScan() {
    _detectBanknote.reset();
    _confirmed = null;
    _candidates = const [];
    notifyListeners();
  }

  /// Descarta el billete detectado y vuelve a buscar.
  void scanAgain() {
    _detectBanknote.reset();
    _confirmed = null;
    _candidates = const [];
    resumeSearch();
  }

  @override
  Future<void> releaseModule() async {
    await _recognizeText.release();
    await _detectBanknote.release();
  }
}
