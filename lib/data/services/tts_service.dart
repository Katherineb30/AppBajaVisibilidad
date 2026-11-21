// ==========================================================================
// Motor de voz
// Capa MVVM: Datos
//
// Sintesis de voz sobre el motor del sistema, con cola propia para que un
// resultado nunca se corte y sin pisarse con TalkBack.
//
// Requisitos de la ERS que atiende:
//   - RF05 salida por voz
//   - RNF-U1 compatibilidad con lector de pantalla
// ==========================================================================

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/utils/speech_text_formatter.dart';

/// Prioridad de cada enunciado.
///
/// [result] es el contenido que el usuario pidio (texto leido o denominacion
/// del billete): NUNCA se interrumpe ni se descarta.
/// [status] son avisos de apoyo ("Buscando texto", "Acerque el objeto"): se
/// descartan si hay un resultado en curso, porque pisarlos es precisamente lo
/// que hace que la voz suene entrecortada.
enum SpeechPriority { status, result }

/// Un enunciado ya preparado y en espera dentro de la cola.
///
/// Guarda los fragmentos YA troceados en limites de frase, su prioridad y una
/// etiqueta que permite reconocer si se esta pidiendo repetir lo mismo.
class _Utterance {
  _Utterance(this.chunks, this.priority, this.tag);

  final List<String> chunks;
  final SpeechPriority priority;
  final String tag;
}

/// Motor de sintesis de voz propio de la aplicacion (TextToSpeech de Android).
///
/// Reglas de diseno:
///
/// 1. **No pelea con TalkBack.** No usa `SemanticsService.announce`, no lee las
///    etiquetas de los controles (de eso ya se encarga el lector de pantalla) y
///    respeta el motor y la voz que el usuario configuro en el sistema: se
///    limita a leer el CONTENIDO reconocido, que TalkBack no puede conocer.
///    Cuando detecta que hay un lector de pantalla activo silencia los avisos
///    de estado y espera un margen tras cada cambio de pantalla para no
///    solaparse con el anuncio de TalkBack.
///
/// 2. **Nunca se corta a si mismo.** Un unico enunciado en vuelo, cola FIFO y
///    `awaitSpeakCompletion(true)`. Los textos largos se parten SOLO en limites
///    de frase y se encadenan sin silencio perceptible entre fragmentos.
///
/// 3. **No tartamudea.** El texto pasa por [SpeechTextFormatter] (cifras a
///    palabras, simbolos fuera, saltos de linea reconstruidos) y las peticiones
///    repetidas del mismo resultado se ignoran.
class TtsService {
  TtsService({FlutterTts? engine}) : _tts = engine ?? FlutterTts();

  final FlutterTts _tts;
  final Queue<_Utterance> _queue = Queue<_Utterance>();

  final ValueNotifier<bool> isSpeaking = ValueNotifier<bool>(false);

  bool _initialized = false;
  bool _draining = false;
  bool _screenReaderActive = false;
  bool _disposed = false;

  Completer<void>? _current;
  String? _lastResultTag;

  /// Margen que se deja tras un cambio de pantalla para que TalkBack termine
  /// de anunciar el titulo antes de que hablemos nosotros.
  static const Duration screenReaderGrace = Duration(milliseconds: 450);

  /// Silencio entre fragmentos de un mismo texto. Muy corto: solo evita que
  /// algunas voces recorten la primera silaba del fragmento siguiente.
  static const Duration _interChunkGap = Duration(milliseconds: 90);

  bool get screenReaderActive => _screenReaderActive;

  /// Informar si TalkBack (o cualquier lector de pantalla) esta activo.
  /// Se alimenta desde la vista con `MediaQuery.accessibleNavigationOf(context)`.
  void setScreenReaderActive(bool value) => _screenReaderActive = value;

  // ---------------------------------------------------------------------
  // Inicializacion
  // ---------------------------------------------------------------------

  Future<void> init() async {
    if (_initialized) return;

    // Con esto `speak()` devuelve un Future que se completa cuando la voz
    // TERMINA de hablar. Es la pieza clave para encadenar sin cortes.
    await _tts.awaitSpeakCompletion(true);

    // QUEUE_FLUSH: como nunca hablamos en paralelo, el flush jamas trunca nada
    // y garantiza que un `stop()` explicito del usuario tenga efecto inmediato.
    await _tts.setQueueMode(0);

    await _applyLanguage();

    // No se cambia el motor: se usa el que el usuario tenga configurado en
    // Android, que es el mismo que emplea TalkBack. Asi la voz es la que el
    // usuario ya reconoce y no se descarga ni se fuerza ninguna otra.

    await _tts.setSpeechRate(0.52); // ~ritmo natural en Android
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    _tts.setCancelHandler(_finishCurrent);
    _tts.setCompletionHandler(_finishCurrent);
    _tts.setErrorHandler((dynamic _) => _finishCurrent());

    _initialized = true;
  }

  Future<void> _applyLanguage() async {
    const candidates = ['es-CO', 'es-MX', 'es-US', 'es-ES', 'es'];
    for (final code in candidates) {
      try {
        final available = await _tts.isLanguageAvailable(code);
        if (available == true) {
          await _tts.setLanguage(code);
          return;
        }
      } catch (_) {
        // isLanguageAvailable puede lanzar en algunos motores; se sigue probando.
      }
    }
    await _tts.setLanguage('es-ES');
  }

