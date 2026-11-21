// ==========================================================================
// Servicio de camara
// Capa MVVM: Datos
//
// Camara trasera, enfoque y exposicion automaticos, flujo de fotogramas,
// linterna y calculo de la rotacion del sensor.
//
// Requisitos de la ERS que atiende:
//   - RF06 captura de imagen
// ==========================================================================

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Encapsula la camara trasera del dispositivo.
///
/// Configuracion pensada para el reconocimiento:
/// * `ImageFormatGroup.nv21` en Android, que es el formato que ML Kit acepta
///   directamente y el mas barato de convertir a RGB para TFLite.
/// * Enfoque y exposicion automaticos continuos.
/// * Linterna gobernada por la luminancia del fotograma.
/// * Sin audio: la app no graba nada.
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _streaming = false;
  bool _torchOn = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isStreaming => _streaming;
  bool get torchOn => _torchOn;

  CameraDescription? get description => _controller?.description;

  /// Inicializa la camara trasera. Lanza [CameraException] si no hay camara.
  Future<void> initialize() async {
    if (isInitialized) return;

    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      throw CameraException('sin_camara', 'El dispositivo no reporta camaras.');
    }

    final back = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    // Resolucion: "veryHigh" (1080p) en lugar de "high" (720p).
    //
    // El coste para el detector es casi nulo, porque el preprocesado recorre
    // los 640x640 pixeles de SALIDA y no los de entrada. La ganancia, en
    // cambio, va entera al OCR: la cifra impresa en el billete pasa a tener
    // mas del doble de pixeles, y es justo la que decide entre 5, 10 y 20 mil
    // cuando el color no basta. Si el dispositivo no admite 1080p se vuelve a
    // 720p en vez de dejar la camara sin abrir.
    var controller = _crearControlador(back, ResolutionPreset.veryHigh);
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      debugPrint('CameraService: 1080p no disponible ($e), se usa 720p.');
      await controller.dispose();
      controller = _crearControlador(back, ResolutionPreset.high);
      await controller.initialize();
    }
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setFlashMode(FlashMode.off);
    } on CameraException catch (e) {
      debugPrint('CameraService: ajuste no soportado -> ${e.description}');
    }

    _controller = controller;
  }

  CameraController _crearControlador(
    CameraDescription camara,
    ResolutionPreset resolucion,
  ) {
    return CameraController(
      camara,
      resolucion,
      enableAudio: false,
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
  }

  /// Arranca el flujo de fotogramas. El callback debe ser rapido: si tarda,
  /// se deben descartar fotogramas en el llamador.
  Future<void> startStream(void Function(CameraImage image) onFrame) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_streaming) return;
    await controller.startImageStream(onFrame);
    _streaming = true;
  }

  Future<void> stopStream() async {
    final controller = _controller;
    if (controller == null || !_streaming) return;
    try {
      await controller.stopImageStream();
    } on CameraException catch (e) {
      debugPrint('CameraService: stopImageStream -> ${e.description}');
    }
    _streaming = false;
  }

  /// Enciende o apaga la linterna. Silencioso si el dispositivo no la tiene.
  Future<void> setTorch(bool on) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_torchOn == on) return;
    try {
      await controller.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      _torchOn = on;
    } on CameraException catch (e) {
      debugPrint('CameraService: linterna no disponible -> ${e.description}');
    }
  }

  /// Rotacion, en grados, que hay que aplicar al fotograma para que quede
  /// derecho. La necesitan tanto ML Kit como el modelo de billetes.
  int get sensorRotation {
    final controller = _controller;
    if (controller == null) return 0;
    final sensorOrientation = controller.description.sensorOrientation;
    if (defaultTargetPlatform != TargetPlatform.android) {
      return sensorOrientation;
    }
    const compensation = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final device = compensation[controller.value.deviceOrientation] ?? 0;
    if (controller.description.lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + device) % 360;
    }
    return (sensorOrientation - device + 360) % 360;
  }

  Future<void> dispose() async {
    await stopStream();
    await setTorch(false);
    await _controller?.dispose();
    _controller = null;
  }
}
