// ==========================================================================
// Modelo de datos - billete
// Capa MVVM: Datos
//
// Deteccion de un billete: denominacion, confianza, caja y si la cifra la
// confirmo el OCR.
//
// Requisitos de la ERS que atiende:
//   - RF03 billetes
//   - RNF-F4 confianza minima
// ==========================================================================

import 'dart:ui';

import '../../core/utils/spanish_number_speller.dart';

/// Deteccion individual producida por el modelo YOLOv8.
class BanknoteDetection {
  const BanknoteDetection({
    required this.label,
    required this.denomination,
    required this.confidence,
    required this.rect,
    this.classIndex = -1,
    this.verifiedByText = false,
  });

  /// true cuando la denominacion la confirmo (o la corrigio) la cifra impresa
  /// leida por el OCR. Es una certeza distinta a la del modelo: no es una
  /// probabilidad, es texto.
  final bool verifiedByText;

  BanknoteDetection copyWith({
    String? label,
    int? denomination,
    double? confidence,
    bool? verifiedByText,
  }) =>
      BanknoteDetection(
        label: label ?? this.label,
        denomination: denomination ?? this.denomination,
        confidence: confidence ?? this.confidence,
        rect: rect,
        classIndex: classIndex,
        verifiedByText: verifiedByText ?? this.verifiedByText,
      );

  /// true si la deteccion viene del modelo de monedas.
  ///
  /// Se decide por la etiqueta y no por un campo aparte, de modo que el
  /// detector no necesita saber que tipo de modelo esta ejecutando: basta con
  /// que su archivo de etiquetas use el prefijo "moneda_". Es la misma
  /// convencion que ya usaba [displayName].
  bool get isCoin => label.toLowerCase().contains('moneda');

  /// Indice crudo que devolvio el modelo. Se conserva para poder distinguir
  /// un fallo del modelo de un desajuste en el archivo de etiquetas.
  final int classIndex;

  /// Etiqueta cruda del modelo, por ejemplo `50000_frente`.
  final String label;

  /// Valor en pesos colombianos. 0 si la etiqueta no es numerica.
  final int denomination;

  /// Confianza 0..1.
  final double confidence;

  /// Caja normalizada 0..1 (left, top, right, bottom).
  final Rect rect;

  /// "$50.000"
  String get displayAmount {
    final s = denomination.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return '\$$buffer';
  }

  /// "Billete de cincuenta mil pesos"
  String get displayName {
    if (denomination <= 0) return label;
    final noun = isCoin ? 'Moneda' : 'Billete';
    return '$noun de ${SpanishNumberSpeller.spellPesos(denomination)}';
  }

  /// Frase que se entrega al motor de voz. Sin simbolos ni cifras: el
  /// sintetizador recibe unicamente palabras, para que la locucion salga
  /// limpia y de corrido.
  String get spokenPhrase => displayName;

  /// Clave estable para evitar repetir el mismo anuncio.
  String get tag => '$denomination';

  @override
  String toString() =>
      'BanknoteDetection($label, $denomination, ${(confidence * 100).toStringAsFixed(1)}%)';
}
