import 'package:baja_vision_app/core/utils/speech_text_formatter.dart';
import 'package:baja_vision_app/core/utils/spanish_number_speller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpanishNumberSpeller', () {
    test('escribe cifras habituales de los billetes', () {
      expect(SpanishNumberSpeller.spell(1000), 'mil');
      expect(SpanishNumberSpeller.spell(2000), 'dos mil');
      expect(SpanishNumberSpeller.spell(12500), 'doce mil quinientos');
      expect(SpanishNumberSpeller.spell(50000), 'cincuenta mil');
      expect(SpanishNumberSpeller.spell(100000), 'cien mil');
    });

    test('usa el plural correcto en pesos', () {
      expect(SpanishNumberSpeller.spellPesos(1), 'un peso');
      expect(SpanishNumberSpeller.spellPesos(20000), 'veinte mil pesos');
    });
  });

  group('SpeechTextFormatter', () {
    test('convierte precios a palabras', () {
      final r = SpeechTextFormatter.forSpeech(r'Precio: $12.500');
      expect(r, contains('doce mil quinientos pesos'));
      expect(r, isNot(contains(r'$')));
    });

    test('reune palabras partidas y no deja saltos de linea', () {
      final r = SpeechTextFormatter.forSpeech('conti-\nnuacion\nde la frase');
      expect(r, contains('continuacion'));
      expect(r, isNot(contains('\n')));
    });

    test('cierra siempre con punto para que no se corte la ultima silaba', () {
      expect(SpeechTextFormatter.forSpeech('Oferta especial'), endsWith('.'));
    });

    test('elimina simbolos que el sintetizador deletrearia', () {
      final r = SpeechTextFormatter.forSpeech('Total ** 5 | unidades');
      expect(r, isNot(contains('*')));
      expect(r, isNot(contains('|')));
    });

    test('trocea solo en limites de frase', () {
      final texto = List.filled(40, 'Esta es una frase de prueba.').join(' ');
      final trozos = SpeechTextFormatter.chunk(texto, maxChars: 120);
      expect(trozos.length, greaterThan(1));
      for (final t in trozos) {
        expect(t.trim(), isNotEmpty);
        expect(t.trim().endsWith('.'), isTrue);
      }
    });

    test('un texto corto no se trocea', () {
      expect(SpeechTextFormatter.chunk('Hola mundo.').length, 1);
    });
  });
}
