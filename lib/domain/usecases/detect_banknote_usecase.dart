// ==========================================================================
// Caso de uso CU03
// Capa MVVM: Dominio
//
// Reconocer billete. Combina el juicio del modelo con la cifra impresa leida
// por el OCR y aplica el umbral de confianza.
//
// Requisitos de la ERS que atiende:
//   - RF03 billetes
//   - CU03
//   - RNF-F1 exactitud
//   - RNF-F4 confianza minima
// ==========================================================================

import 'package:camera/camera.dart';

import '../../data/models/banknote_detection.dart';
import '../repositories/i_banknote_repository.dart';

/// Caso de uso CU03 - Reconocer billetes.
///
/// Aplica dos filtros exigidos por los requisitos no funcionales:
/// * **RNF-F4**: no se anuncia ningun resultado con confianza inferior al 85 %.
/// * **Estabilidad**: la misma denominacion debe aparecer en varios fotogramas
///   consecutivos antes de anunciarse, para que la voz no cambie de cifra a
///   mitad de la frase.
class DetectBanknoteUseCase {
  DetectBanknoteUseCase(
    this._repository, {
    this.announceThreshold = 0.85,
    this.framesToConfirm = 3,
    this.framesToConfirmWithText = 2,
  });

  final IBanknoteRepository _repository;

  /// Confianza minima para anunciar por voz (RNF-F4).
  final double announceThreshold;

  final int framesToConfirm;

  /// Con la cifra impresa leida hace falta menos insistencia: el texto no es
  /// una probabilidad, y esperar de mas solo hace la aplicacion mas lenta.
  final int framesToConfirmWithText;

  int _candidate = -1;
  int _hits = 0;

  /// Cuantos fotogramas sigue valiendo una lectura buena de la cifra impresa.
  ///
  /// El OCR no acierta en todos los fotogramas: basta un reflejo, un leve
  /// movimiento o un angulo malo para perder uno. Antes, ese unico fallo
  /// reiniciaba la cuenta de confirmaciones y la verificacion por texto no
  /// llegaba a completarse jamas, de modo que acababa mandando el modelo --
  /// precisamente el que se equivoca entre 5, 10 y 20 mil bajo luz calida.
  /// Con esta memoria corta, una lectura clara sigue contando mientras el
  /// billete siga a la vista.
  static const int textMemoryFrames = 5;

  int? _lastText;
  int _textAge = 0;

  /// Fotogramas necesarios para anunciar una moneda cuya cifra ya se leyo.
  static const int coinFramesToConfirmWithText = 1;

  bool get isModelReady => _repository.isModelReady;
  String? get modelError => _repository.modelError;

  Future<void> prepare() => _repository.prepare();

  Future<void> release() => _repository.release();

  Future<List<BanknoteDetection>> call(
    CameraImage image,
    int rotationDegrees,
  ) {
    return _repository.detectFrame(image, rotationDegrees);
  }

