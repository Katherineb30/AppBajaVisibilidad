// ==========================================================================
// Lector de la cifra impresa
// Capa MVVM: Core
//
// Extrae la denominacion escrita en el billete a partir del texto del OCR.
// Es la segunda fuente de verdad del modulo de dinero: no depende del color,
// asi que no la enganan las dominantes de iluminacion.
//
// Requisitos de la ERS que atiende:
//   - RF03 reconocimiento de billetes
//   - RNF-F1 exactitud
// ==========================================================================

/// Extrae la denominacion impresa en un billete a partir del texto que
/// devuelve el OCR.
///
/// Sirve de contraste al modelo de vision: el reconocimiento de texto trabaja
/// sobre la luminancia y no sobre el color, asi que no le afecta la dominante
/// de una bombilla incandescente, que es justo lo que confunde al detector
/// entre denominaciones de tono parecido. Cuando la cifra impresa se lee con
/// claridad, es informacion inequivoca y no una probabilidad.
///
/// **El texto llega en trozos y desordenado.** ML Kit devuelve bloques por
/// region de la imagen, no en orden de lectura, de modo que un billete de
/// cinco mil se recibe tal cual asi:
///
/// ```
/// "PESOS / MIL / 5 / BC45063983 / CINCOo / BANCO DE LA REPUBLICA"
/// ```
///
/// La informacion esta completa, pero las piezas no estan juntas: "CINCO" y
/// "MIL" aparecen separadas por un numero de serie. Por eso el analisis no
/// exige que las palabras esten pegadas -- lo hacia antes, y por eso callaba
/// ante billetes perfectamente legibles. Ahora reune indicios sueltos y
/// decide por peso.
class BanknoteTextParser {
  const BanknoteTextParser._();

  /// Familia actual del peso colombiano. Cualquier cifra fuera de este
  /// conjunto se descarta: en un billete aparecen tambien anos, numeros de
  /// serie y codigos que no son denominaciones.
  static const Set<int> denominaciones = {
    2000,
    5000,
    10000,
    20000,
    50000,
    100000,
  };

  static const Map<String, int> _palabras = {
    'DOS': 2,
    'CINCO': 5,
    'DIEZ': 10,
    'VEINTE': 20,
    'CINCUENTA': 50,
    'CIEN': 100,
  };

  /// Cifras con separador de miles: 2.000, 20.000, 100.000
  static final RegExp _agrupada = RegExp(r'\b(\d{1,3}(?:[.,  ]\d{3})+)\b');

  /// Cifra seguida, sin separador. El punto de los miles es diminuto y el OCR
  /// lo pierde con frecuencia.
  static final RegExp _seguida =
      RegExp(r'\b(2000|5000|10000|20000|50000|100000)\b');

  /// Formato "20 MIL", con las dos piezas juntas.
  static final RegExp _numeroMil = RegExp(r'\b(\d{1,3})\s*MIL\b');

  /// Formato "VEINTE MIL", con las dos piezas juntas.
  static final RegExp _palabraMil =
      RegExp(r'\b(DOS|CINCO|DIEZ|VEINTE|CINCUENTA|CIEN)\s+MIL\b');

  /// La palabra MIL en cualquier parte del texto.
  static final RegExp _mil = RegExp(r'\bMIL\b');

  /// Un numero de la familia, suelto como bloque propio. Es como el OCR
  /// devuelve la cifra grande del billete cuando no alcanza a leer el punto
  /// de los miles: "5", "20", "100".
  static final RegExp _numeroSuelto = RegExp(r'\b(2|5|10|20|50|100)\b');

  /// Nivel de cada indicio. Un nivel superior gana siempre al inferior, por
  /// mucho que el inferior se repita: que el billete diga "VEINTE" pesa mas
  /// que cualquier cantidad de cifras sueltas encontradas por ahi.
  static const int _nivelJunto = 3; // "VEINTE MIL", "20.000", "20000"
  static const int _nivelPalabra = 2; // "VEINTE" en cualquier parte
  static const int _nivelNumero = 1; // "20" suelto en cualquier parte

