// ==========================================================================
// Contrato - billetes
// Capa MVVM: Dominio
//
// Abstraccion del detector. Cambiar de motor de inferencia no afecta a la
// capa de presentacion.
//
// Requisitos de la ERS que atiende:
//   - RF03 billetes
// ==========================================================================

import 'package:camera/camera.dart';

import '../../data/models/banknote_detection.dart';

/// Contrato del modulo de reconocimiento de billetes.
abstract class IBanknoteRepository {
  Future<void> prepare();

  bool get isModelReady;

  String? get modelError;

  Future<List<BanknoteDetection>> detectFrame(
    CameraImage image,
    int rotationDegrees,
  );

  Future<void> release();
}
