// ==========================================================================
// Normalizador de voz
// Capa MVVM: Core
//
// Prepara el texto antes de entregarlo al sintetizador: cifras a palabras,
// palabras partidas reunidas, simbolos fuera y troceado en limites de frase.
// Sin este paso la locucion suena entrecortada.
//
// Requisitos de la ERS que atiende:
//   - RF05 salida por voz
// ==========================================================================

import 'spanish_number_speller.dart';

/// Normaliza el texto antes de entregarselo al motor TTS.
///
/// Sin este paso la locucion suena entrecortada ("tartamuda"): el OCR devuelve
/// saltos de linea en mitad de las frases, palabras partidas con guion,
/// simbolos que el sintetizador deletrea uno a uno y cifras que lee digito a
/// digito. Aqui se reconstruye un parrafo continuo y pronunciable.
class SpeechTextFormatter {
  const SpeechTextFormatter._();

  /// Caracteres que el motor deletrea o convierte en pausas absurdas.
  static final RegExp _noise = RegExp(r'[|_~^`*<>\[\]{}\\/@#•·¬°=+]');

  /// Palabra partida al final de renglon: "conti-\nnuacion".
  static final RegExp _hyphenBreak = RegExp(r'-\s*\n\s*');

  /// Cifras con separador de miles: 12.500 / 12,500 / 1 000 000.
  static final RegExp _groupedNumber =
      RegExp(r'\b\d{1,3}(?:[.,  ]\d{3})+\b');

  /// Cifra simple de 2 o mas digitos.
  static final RegExp _plainNumber = RegExp(r'\b\d{2,}\b');

  static final RegExp _multiSpace = RegExp(r'[ \t]{2,}');
  static final RegExp _multiNewline = RegExp(r'\n{2,}');

  static const Map<String, String> _abbreviations = {
    r'\$': 'pesos ',
    '%': ' por ciento',
    '&': ' y ',
    'Nro.': 'numero',
    'No.': 'numero',
    'Cra.': 'carrera',
    'Cll.': 'calle',
    'Av.': 'avenida',
    'Dr.': 'doctor',
    'Dra.': 'doctora',
    'Sr.': 'senor',
    'Sra.': 'senora',
    'Ud.': 'usted',
    'etc.': 'etcetera',
    'kg': 'kilogramos',
    'ml': 'mililitros',
  };

  /// Prepara [raw] para ser hablado de corrido.
  static String forSpeech(String raw) {
    if (raw.trim().isEmpty) return '';

    var t = raw;

    // 1. Reunir palabras partidas por guion al final de renglon.
    t = t.replaceAll(_hyphenBreak, '');

    // 2. Eliminar simbolos que el sintetizador deletrearia.
    t = t.replaceAll(_noise, ' ');

    // 3. Expandir el simbolo de moneda ANTES de convertir cifras,
    //    para que "$12.500" quede como "doce mil quinientos pesos".
    t = _expandCurrency(t);

    // 4. Abreviaturas frecuentes.
    _abbreviations.forEach((key, value) {
      if (key == r'\$') return; // ya tratado en _expandCurrency
      t = t.replaceAll(key, value);
    });

    // 5. Cifras -> palabras.
    t = t.replaceAllMapped(_groupedNumber, (m) {
      final digits = m[0]!.replaceAll(RegExp(r'[.,  ]'), '');
      final n = int.tryParse(digits);
      return n == null ? m[0]! : SpanishNumberSpeller.spell(n);
    });
    t = t.replaceAllMapped(_plainNumber, (m) {
      final n = int.tryParse(m[0]!);
      if (n == null || n > 999999999) return m[0]!;
      return SpanishNumberSpeller.spell(n);
    });

    // 6. Los saltos de linea del OCR NO son finales de frase: se convierten en
    //    una coma corta para que la voz respire pero no se corte.
    t = t.replaceAll(_multiNewline, '. ');
    t = t.replaceAll('\n', ', ');

    // 7. Compactar espacios y limpiar puntuacion redundante.
    t = t.replaceAll(_multiSpace, ' ');
    t = t.replaceAll(RegExp(r'\s+([,.;:])'), r'$1');
    t = t.replaceAll(RegExp(r'([,.;:]){2,}'), r'$1');
    t = t.replaceAll(RegExp(r',\s*\.'), '.');
    t = t.trim();

    // 8. Cerrar con punto: algunas voces de Android recortan la ultima silaba
    //    cuando el enunciado no termina en signo de puntuacion.
    if (t.isNotEmpty && !RegExp(r'[.!?]$').hasMatch(t)) {
      t = '$t.';
    }
    return t;
  }

  /// Version corta y legible del texto para mostrarlo en pantalla
  /// (conserva las cifras tal como aparecen en el original).
  static String forDisplay(String raw) {
    return raw
        .replaceAll(_hyphenBreak, '')
        .replaceAll(_multiNewline, '\n')
        .replaceAll(_multiSpace, ' ')
        .trim();
  }

  static String _expandCurrency(String input) {
    // $ 12.500  |  $12.500  |  COP 12.500
    final re = RegExp(r'(?:\$|COP)\s*(\d{1,3}(?:[.,  ]\d{3})+|\d+)');
    return input.replaceAllMapped(re, (m) {
      final digits = m[1]!.replaceAll(RegExp(r'[.,  ]'), '');
      final n = int.tryParse(digits);
      if (n == null) return m[0]!;
      return SpanishNumberSpeller.spellPesos(n);
    });
  }

  /// Divide un texto largo en fragmentos pronunciables.
  ///
  /// El motor TTS de Android limita cada enunciado a unos 4000 caracteres y,
  /// en textos muy largos, algunas voces se atascan. Se corta SIEMPRE en un
  /// limite de frase para que ningun fragmento empiece a media palabra: asi la
  /// lectura encadenada se percibe continua.
  static List<String> chunk(String text, {int maxChars = 380}) {
    final clean = text.trim();
    if (clean.isEmpty) return const [];
    if (clean.length <= maxChars) return [clean];

    final sentences = clean.split(RegExp(r'(?<=[.!?])\s+'));
    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final s = buffer.toString().trim();
      if (s.isNotEmpty) chunks.add(s);
      buffer.clear();
    }

    for (final sentence in sentences) {
      if (sentence.length > maxChars) {
        flush();
        // Frase gigantesca sin puntuacion: cortar por comas y, en ultimo
        // caso, por espacios; nunca a mitad de palabra.
        for (final piece in _splitLong(sentence, maxChars)) {
          chunks.add(piece);
        }
        continue;
      }
      if (buffer.length + sentence.length + 1 > maxChars) flush();
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(sentence);
    }
    flush();
    return chunks;
  }

  static List<String> _splitLong(String sentence, int maxChars) {
    final out = <String>[];
    final words = sentence.split(' ');
    final buffer = StringBuffer();
    for (final w in words) {
      if (buffer.length + w.length + 1 > maxChars && buffer.isNotEmpty) {
        out.add(buffer.toString().trim());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(w);
    }
    if (buffer.isNotEmpty) out.add(buffer.toString().trim());
    return out;
  }
}