  /// Devuelve la denominacion leida, o null si no hay ninguna clara.
  ///
  /// Decide por NIVEL de evidencia y, a igualdad de nivel, por cantidad. Ante
  /// un empate real devuelve null: es preferible callar a arriesgar un valor
  /// equivocado en una aplicacion con la que alguien va a pagar.
  static int? parse(String raw) {
    if (raw.trim().isEmpty) return null;
    final t = _repararDigitos(_normalizar(raw));

    final nivel = <int, int>{};
    final cuenta = <int, int>{};
    void anotar(int valor, int suNivel) {
      if (!denominaciones.contains(valor)) return;
      final actual = nivel[valor] ?? 0;
      if (suNivel > actual) nivel[valor] = suNivel;
      cuenta[valor] = (cuenta[valor] ?? 0) + 1;
    }

    // ---- Nivel 3: las piezas vienen juntas ----
    for (final m in _palabraMil.allMatches(t)) {
      final n = _palabras[m.group(1)];
      if (n != null) anotar(n * 1000, _nivelJunto);
    }
    for (final m in _numeroMil.allMatches(t)) {
      final n = int.tryParse(m.group(1)!);
      if (n != null) anotar(n * 1000, _nivelJunto);
    }
    for (final m in _agrupada.allMatches(t)) {
      final digitos = m.group(1)!.replaceAll(RegExp(r'[.,\u00A0 ]'), '');
      final n = int.tryParse(digitos);
      if (n != null) anotar(n, _nivelJunto);
    }
    for (final m in _seguida.allMatches(t)) {
      final n = int.tryParse(m.group(1)!);
      if (n != null) anotar(n, _nivelJunto);
    }

    // ---- Niveles 2 y 1: piezas sueltas, solo si MIL aparece en alguna parte ----
    //
    // Esa condicion mantiene honesto el metodo: un "5" suelto no significa
    // nada, pero un "5" en un papel que ademas dice "MIL" y "CINCO" solo puede
    // ser un billete de cinco mil.
    if (_mil.hasMatch(t)) {
      for (final entrada in _palabras.entries) {
        // Sin \b final: el OCR agrega basura al final de la palabra y devuelve
        // "CINCOo" en lugar de "CINCO". CINCO no se confunde con CINCUENTA
        // porque difieren en la quinta letra.
        if (RegExp('\\b${entrada.key}').hasMatch(t)) {
          anotar(entrada.value * 1000, _nivelPalabra);
        }
      }
      for (final n in _numerosSueltos(t)) {
        anotar(n * 1000, _nivelNumero);
      }
    }

    if (nivel.isEmpty) return null;

    final orden = nivel.keys.toList()
      ..sort((a, b) {
        final porNivel = nivel[b]!.compareTo(nivel[a]!);
        if (porNivel != 0) return porNivel;
        return cuenta[b]!.compareTo(cuenta[a]!);
      });
    if (orden.length == 1) return orden.first;

    final primero = orden[0];
    final segundo = orden[1];
    final empatados = nivel[primero] == nivel[segundo] &&
        cuenta[primero] == cuenta[segundo];
    return empatados ? null : primero;
  }

  /// Numeros sueltos del texto, descartando los que son un TROZO de otro mas
  /// largo que tambien aparece.
  ///
  /// El OCR parte la cifra grande del billete en varios bloques, de modo que un
  /// billete de veinte mil devuelve "20" y ademas un "2" suelto. Sin esta
  /// limpieza, ese "2" votaba por el billete de dos mil y empataba con el
  /// verdadero, con lo que el lector callaba. La regla tambien evita que un
  /// billete de cincuenta mil se lea como de cinco mil, o uno de cien mil como
  /// de diez mil.
  static Set<int> _numerosSueltos(String t) {
    final textos = <String>{};
    for (final m in _numeroSuelto.allMatches(t)) {
      textos.add(m.group(1)!);
    }
    textos.removeWhere(
      (corto) => textos.any((otro) => otro != corto && otro.startsWith(corto)),
    );
    return textos.map(int.parse).toSet();
  }

