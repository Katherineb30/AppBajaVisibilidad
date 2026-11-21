import 'package:baja_vision_app/core/utils/banknote_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BanknoteTextParser', () {
    test('lee el formato impreso "N MIL"', () {
      expect(BanknoteTextParser.parse('20 MIL PESOS'), 20000);
      expect(BanknoteTextParser.parse('100 MIL PESOS'), 100000);
      expect(BanknoteTextParser.parse('2 mil pesos'), 2000);
    });

    test('lee la denominacion escrita en palabras', () {
      expect(BanknoteTextParser.parse('CINCUENTA MIL PESOS'), 50000);
      expect(BanknoteTextParser.parse('Diez mil pesos'), 10000);
      expect(BanknoteTextParser.parse('CIEN MIL PESOS'), 100000);
    });

    test('lee cifras con separador de miles', () {
      expect(BanknoteTextParser.parse('50.000'), 50000);
      expect(BanknoteTextParser.parse('2.000 PESOS'), 2000);
    });

    test('ignora anos y numeros de serie', () {
      expect(BanknoteTextParser.parse('2016 AB1234567'), isNull);
      expect(BanknoteTextParser.parse('BANCO DE LA REPUBLICA'), isNull);
    });

    test('calla si el texto contiene dos denominaciones distintas', () {
      expect(BanknoteTextParser.parse('20 MIL ... 50 MIL'), isNull);
    });

    test('acepta el mismo valor repetido en formatos distintos', () {
      expect(
        BanknoteTextParser.parse('20 MIL PESOS  VEINTE MIL PESOS  20.000'),
        20000,
      );
    });

    test('lee la cifra aunque el OCR pierda el punto de los miles', () {
      expect(BanknoteTextParser.parse('10000 DIEZ MIL PESOS'), 10000);
      expect(BanknoteTextParser.parse('20000'), 20000);
      expect(BanknoteTextParser.parse('5000'), 5000);
    });

    test('corrige la O leida en lugar del cero', () {
      expect(BanknoteTextParser.parse('1O.OOO DIEZ MIL PESOS'), 10000);
      expect(BanknoteTextParser.parse('2O.OOO'), 20000);
      expect(BanknoteTextParser.parse('5.OOO'), 5000);
    });

    test('no toca las letras de las palabras', () {
      expect(BanknoteTextParser.parse('BANCO DE LA REPUBLICA DE COLOMBIA'),
          isNull);
    });

    test('gana la denominacion mas repetida', () {
      // Caso real: la cifra del billete sale dos veces y un numero suelto de
      // la escena una sola. Antes el lector callaba; ahora decide por mayoria.
      expect(
        BanknoteTextParser.parse('20.000 VEINTE MIL PESOS 20.000 5.000'),
        20000,
      );
    });

    test('texto completo de cada denominacion', () {
      expect(BanknoteTextParser.parse('5.000 CINCO MIL PESOS'), 5000);
      expect(
        BanknoteTextParser.parse('BANCO DE LA REPUBLICA 10.000 DIEZ MIL PESOS'),
        10000,
      );
      expect(BanknoteTextParser.parse('20.000 VEINTE MIL PESOS COLOMBIA'),
          20000);
    });

    // Texto REAL capturado del dispositivo sobre un billete de cinco mil.
    // ML Kit devuelve los bloques por region de la imagen, no en orden de
    // lectura, de modo que "CINCO" y "MIL" llegan separadas por el numero de
    // serie. Estas cuatro lineas son las que el analizador descartaba.
    test('lee el billete aunque las piezas lleguen sueltas y desordenadas', () {
      expect(
        BanknoteTextParser.parse(
          'PESOS / MIL / 5 / BC45063983 / CINCOo / BC45063983 / '
          'BANCO DE LA REPUBLICA / COLOMBIA',
        ),
        5000,
      );
      expect(
        BanknoteTextParser.parse(
          'MIL / PESOS / 5 / CINCOos / BC45063983 / GIRENTE GENCRAL / '
          'BANCO DE LA REPUBLICA / COLOMBIA',
        ),
        5000,
      );
      expect(
        BanknoteTextParser.parse(
          'MIL / PESOS / BC45063983 / CINCO / GERENTE GENCRAL / '
          'BANCO DE LA REPUBLICA / COLOMBIA',
        ),
        5000,
      );
      expect(
        BanknoteTextParser.parse(
          'MIL / PESOS / 20 / VEINTEo / AB12345678 / BANCO DE LA REPUBLICA',
        ),
        20000,
      );
      expect(
        BanknoteTextParser.parse(
          'PESOS / MIL / DIEZ / 10 / BANCO DE LA REPUBLICA / COLOMBIA',
        ),
        10000,
      );
    });

    test('CINCUENTA no se confunde con CINCO', () {
      expect(
        BanknoteTextParser.parse('MIL / PESOS / CINCUENTA / 50 / BANCO'),
        50000,
      );
      expect(BanknoteTextParser.parse('CINCUENTA MIL PESOS 50.000'), 50000);
    });

    test('un numero suelto sin la palabra MIL no decide nada', () {
      // Sin "MIL" en alguna parte, un "5" aislado no es evidencia de billete.
      expect(BanknoteTextParser.parse('5 BC45063983 COLOMBIA'), isNull);
    });

    // Caso real: la cifra grande del billete llega partida y deja un "2"
    // suelto que votaba por el billete de dos mil y empataba con el verdadero.
    test('un trozo suelto no compite con el numero completo', () {
      expect(
        BanknoteTextParser.parse(
          'NA / MIL / PESOS / BD88314290 / 20* / APROBACION / FECHA DE / '
          'BANCO DE LA REPUBLICA / COLOMBIA / 2',
        ),
        20000,
      );
      // Cincuenta mil no puede leerse como cinco mil.
      expect(
        BanknoteTextParser.parse('MIL / PESOS / 50 / 5 / CINCUENTA / BANCO'),
        50000,
      );
      // Cien mil no puede leerse como diez mil.
      expect(
        BanknoteTextParser.parse('MIL / PESOS / 100 / 10 / CIEN / BANCO'),
        100000,
      );
    });

    test('la palabra del billete gana a una cifra suelta cualquiera', () {
      expect(
        BanknoteTextParser.parse(
          'PESOS / MIL / 20 / VEINTE / BD88314290 / COLOMBIA / 2',
        ),
        20000,
      );
    });

    test('texto vacio o sin cifras', () {
      expect(BanknoteTextParser.parse(''), isNull);
      expect(BanknoteTextParser.parse('   '), isNull);
    });
  });
}
