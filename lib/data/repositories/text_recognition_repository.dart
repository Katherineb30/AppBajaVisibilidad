// ==========================================================================
// Repositorio de texto
// Capa MVVM: Datos
//
// Implementa el contrato del dominio sobre el servicio de OCR.
//
// Requisitos de la ERS que atiende:
//   - RF01 OCR
// ==========================================================================

import 'package:camera/camera.dart';

import '../../domain/repositories/i_text_recognition_repository.dart';
import '../models/detected_text_block.dart';
import '../services/ocr_service.dart';

/// Implementacion del contrato del dominio sobre el servicio de OCR.
///
/// Igual que su equivalente de billetes: aisla a las capas superiores del
/// motor concreto (ML Kit) para que este sea sustituible.
class TextRecognitionRepository implements ITextRecognitionRepository {
  TextRecognitionRepository(this._ocr);

  final OcrService _ocr;

  @override
  Future<void> prepare() async {
    // ML Kit v2 inicializa el modelo de forma perezosa en la primera llamada.
  }

  @override
  Future<TextRecognitionResult> recognizeFrame(
    CameraImage image,
    int rotationDegrees,
  ) {
    return _ocr.processFrame(image, rotationDegrees);
  }

  @override
  Future<void> release() => _ocr.dispose();
}