  // ====================================================================
  // Monedas
  // ====================================================================

  /// Familia actual de monedas colombianas.
  static const Set<int> denominacionesMoneda = {50, 100, 200, 500, 1000};

  /// La cifra grande acunada en la cara de la moneda.
  ///
  /// Los limites de palabra bastan para que "100" no se encuentre dentro de
  /// "1000", ni "50" dentro de "500": despues del grupo viene otro digito, que
  /// no es frontera.
  static final RegExp _numeroMoneda = RegExp(r'\b(50|100|200|500|1000)\b');

  static const Map<String, int> _palabrasMoneda = {
    'CINCUENTA': 50,
    'DOSCIENTOS': 200,
    'QUINIENTOS': 500,
    'CIEN': 100,
    'MIL': 1000,
  };

  /// Extrae la denominacion de una MONEDA a partir del texto del OCR.
  ///
  /// Se usa solo cuando el detector ya decidio que lo que hay delante es una
  /// moneda, y por eso puede ser mas directo que [parse]: no necesita exigir
  /// la palabra "MIL" para dar por buena una cifra suelta, porque en una
  /// moneda el unico numero grande acunado es su valor.
  ///
  /// Hace falta porque las monedas de 50, 100 y 200 se distinguen sobre todo
  /// por el diametro, y el modelo no puede usarlo: ve un recorte, sin saber a
  /// que distancia esta. La cifra acunada, en cambio, es inequivoca.
  ///
  /// Devuelve null ante una lectura parcial ("00") o ambigua: es preferible
  /// callar a anunciar un valor equivocado.
  static int? parseCoin(String raw) {
    if (raw.trim().isEmpty) return null;
    final t = _repararDigitos(_normalizar(raw));

    // Primero, la cifra acunada, que es la evidencia mas directa.
    final cifras = <String>{};
    for (final m in _numeroMoneda.allMatches(t)) {
      cifras.add(m.group(1)!);
    }
    cifras.removeWhere(
      (corto) => cifras.any((otro) => otro != corto && otro.startsWith(corto)),
    );
    if (cifras.length == 1) return int.parse(cifras.first);
    if (cifras.length > 1) return null; // dos cifras distintas: callar

    // Si no hay cifra legible, el valor escrito en palabras.
    final encontradas = <int>{};
    for (final e in _palabrasMoneda.entries) {
      if (RegExp('\\b${e.key}').hasMatch(t)) encontradas.add(e.value);
    }
    if (encontradas.length == 1) return encontradas.first;
    return null;
  }

  /// Mayusculas, sin tildes y con los espacios compactados, que es como se
  /// comparan las expresiones de arriba.
  static String _normalizar(String raw) {
    var t = raw.toUpperCase();
    const acentos = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'Ñ': 'N',
    };
    acentos.forEach((k, v) => t = t.replaceAll(k, v));
    return t.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Corrige las confusiones tipicas del OCR DENTRO de una cifra: la O o la Q
  /// por el cero, la I o la L por el uno.
  ///
  /// Se aplica solo a los grupos que ya contienen algun digito, de modo que
  /// ninguna palabra normal se ve afectada: en "BANCO" o en "COLOMBIA" no hay
  /// ningun numero y esas letras se quedan como estan; en "1O.OOO" si lo hay,
  /// y se convierte en "10.000".
  static final RegExp _grupoCifra = RegExp(r'[0-9OQIL.,$]+');
  static final RegExp _algunDigito = RegExp(r'\d');

  static String _repararDigitos(String t) {
    return t.replaceAllMapped(_grupoCifra, (m) {
      final grupo = m.group(0)!;
      if (!_algunDigito.hasMatch(grupo)) return grupo;
      return grupo
          .replaceAll(RegExp(r'[OQ]'), '0')
          .replaceAll(RegExp(r'[IL]'), '1');
    });
  }
}