  // ---------------------------------------------------------------------
  // API publica
  // ---------------------------------------------------------------------

  /// Lee un resultado reconocido. Se pronuncia SIEMPRE completo.
  ///
  /// [tag] identifica el contenido; si coincide con el ultimo resultado leido
  /// la peticion se ignora, salvo que [force] sea true (boton REPETIR).
  Future<void> speakResult(String raw, {String? tag, bool force = false}) async {
    final spoken = SpeechTextFormatter.forSpeech(raw);
    if (spoken.isEmpty) return;

    final key = tag ?? spoken;
    if (!force && key == _lastResultTag && isSpeaking.value) return;
    _lastResultTag = key;

    // Un resultado nuevo deja sin efecto los avisos de estado en espera,
    // pero jamas corta a otro resultado que ya se este leyendo.
    _queue.removeWhere((u) => u.priority == SpeechPriority.status);

    _queue.add(_Utterance(SpeechTextFormatter.chunk(spoken), SpeechPriority.result, key));
    unawaited(_drain());
  }

  /// Aviso breve de estado. Se omite si TalkBack esta activo (lo anunciaria el
  /// propio lector) o si hay un resultado hablando.
  Future<void> speakStatus(String raw) async {
    if (_screenReaderActive) return;
    if (_hasPendingResult || _speakingResult) return;

    final spoken = SpeechTextFormatter.forSpeech(raw);
    if (spoken.isEmpty) return;

    // Solo un aviso de estado en cola a la vez.
    _queue.removeWhere((u) => u.priority == SpeechPriority.status);
    _queue.add(_Utterance([spoken], SpeechPriority.status, 'status'));
    unawaited(_drain());
  }

  /// Vuelve a leer el ultimo resultado (boton REPETIR).
  Future<void> repeat(String raw) async {
    await stop();
    await speakResult(raw, force: true);
  }

  /// Detiene la locucion. Solo debe llamarse por una accion explicita del
  /// usuario (salir de la pantalla, pulsar REPETIR) o al cerrar la app.
  Future<void> stop() async {
    _queue.clear();
    try {
      await _tts.stop();
    } catch (_) {
      // Ignorado: algunos motores lanzan si no habia nada hablando.
    }
    _finishCurrent();
    isSpeaking.value = false;
  }

  /// Espera a que la voz termine TODO lo que tiene en cola.
  ///
  /// La usa el modo automatico para no reanudar la deteccion mientras se esta
  /// leyendo un resultado: si se reanudara antes, la CPU volveria a llenarse
  /// de fotogramas y la locucion se entrecortaria.
  Future<void> waitUntilDone({
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final start = DateTime.now();
    // Margen inicial: la cola puede tardar unos milisegundos en arrancar.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    while ((isSpeaking.value || _queue.isNotEmpty) && !_disposed) {
      if (DateTime.now().difference(start) > timeout) break;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  /// Espera reglamentaria tras entrar a una pantalla, para no solaparse con el
  /// anuncio de TalkBack.
  Future<void> waitForScreenReader() async {
    if (_screenReaderActive) {
      await Future<void>.delayed(screenReaderGrace);
    }
  }

  void dispose() {
    _disposed = true;
    _queue.clear();
    isSpeaking.dispose();
    _tts.stop();
  }

  // ---------------------------------------------------------------------
  // Motor de la cola
  // ---------------------------------------------------------------------

  bool get _hasPendingResult =>
      _queue.any((u) => u.priority == SpeechPriority.result);

  bool _speakingResult = false;

  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;

    try {
      await init();
      while (_queue.isNotEmpty && !_disposed) {
        final utterance = _queue.removeFirst();
        _speakingResult = utterance.priority == SpeechPriority.result;
        isSpeaking.value = true;

        for (var i = 0; i < utterance.chunks.length; i++) {
          if (_disposed) break;
          await _speakChunk(utterance.chunks[i]);
          final isLast = i == utterance.chunks.length - 1;
          if (!isLast) {
            await Future<void>.delayed(_interChunkGap);
          }
        }
        _speakingResult = false;
      }
    } catch (e) {
      debugPrint('TtsService: error al hablar -> $e');
    } finally {
      _draining = false;
      isSpeaking.value = false;
    }
  }

  Future<void> _speakChunk(String chunk) async {
    _current = Completer<void>();
    try {
      await _tts.speak(chunk);
    } catch (e) {
      debugPrint('TtsService: speak fallo -> $e');
    }
    // Con awaitSpeakCompletion(true) el await anterior ya bloquea hasta el
    // final. El completer es la red de seguridad para los motores que no
    // respetan ese contrato: se libera con el handler o por tiempo maximo.
    final completer = _current;
    if (completer != null && !completer.isCompleted) {
      await completer.future.timeout(
        _estimateDuration(chunk),
        onTimeout: () {},
      );
    }
    _current = null;
  }

  void _finishCurrent() {
    final completer = _current;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Cota superior generosa: ~11 caracteres por segundo mas 1,5 s de margen.
  Duration _estimateDuration(String chunk) =>
      Duration(milliseconds: (chunk.length * 90) + 1500);
}
