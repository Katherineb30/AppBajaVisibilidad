import 'dart:ui';

import 'package:baja_vision_app/data/models/banknote_detection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BanknoteDetection build(int valor, {String? etiqueta}) => BanknoteDetection(
        label: etiqueta ?? 'billete_$valor',
        denomination: valor,
        confidence: 0.97,
        rect: const Rect.fromLTRB(0.1, 0.2, 0.8, 0.6),
      );

  test('formatea el importe con separador de miles', () {
    expect(build(1000).displayAmount, r'$1.000');
    expect(build(50000).displayAmount, r'$50.000');
    expect(build(100000).displayAmount, r'$100.000');
  });

  test('la frase hablada no contiene cifras ni simbolos', () {
    final frase = build(20000).spokenPhrase;
    expect(frase, 'Billete de veinte mil pesos');
    expect(RegExp(r'\d').hasMatch(frase), isFalse);
    expect(frase.contains(r'$'), isFalse);
  });

  test('distingue monedas de billetes', () {
    expect(build(500, etiqueta: 'moneda_500').displayName,
        'Moneda de quinientos pesos');
  });
}
