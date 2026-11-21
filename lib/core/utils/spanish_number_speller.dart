// ==========================================================================
// Cifras a palabras
// Capa MVVM: Core
//
// Convierte cantidades a su forma escrita en espanol. Entregar "12.500" al
// sintetizador produce lecturas ininteligibles; "doce mil quinientos" no.
//
// Requisitos de la ERS que atiende:
//   - RF05 salida por voz
// ==========================================================================

/// Convierte cantidades numericas a palabras en espanol.
///
/// Es imprescindible para la lectura por voz: si al motor TTS se le entrega
/// "12.500" muchas voces lo leen como "doce punto quinientos" o deletrean los
/// digitos, lo que resulta ininteligible para el usuario. Entregandole
/// "doce mil quinientos" la locucion sale limpia y continua.
class SpanishNumberSpeller {
  const SpanishNumberSpeller._();

  static const List<String> _units = [
    'cero', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho',
    'nueve', 'diez', 'once', 'doce', 'trece', 'catorce', 'quince', 'dieciseis',
    'diecisiete', 'dieciocho', 'diecinueve', 'veinte', 'veintiuno',
    'veintidos', 'veintitres', 'veinticuatro', 'veinticinco', 'veintiseis',
    'veintisiete', 'veintiocho', 'veintinueve',
  ];

  static const List<String> _tens = [
    '', '', '', 'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta',
    'ochenta', 'noventa',
  ];

  static const List<String> _hundreds = [
    '', 'ciento', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos',
    'seiscientos', 'setecientos', 'ochocientos', 'novecientos',
  ];

  /// Devuelve [value] escrito en palabras. Soporta hasta 999.999.999.
  static String spell(int value) {
    if (value < 0) return 'menos ${spell(-value)}';
    if (value < 30) return _units[value];
    if (value < 100) {
      final t = value ~/ 10;
      final u = value % 10;
      return u == 0 ? _tens[t] : '${_tens[t]} y ${_units[u]}';
    }
    if (value == 100) return 'cien';
    if (value < 1000) {
      final h = value ~/ 100;
      final rest = value % 100;
      return rest == 0 ? _hundreds[h] : '${_hundreds[h]} ${spell(rest)}';
    }
    if (value < 1000000) {
      final thousands = value ~/ 1000;
      final rest = value % 1000;
      final head = thousands == 1 ? 'mil' : '${spell(thousands)} mil';
      return rest == 0 ? head : '$head ${spell(rest)}';
    }
    final millions = value ~/ 1000000;
    final rest = value % 1000000;
    final head = millions == 1 ? 'un millon' : '${spell(millions)} millones';
    return rest == 0 ? head : '$head ${spell(rest)}';
  }

  /// Version monetaria: "doce mil quinientos pesos".
  static String spellPesos(int value) {
    final words = spell(value);
    // "uno" -> "un peso"; el resto siempre en plural.
    if (value == 1) return 'un peso';
    return '$words pesos';
  }
}
