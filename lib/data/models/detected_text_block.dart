// ==========================================================================
// Modelo de datos - texto
// Capa MVVM: Datos
//
// Bloques de texto reconocidos con su posicion normalizada, lista para
// dibujar el resaltado sobre la vista previa.
//
// Requisitos de la ERS que atiende:
//   - RF01 OCR
//   - RF02 realidad aumentada
// ==========================================================================

import 'dart:ui';

/// Bloque de texto devuelto por el OCR, con su posicion normalizada (0..1)
/// respecto al tamano de la imagen analizada. La posicion normalizada permite
/// dibujar el recuadro de realidad aumentada sobre la vista previa sin
/// depender de la resolucion del sensor.
class DetectedTextBlock {
  const DetectedTextBlock({
    required this.text,
    required this.rect,
  });

  final String text;
  final Rect rect;

  @override
  String toString() => 'DetectedTextBlock("$text", $rect)';
}

/// Resultado completo de una pasada de OCR.
class TextRecognitionResult {
  const TextRecognitionResult({
    required this.fullText,
    required this.blocks,
    required this.imageSize,
  });

  const TextRecognitionResult.empty()
      : fullText = '',
        blocks = const [],
        imageSize = Size.zero;

  final String fullText;
  final List<DetectedTextBlock> blocks;
  final Size imageSize;

  bool get isEmpty => fullText.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;
}
