// ==========================================================================
// ViewModel de TEXTO
// Capa MVVM: Presentacion
//
// Orquesta el OCR, la estabilizacion y la lectura en voz alta.
//
// Requisitos de la ERS que atiende:
//   - RF01 OCR
//   - RF05 voz
//   - CU01
// ==========================================================================

import 'package:camera/camera.dart';

import '../../core/constants/app_strings.dart';
import '../../core/utils/speech_text_formatter.dart';
import '../../data/models/detected_text_block.dart';
import '../../data/services/diagnostics_service.dart';
import '../../domain/usecases/recognize_text_usecase.dart';
import 'recognition_view_model.dart';

/// ViewModel del modulo TEXTO (CU01, CU05, CU06).
class TextViewModel extends RecognitionViewModel {
  TextViewModel({
    required super.cameraService,
    required super.permissionService,
    required super.tts,
    required super.diagnostics,
    required RecognizeTextUseCase recognizeText,
  }) : _recognizeText = recognizeText;

  final RecognizeTextUseCase _recognizeText;

  TextRecognitionResult _result = const TextRecognitionResult.empty();
  TextRecognitionResult get result => _result;

  String _displayText = '';
  String get displayText => _displayText;

  List<DetectedTextBlock> get blocks => _result.blocks;

  @override
  String get lastSpokenContent => _displayText;

  @override
  String get moduleName => DiagnosticsService.textModule;

  @override
  String get searchingMessage => AppStrings.searchingText;

  /// El OCR es rapido: se puede analizar con mas frecuencia que el detector.
  @override
  Duration get minInterval => const Duration(milliseconds: 320);

  @override
  Future<void> prepareModule() => _recognizeText.prepare();

  @override
  Future<bool> analyze(CameraImage image, int rotation) async {
    final recognized = await _recognizeText(image, rotation);

    if (recognized.isEmpty) {
      _recognizeText.confirm(recognized);
      return false;
    }

    // Indicador audible de encuadre (interfaz de usuario 3.1.1): si el texto
    // se ve pero sale diminuto, el OCR fallara; se avisa antes de intentarlo.
    if (_looksTooSmall(recognized.blocks)) {
      await announceProblem(AppStrings.moveCloser, tag: 'acercar-texto');
      return false;
    }

    // El resaltado de realidad aumentada se pinta en cuanto hay bloques,
    // aunque el texto todavia no este confirmado (RF02).
    _result = recognized;
    notifyListeners();

    if (!_recognizeText.confirm(recognized)) return false;

    _displayText = SpeechTextFormatter.forDisplay(recognized.fullText);
    setHint(AppStrings.detectedTextLabel);
    notifyListeners();

    // Lectura completa y sin interrupciones del texto reconocido (RF05).
    // Si es el mismo texto que se acaba de leer no se repite: el modo
    // continuo seguira buscando hasta que aparezca contenido distinto.
    if (shouldAnnounce(_displayText)) {
      await tts.speakResult(recognized.fullText, tag: _displayText);
    }
    return true;
  }

  /// Prepara la siguiente lectura. Se limpian los bloques resaltados para que
  /// el overlay no siga marcando el texto anterior; el texto leido se conserva
  /// en pantalla y en REPETIR hasta que llegue uno nuevo.
  @override
  void prepareNextScan() {
    _recognizeText.reset();
    _result = const TextRecognitionResult.empty();
    notifyListeners();
  }

  /// Altura media de los bloques respecto al alto de la imagen. Por debajo
  /// del 2 % el texto es demasiado pequeno para reconocerse con fiabilidad.
  static bool _looksTooSmall(List<DetectedTextBlock> blocks) {
    if (blocks.isEmpty) return false;
    final media =
        blocks.map((b) => b.rect.height).reduce((a, b) => a + b) / blocks.length;
    return media < 0.02;
  }

  /// Descarta el resultado y vuelve a buscar texto nuevo.
  void scanAgain() {
    _recognizeText.reset();
    _result = const TextRecognitionResult.empty();
    _displayText = '';
    resumeSearch();
  }

  @override
  Future<void> releaseModule() => _recognizeText.release();
}
