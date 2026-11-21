// ==========================================================================
// Contrato - texto
// Capa MVVM: Dominio
//
// Abstraccion de la que depende el ViewModel. Cambiar de motor de OCR no
// obliga a tocar la interfaz.
//
// Requisitos de la ERS que atiende:
//   - RF01 OCR
// ==========================================================================

import 'package:camera/camera.dart';

import '../../data/models/detected_text_block.dart';

/// Contrato del modulo de reconocimiento de texto.
/// El ViewModel depende de esta abstraccion, nunca de ML Kit directamente.
abstract class ITextRecognitionRepository {
  Future<void> prepare();

  Future<TextRecognitionResult> recognizeFrame(
    CameraImage image,
    int rotationDegrees,
  );

  Future<void> release();
}
