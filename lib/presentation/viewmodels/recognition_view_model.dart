// ==========================================================================
// ViewModel base
// Capa MVVM: Presentacion
//
// Logica comun a los dos modulos: permisos, ciclo de la camara, ritmo de
// analisis, linterna, avisos audibles y reanudacion automatica. No conoce
// ningun widget.
//
// Requisitos de la ERS que atiende:
//   - RF06 captura
//   - RNF-F3 errores audibles
//   - RNF-D2 consumo
// ==========================================================================

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_strings.dart';
import '../../core/utils/image_converter.dart';
import '../../data/models/recognition_status.dart';
import '../../data/services/camera_service.dart';
import '../../data/services/diagnostics_service.dart';
import '../../data/services/permission_service.dart';
import '../../data/services/tts_service.dart';
import '../../domain/usecases/user_preferences_usecase.dart';

/// Logica comun a los dos modulos de reconocimiento (texto y dinero).
///
/// Es la capa *ViewModel* del patron MVVM: no conoce widgets, expone estado
/// observable mediante [ChangeNotifier] y orquesta los servicios y casos de uso.
abstract class RecognitionViewModel extends ChangeNotifier {
  RecognitionViewModel({
    required this.cameraService,
    required this.permissionService,
    required this.tts,
    required this.diagnostics,
    required this.preferences,
  });

  final CameraService cameraService;
  final PermissionService permissionService;
  final TtsService tts;
  final DiagnosticsService diagnostics;
  final UserPreferencesUseCase preferences;

  /// Nombre del modulo para las estadisticas de RF08.
  String get moduleName;

  // ------------------------------------------------------------------
  // Estado observable
  // ------------------------------------------------------------------
  RecognitionStatus _status = RecognitionStatus.idle;
  RecognitionStatus get status => _status;

  String _hint = '';
  String get hint => _hint;

  bool _autoMode = true;
  bool get autoMode => _autoMode;

  bool _torchOn = false;
  bool get torchOn => _torchOn;

  /// Cuando el usuario acciona la linterna a mano, el automatico deja de
  /// gobernarla hasta que la apague o salga de la pantalla: si no, el ajuste
  /// automatico deshace la decision del usuario a los pocos fotogramas.
  bool _torchManual = false;
  bool get torchManual => _torchManual;

  /// RF02 declara la capa de realidad aumentada como comportamiento
  /// **opcional** que puede desactivarse. A quien no aprovecha el resto visual
  /// no le aporta nada y ahorra trabajo de dibujado.
  bool _overlayEnabled = true;
  bool get overlayEnabled => _overlayEnabled;

  double _progress = 0.0;
  double get progress => _progress;

  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Texto que se leera al pulsar REPETIR.
  String get lastSpokenContent;

  /// Aviso de estado propio de cada modulo ("Buscando texto" / "Buscando billete").
  String get searchingMessage;

  // ------------------------------------------------------------------
  // Control de fotogramas
  // ------------------------------------------------------------------
  bool _processing = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  int _darkFrames = 0;
  int _brightFrames = 0;

  /// Intervalo minimo entre analisis. Evita saturar la CPU y, sobre todo,
  /// evita que el hilo de audio se quede sin recursos y la voz se entrecorte.
  Duration get minInterval => const Duration(milliseconds: 350);

  /// Pausa entre el final de la locucion y la reanudacion de la busqueda.
  /// Da tiempo al usuario a mover el telefono al siguiente objeto.
  Duration get autoResumeDelay => const Duration(milliseconds: 900);

  /// Umbral de luminancia media por debajo del cual se enciende la linterna,
  /// y por encima del cual se apaga. Cada modulo lo ajusta: el detector de
  /// billetes la quiere encendida mucho antes, porque la luz blanca del LED no
  /// solo ilumina, tambien corrige la dominante de color de una bombilla
  /// incandescente, que es lo que confunde denominaciones de tono parecido.
  double get torchOnBelow => 55;
  double get torchOffAbove => 85;

  /// Aviso hablado al encenderla sola.
  String get torchReason => AppStrings.lowLight;

  /// Tiempo que debe pasar para volver a anunciar EL MISMO contenido.
  /// Sin esta ventana, apuntar fijo a un mismo papel repetiria la lectura en
  /// bucle; con ella, si el usuario vuelve a enfocarlo mas tarde, se relee.
  Duration get repeatWindow => const Duration(seconds: 6);

  String? _lastAnnouncedTag;
  DateTime _lastAnnouncedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// True si [tag] es contenido nuevo (o si ya paso [repeatWindow]).
  @protected
  bool shouldAnnounce(String tag) {
    final now = DateTime.now();
    final isSame = tag == _lastAnnouncedTag;
    final expired = now.difference(_lastAnnouncedAt) > repeatWindow;
    if (isSame && !expired) return false;
    _lastAnnouncedTag = tag;
    _lastAnnouncedAt = now;
    return true;
  }

  /// Reinicia los acumuladores del modulo para empezar una lectura nueva.
  /// Las subclases lo sobrescriben; el resultado en pantalla se conserva.
  @protected
  void prepareNextScan() {}

