// ==========================================================================
// Servicio de OCR
// Capa MVVM: Datos
//
// ML Kit Text Recognition v2 con el modelo empaquetado en el APK: no
// descarga nada ni consulta ningun servidor.
//
// Requisitos de la ERS que atiende:
//   - RF01 OCR offline
//   - RF04 procesamiento local
//   - RNF-F2 exactitud del OCR
// ==========================================================================

import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/detected_text_block.dart';

/// Reconocimiento optico de caracteres 100 % offline (RF01, RF04).
///
/// Usa **ML Kit Text Recognition v2** con el script latino, que se empaqueta
/// dentro del APK (dependencia `com.google.mlkit:text-recognition` declarada
/// por el plugin) y por tanto no descarga nada ni consulta ningun servidor.
class OcrService {
  OcrService()
      : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;
  bool _closed = false;

  /// Procesa un fotograma del flujo de camara.
  Future<TextRecognitionResult> processFrame(
    CameraImage image,
    int rotationDegrees,
  ) async {
    if (_closed) return const TextRecognitionResult.empty();

    final inputImage = _toInputImage(image, rotationDegrees);
    if (inputImage == null) return const TextRecognitionResult.empty();
    return _recognize(
      inputImage,
      _rotatedSize(image.width, image.height, rotationDegrees),
    );
  }

  /// Procesa una foto ya guardada en disco (modo manual / captura unica).
  Future<TextRecognitionResult> processFile(String path, Size size) async {
    if (_closed) return const TextRecognitionResult.empty();
    return _recognize(InputImage.fromFilePath(path), size);
  }

  Future<TextRecognitionResult> _recognize(
    InputImage inputImage,
    Size imageSize,
  ) async {
    try {
      final recognized = await _recognizer.processImage(inputImage);
      if (recognized.text.trim().isEmpty) {
        return const TextRecognitionResult.empty();
      }

      final w = imageSize.width == 0 ? 1.0 : imageSize.width;
      final h = imageSize.height == 0 ? 1.0 : imageSize.height;

      final blocks = <DetectedTextBlock>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final b = line.boundingBox;
          blocks.add(
            DetectedTextBlock(
              text: line.text,
              rect: Rect.fromLTRB(
                (b.left / w).clamp(0.0, 1.0),
                (b.top / h).clamp(0.0, 1.0),
                (b.right / w).clamp(0.0, 1.0),
                (b.bottom / h).clamp(0.0, 1.0),
              ),
            ),
          );
        }
      }

      return TextRecognitionResult(
        fullText: recognized.text,
        blocks: blocks,
        imageSize: imageSize,
      );
    } catch (e) {
      debugPrint('OcrService: fallo el reconocimiento -> $e');
      return const TextRecognitionResult.empty();
    }
  }

  InputImage? _toInputImage(CameraImage image, int rotationDegrees) {
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees) ??
        InputImageRotation.rotation0deg;

    final format = InputImageFormatValue.fromRawValue(image.format.raw is int
            ? image.format.raw as int
            : 0) ??
        (defaultTargetPlatform == TargetPlatform.android
            ? InputImageFormat.nv21
            : InputImageFormat.bgra8888);

    // Con ImageFormatGroup.nv21 / bgra8888 siempre llega un unico plano.
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Size _rotatedSize(int width, int height, int rotationDegrees) {
    final swapped = rotationDegrees == 90 || rotationDegrees == 270;
    return swapped
        ? Size(height.toDouble(), width.toDouble())
        : Size(width.toDouble(), height.toDouble());
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _recognizer.close();
  }
}