  /// Devuelve la deteccion confirmada, o null si aun no es fiable.
  ///
  /// [textValue] es la denominacion que el OCR leyo impresa en el billete, si
  /// pudo leerla. **Cuando existe, manda sobre el modelo**: el reconocimiento
  /// de texto no depende del color y por tanto no lo enganan las dominantes de
  /// iluminacion que confunden entre denominaciones de tono parecido. El
  /// modelo sigue aportando la caja y la rapidez; el texto aporta la certeza.
  BanknoteDetection? confirm(
    List<BanknoteDetection> detections, {
    int? textValue,
    int? coinTextValue,
  }) {
    if (detections.isEmpty) {
      _candidate = -1;
      _hits = 0;
      return null;
    }

    // Gana la deteccion de MAYOR CONFIANZA. El area solo desempata.
    //
    // Antes se ponderaba confianza * area para quedarse con el billete que el
    // usuario enfoca y no con uno del fondo. Era mala idea: una caja grande y
    // equivocada le ganaba a una pequena y correcta aunque tuviera mucha menos
    // confianza, y con varias cajas por fotograma eso hace anunciar
    // denominaciones erroneas. Para descartar objetos lejanos ya esta el aviso
    // de "Acerque el objeto", que no falsea la clasificacion.
    final best = detections.reduce((a, b) {
      if ((a.confidence - b.confidence).abs() > 0.05) {
        return a.confidence > b.confidence ? a : b;
      }
      final areaA = a.rect.width * a.rect.height;
      final areaB = b.rect.width * b.rect.height;
      return areaA >= areaB ? a : b;
    });

    // Cada tipo de dinero se contrasta con su propio analizador de texto.
    //
    // Las reglas no son las mismas: en un billete la cifra va acompanada de
    // "MIL", y en una moneda el numero acunado aparece solo. Usar el analizador
    // de billetes sobre una moneda leeria cifras que no le corresponden.
    final int? cifra = _recordarCifra(best.isCoin ? coinTextValue : textValue);

    // Si el OCR leyo la cifra, manda ella. Si no, decide el modelo.
    //
    // Las monedas de 50, 100 y 200 se distinguen sobre todo por el diametro, y
    // el modelo no puede usarlo: ve un recorte, sin saber a que distancia
    // esta, de modo que entre esas tres se equivoca con frecuencia. Por eso la
    // cifra acunada tiene prioridad siempre que se consiga leer.
    //
    // Cuando no se lee -- la cara que se muestra no lleva numero, o esta
    // demasiado lejos -- se responde igualmente con el modelo, pero por el
    // camino exigente: umbral del 85 % y varios fotogramas seguidos. Es la
    // misma vara que se le aplica a un billete sin verificar.

    if (best.denomination <= 0 && cifra == null) return null;

    final porTexto = cifra != null;
    final valor = cifra ?? best.denomination;

    if (valor == _candidate) {
      _hits++;
    } else {
      _candidate = valor;
      _hits = 1;
    }

    // Una moneda con su cifra leida se anuncia en cuanto se lee.
    //
    // El numero acunado no es una probabilidad, y el analizador ya rechaza las
    // lecturas parciales o ambiguas: si dijo 100, es 100. Esperar un segundo
    // fotograma solo anadiria demora a algo que ya es seguro, y en monedas esa
    // demora se nota porque hay que sostenerlas quietas y cerca.
    //
    // En billetes no cambia nada: siguen pidiendo los mismos fotogramas.
    final necesarios = porTexto
        ? (best.isCoin ? coinFramesToConfirmWithText : framesToConfirmWithText)
        : framesToConfirm;
    if (_hits < necesarios) return null;

    // El umbral de confianza del RNF-F4 se aplica al juicio del MODELO. Si la
    // cifra viene leida del propio billete, ese umbral no tiene sentido: no
    // hay incertidumbre que medir.
    if (!porTexto && best.confidence < announceThreshold) return null;

    if (!porTexto) return best;

    // El texto manda. Si alguna caja ya coincidia con esa denominacion se usa
    // esa; si no, se conserva la caja del modelo y se corrige la etiqueta.
    final coincide = detections.where((d) => d.denomination == valor);
    final elegida = coincide.isNotEmpty ? coincide.first : best;
    return elegida.copyWith(
      denomination: valor,
      label: elegida.isCoin ? 'moneda_$valor' : 'billete_$valor',
      verifiedByText: true,
    );
  }

  /// Devuelve la cifra impresa vigente: la de este fotograma si el OCR la
  /// leyo, o la ultima buena mientras no se agote [textMemoryFrames].
  int? _recordarCifra(int? leidaAhora) {
    if (leidaAhora != null) {
      _lastText = leidaAhora;
      _textAge = 0;
      return leidaAhora;
    }
    if (_lastText != null && _textAge < textMemoryFrames) {
      _textAge++;
      return _lastText;
    }
    _lastText = null;
    return null;
  }

  void reset() {
    _candidate = -1;
    _hits = 0;
    _lastText = null;
    _textAge = 0;
  }
}