  // ------------------------------------------------------------------
  // Ciclo de vida
  // ------------------------------------------------------------------

  Future<void> initialize() async {
    _setStatus(RecognitionStatus.requestingPermission);

    final granted = await permissionService.hasCamera()
        ? true
        : await permissionService.requestCamera();

    if (!granted) {
      _hint = AppStrings.cameraPermissionBody;
      _setStatus(RecognitionStatus.permissionDenied);
      await tts.speakResult(AppStrings.cameraPermissionBody);
      return;
    }

    await _cargarPreferencias();
    try {
      await prepareModule();
      await cameraService.initialize();
      await cameraService.startStream(_onFrame);
      _hint = searchingMessage;
      _setStatus(RecognitionStatus.searching);

      // Se espera a que TalkBack termine de anunciar la pantalla antes de
      // decir nada: asi las dos voces no se pisan.
      await tts.waitForScreenReader();
      await tts.speakStatus(searchingMessage);
    } catch (e, st) {
      diagnostics.recordError('inicializacion/$moduleName', e, st);
      debugPrint('RecognitionViewModel: fallo la inicializacion -> $e');
      _hint = AppStrings.cameraUnavailable;
      _setStatus(RecognitionStatus.error);
      // RNF-F3: mensaje audible y con una salida clara, no un texto mudo.
      await tts.speakResult(
        '${AppStrings.cameraUnavailable} ${AppStrings.errorAlternative}',
      );
    }
  }

  /// Lee de la base de datos local como dejo el usuario la realidad
  /// aumentada y la deteccion automatica. Si falla, sigue con los valores
  /// por defecto: la app nunca se detiene por esto.
  Future<void> _cargarPreferencias() async {
    try {
      _overlayEnabled = await preferences.cargarRealidadAumentada();
      _autoMode = await preferences.cargarDeteccionAutomatica();
      notifyListeners();
    } catch (e, st) {
      diagnostics.recordError('preferencias/$moduleName', e, st);
    }
  }

  /// Preparacion especifica del modulo (cargar modelo, abrir el OCR...).
  Future<void> prepareModule();

  /// Analisis de un fotograma. Debe devolver true si se obtuvo un resultado
  /// confirmado (en ese caso el estado pasa a success).
  Future<bool> analyze(CameraImage image, int rotation);

  /// Limpia el resultado y vuelve a buscar.
  void resumeSearch() {
    if (_disposed) return;
    _progress = 0;
    _hint = searchingMessage;
    _setStatus(RecognitionStatus.searching);
  }

  // ------------------------------------------------------------------
  // Acciones de la vista
  // ------------------------------------------------------------------

  /// Control manual de la linterna.
  ///
  /// Se acciona con el boton de la barra superior o manteniendo pulsada la
  /// vista de camara. Desde el primer toque, el automatico deja de intervenir
  /// hasta que se vuelva a entrar al modulo.
  Future<void> toggleTorch() async {
    _torchManual = true;
    _torchOn = !_torchOn;
    HapticFeedback.mediumImpact();
    await cameraService.setTorch(_torchOn);
    notifyListeners();
    // Este aviso SI se dice siempre, tambien con TalkBack activo: es la
    // confirmacion de una accion que el usuario acaba de hacer y que no puede
    // comprobar mirando la pantalla.
    await tts.speakResult(
      _torchOn ? AppStrings.torchOnSpoken : AppStrings.torchOffSpoken,
      tag: 'linterna-$_torchOn',
      force: true,
    );
    // El pestillo manual NO se suelta al apagarla.
    //
    // Antes si se soltaba, y el resultado era que apagarla no servia de nada:
    // bajo una bombilla calida el automatico la volvia a encender a los pocos
    // fotogramas y el usuario no tenia forma de impedirlo. A partir del primer
    // toque manda la persona; el automatico vuelve a actuar al entrar de nuevo
    // al modulo, porque este ViewModel se crea con cada pantalla.
    _darkFrames = 0;
    _brightFrames = 0;
  }

  Future<void> toggleOverlay() async {
    _overlayEnabled = !_overlayEnabled;
    unawaited(preferences.guardarRealidadAumentada(_overlayEnabled));
    HapticFeedback.selectionClick();
    notifyListeners();
    await tts.speakStatus(
      _overlayEnabled
          ? 'Resaltado visual activado'
          : 'Resaltado visual desactivado',
    );
  }

  /// Comunica un problema de forma **audible** y no solo en pantalla
  /// (RNF-F3). Se respeta una ventana para no repetirlo en bucle.
  @protected
  Future<void> announceProblem(String message, {String? tag}) async {
    setHint(message);
    if (shouldAnnounce(tag ?? message)) {
      await tts.speakResult(message, tag: tag ?? message);
    }
  }

  Future<void> toggleAutoMode() async {
    _autoMode = !_autoMode;
    unawaited(preferences.guardarDeteccionAutomatica(_autoMode));
    HapticFeedback.selectionClick();
    notifyListeners();
    await tts.speakStatus(
      _autoMode ? 'Deteccion automatica activada' : 'Deteccion manual activada',
    );
  }

