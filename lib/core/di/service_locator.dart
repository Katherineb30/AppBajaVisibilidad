// ==========================================================================
// Inyeccion de dependencias
// Capa MVVM: Core
//
// Servicios de sesion (voz, permisos, diagnostico, modelo) y fabricas de los
// que se crean y liberan por pantalla (camara y motores de reconocimiento).
// ==========================================================================

import '../../data/repositories/banknote_repository.dart';
import '../../data/repositories/text_recognition_repository.dart';
import '../../data/services/banknote_detector_service.dart';
import '../../data/services/camera_service.dart';
import '../../data/services/diagnostics_service.dart';
import '../../data/services/model_storage_service.dart';
import '../../data/services/ocr_service.dart';
import '../../data/services/permission_service.dart';
import '../../data/services/tts_service.dart';
import '../../domain/usecases/detect_banknote_usecase.dart';
import '../../domain/usecases/recognize_text_usecase.dart';

/// Inyeccion de dependencias sencilla y explicita.
///
/// [tts], [permissions], [diagnostics] y [modelStorage] viven durante toda la
/// sesion; la camara y los motores de reconocimiento se crean por pantalla y
/// se liberan al salir, para no mantener el sensor ni el modelo en memoria
/// cuando no se usan.
class ServiceLocator {
  ServiceLocator._();

  static final ServiceLocator instance = ServiceLocator._();

  final TtsService tts = TtsService();
  final PermissionService permissions = const PermissionService();

  /// Modo de diagnostico y registro local (RF08, RF10).
  final DiagnosticsService diagnostics = DiagnosticsService();

  /// Gestion del modelo activo y sus actualizaciones (RF07, RNF-S3).
  final ModelStorageService modelStorage = ModelStorageService();

  /// Lo mismo para el modelo de monedas, que es un archivo aparte con su
  /// propio ciclo de actualizacion.
  final ModelStorageService modelStorageMonedas = ModelStorageService(
    fileName: 'monedas.tflite',
    assetPath: 'assets/models/monedas.tflite',
  );

  CameraService newCameraService() => CameraService();

  RecognizeTextUseCase newRecognizeTextUseCase() =>
      RecognizeTextUseCase(TextRecognitionRepository(OcrService()));

  /// Modulo DINERO: dos detectores independientes.
  ///
  /// El de billetes queda exactamente como estaba. El de monedas usa su propio
  /// modelo y su propio archivo de etiquetas, y lleva un umbral de confianza
  /// algo mas alto: un modelo entrenado solo con monedas nunca vio un billete,
  /// asi que ante uno puede dar un falso positivo convencido. Exigirle un poco
  /// mas evita que le gane a una deteccion de billete correcta.
  DetectBanknoteUseCase newDetectBanknoteUseCase() => DetectBanknoteUseCase(
        BanknoteRepository(
          BanknoteDetectorService(storage: modelStorage),
          monedas: BanknoteDetectorService(
            storage: modelStorageMonedas,
            modelAsset: 'assets/models/monedas.tflite',
            labelsAsset: 'assets/labels/monedas.txt',
            confidenceThreshold: 0.50,
          ),
        ),
      );

  /// Preparacion en segundo plano: no debe bloquear el primer fotograma
  /// (RNF-R4: la aplicacion lista para capturar en menos de 3 segundos).
  void warmUp() {
    tts.init();
    diagnostics.loadIfNeeded();
  }

  void dispose() => tts.dispose();
}
