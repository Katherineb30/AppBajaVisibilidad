// ==========================================================================
// Caso de uso CU01
// Capa MVVM: Dominio
//
// Reconocer texto. Anade estabilizacion temporal: un texto solo se da por
// bueno cuando se repite entre fotogramas.
//
// Requisitos de la ERS que atiende:
//   - RF01 OCR
//   - CU01
//   - RNF-F2 exactitud
// ==========================================================================

import 'package:camera/camera.dart';

import '../../data/models/detected_text_block.dart';
import '../repositories/i_text_recognition_repository.dart';

/// Caso de uso CU01 - Reconocer texto.
///
/// Anade al reconocimiento crudo una **estabilizacion temporal**: solo se da
/// por bueno un texto cuando se repite en varios fotogramas seguidos. Sin esto
/// el OCR cambia en cada fotograma y la voz se reiniciaria constantemente, que
/// es el origen tipico de la lectura entrecortada.
///
/// La comparacion se hace **por palabras**, no caracter a caracter: entre dos
/// fotogramas consecutivos el OCR reordena lineas, pierde una palabra o anade
/// otra, pero el conjunto de palabras se mantiene casi igual. Comparar
/// posiciones exactas hacia que la confirmacion no llegara nunca.
class RecognizeTextUseCase {
  RecognizeTextUseCase(
    this._repository, {
    this.framesToConfirm = 2,
    this.similarityThreshold = 0.65,
    this.maxAttempts = 6,
  });

  final ITextRecognitionRepository _repository;

  /// Fotogramas parecidos necesarios para confirmar.
  final int framesToConfirm;

  /// Proporcion minima de palabras compartidas para considerar que dos
  /// lecturas son "el mismo texto".
  final double similarityThreshold;

  /// Tras este numero de analisis con texto visible se acepta la ultima
  /// lectura aunque no se haya estabilizado. Evita que el usuario se quede
  /// esperando indefinidamente ante un texto dificil o una mano temblorosa.
  final int maxAttempts;

  String _candidate = '';
  int _hits = 0;
  int _attempts = 0;

  Future<void> prepare() => _repository.prepare();

  Future<void> release() => _repository.release();

  Future<TextRecognitionResult> call(
    CameraImage image,
    int rotationDegrees,
  ) {
    return _repository.recognizeFrame(image, rotationDegrees);
  }

  /// Devuelve true cuando [result] puede considerarse estable.
  bool confirm(TextRecognitionResult result) {
    final normalized = _normalize(result.fullText);
    if (normalized.isEmpty) {
      _candidate = '';
      _hits = 0;
      _attempts = 0;
      return false;
    }

    _attempts++;

    if (_candidate.isEmpty) {
      _candidate = normalized;
      _hits = 1;
    } else if (similarity(normalized, _candidate) >= similarityThreshold) {
      _hits++;
      // Se conserva la lectura mas larga: suele ser la mas completa.
      if (normalized.length > _candidate.length) _candidate = normalized;
    } else {
      _candidate = normalized;
      _hits = 1;
    }

    if (_hits >= framesToConfirm) return true;
    if (_attempts >= maxAttempts) return true;
    return false;
  }

  void reset() {
    _candidate = '';
    _hits = 0;
    _attempts = 0;
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Indice de Jaccard sobre el conjunto de palabras: 0 = nada en comun,
  /// 1 = exactamente las mismas palabras.
  ///
  /// Se descartan las palabras de una sola letra, que es donde el OCR mas
  /// ruido introduce.
  static double similarity(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;

    final wordsA = a.split(' ').where((w) => w.length > 1).toSet();
    final wordsB = b.split(' ').where((w) => w.length > 1).toSet();
    if (wordsA.isEmpty || wordsB.isEmpty) return 0;

    final shared = wordsA.intersection(wordsB).length;
    final total = wordsA.union(wordsB).length;
    return total == 0 ? 0 : shared / total;
  }
}