  /// Disparo manual: se usa tocando la vista previa cuando AUTO esta apagado.
  Future<void> captureNow() async {
    if (_autoMode) return;
    _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
    _setStatus(RecognitionStatus.analyzing);
    HapticFeedback.mediumImpact();
  }

  /// Repite en voz alta el ultimo resultado, completo y desde el principio.
  Future<void> repeatLast() async {
    final content = lastSpokenContent;
    HapticFeedback.selectionClick();
    if (content.trim().isEmpty) {
      await tts.speakResult(searchingMessage, force: true);
      return;
    }
    await tts.repeat(content);
  }

  Future<void> requestPermissionAgain() async {
    if (await permissionService.isPermanentlyDenied()) {
      await permissionService.openSettings();
      return;
    }
    await initialize();
  }

  // ------------------------------------------------------------------
  // Flujo de camara
  // ------------------------------------------------------------------

  void _onFrame(CameraImage image) {
    if (_disposed || _processing) return;

    // Mientras la voz esta leyendo un resultado no se analiza nada: el
    // usuario necesita oir la frase entera y la CPU debe quedar libre.
    if (tts.isSpeaking.value) return;

    if (_status == RecognitionStatus.success) return;
    if (!_autoMode && _status != RecognitionStatus.analyzing) return;

    final now = DateTime.now();
    if (now.difference(_lastProcessed) < minInterval) return;
    _lastProcessed = now;

    _processing = true;
    _handleFrame(image).whenComplete(() => _processing = false);
  }

  Future<void> _handleFrame(CameraImage image) async {
    _updateTorch(image);

    if (_status != RecognitionStatus.analyzing) {
      _setStatus(RecognitionStatus.analyzing);
    }
    _bumpProgress();

    final cronometro = Stopwatch()..start();
    try {
      final found = await analyze(image, cameraService.sensorRotation);
      cronometro.stop();
      diagnostics.recordRecognition(
        moduleName,
        cronometro.elapsedMilliseconds,
        success: found,
      );
      if (_disposed) return;
      if (found) {
        _progress = 1.0;
        _setStatus(RecognitionStatus.success);
        HapticFeedback.heavyImpact();
        // Modo continuo: no hay que pulsar nada para la siguiente lectura.
        unawaited(_autoContinue());
      } else if (_status != RecognitionStatus.success) {
        _setStatus(RecognitionStatus.searching);
      }
    } catch (e, st) {
      cronometro.stop();
      diagnostics.recordError('analisis/$moduleName', e, st);
      debugPrint('RecognitionViewModel: error analizando -> $e');
      if (!_disposed) _setStatus(RecognitionStatus.searching);
    }
  }

  /// Vuelve a buscar automaticamente en cuanto la voz ha terminado.
  ///
  /// Es el comportamiento por defecto: la aplicacion la usan personas que no
  /// ven la pantalla, asi que no puede depender de que pulsen un boton para
  /// continuar. Se espera a que la locucion acabe entera para no cortarla.
  Future<void> _autoContinue() async {
    await tts.waitUntilDone();
    if (_disposed) return;
    await Future<void>.delayed(autoResumeDelay);
    if (_disposed || !_autoMode) return;
    if (_status != RecognitionStatus.success) return;

    prepareNextScan();
    _progress = 0;
    _setStatus(RecognitionStatus.searching);
  }

  void _bumpProgress() {
    _progress = (_progress + 0.18).clamp(0.0, 0.96);
    notifyListeners();
  }

  /// Linterna automatica: se enciende con poca luz y se apaga al recuperarla.
  /// La histeresis (varios fotogramas seguidos) evita el parpadeo molesto.
  void _updateTorch(CameraImage image) {
    if (_torchManual) return;
    final luma = ImageConverter.averageLuminance(image);
    if (luma < torchOnBelow) {
      _darkFrames++;
      _brightFrames = 0;
    } else if (luma > torchOffAbove) {
      _brightFrames++;
      _darkFrames = 0;
    }

    if (!_torchOn && _darkFrames >= 4) {
      _torchOn = true;
      cameraService.setTorch(true);
      tts.speakStatus(torchReason);
      notifyListeners();
    } else if (_torchOn && _brightFrames >= 8) {
      _torchOn = false;
      cameraService.setTorch(false);
      notifyListeners();
    }
  }

  void _setStatus(RecognitionStatus value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }

  @protected
  void setHint(String value) {
    if (_hint == value) return;
    _hint = value;
    notifyListeners();
  }

  @protected
  void markSuccess() => _setStatus(RecognitionStatus.success);

  @protected
  void markNotFound() => _setStatus(RecognitionStatus.notFound);

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  Future<void> shutdown() async {
    await cameraService.stopStream();
    await cameraService.setTorch(false);
    await cameraService.dispose();
    await tts.stop();
    await releaseModule();
  }

  Future<void> releaseModule();

  @override
  void dispose() {
    _disposed = true;
    unawaited(shutdown());
    super.dispose();
  }
}
