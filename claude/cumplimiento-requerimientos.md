# Cumplimiento de la ERS (IEEE 830) en el código y en la funcionalidad

**Proyecto:** Aplicación Android de asistencia para personas con baja visión
**Arquitectura:** Flutter · MVVM (`presentation` → `domain` → `data` + `core`)
**Raíz del proyecto:** `C:\App_baja_vison\baja_vision_app`

Este documento responde a dos preguntas por cada requisito: **dónde vive en el
código** (archivo, clase y método) y **cómo se comporta la aplicación** cuando
el requisito se cumple. Al final se indica cómo verificar cada uno.

---

## 0. Cómo leer el código

Cada archivo de `lib/` empieza ahora con un encabezado de este tipo:

```dart
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
```

Es decir: **qué es el archivo, en qué capa de MVVM está y qué requisitos
justifica su existencia**. Con eso, ir de la ERS al código es directo — se busca
el identificador (`RF03`, por ejemplo) dentro de `lib/` y aparecen todos los
archivos implicados.

La regla de dependencia de MVVM se respeta en un solo sentido:

```
presentation/  (Views y ViewModels)   ← lo que el usuario ve y toca
      ↓ depende de
domain/        (casos de uso y contratos)  ← las reglas del negocio
      ↑ implementado por
data/          (servicios y repositorios)  ← cámara, OCR, TFLite, voz
core/          (tema, constantes, utilidades)  ← transversal
```

Ninguna View conoce ML Kit ni TensorFlow Lite; ningún servicio conoce un widget.

---

## 1. Requisitos funcionales

### RF01 — Reconocimiento de texto impreso (OCR offline) · CU01

| | |
|---|---|
| **Servicio** | `data/services/ocr_service.dart` → `OcrService.recognize()` |
| **Contrato** | `domain/repositories/i_text_recognition_repository.dart` |
| **Implementación** | `data/repositories/text_recognition_repository.dart` |
| **Caso de uso** | `domain/usecases/recognize_text_usecase.dart` → `RecognizeTextUseCase` |
| **Orquestación** | `presentation/viewmodels/text_view_model.dart` |
| **Preprocesado** | `core/utils/image_converter.dart` |

**En funcionalidad.** El módulo TEXTO abre la cámara, analiza fotogramas de forma
continua y, cuando el texto se repite entre capturas, lo da por bueno y lo lee en
voz alta. El motor es **ML Kit Text Recognition v2 con el modelo empaquetado
dentro del APK**: no descarga nada la primera vez ni consulta ningún servidor.

**El detalle que importa.** El OCR de un fotograma suelto es inestable: una
sombra o un temblor cambian dos letras. Por eso `RecognizeTextUseCase` no
devuelve lo primero que lee, sino que compara lecturas consecutivas con una
**similitud de Jaccard sobre conjuntos de palabras** (`similarityThreshold =
0.65`) y sólo confirma cuando dos lecturas coinciden. Si tras `maxAttempts = 6`
intentos no hay coincidencia, confirma la mejor lectura disponible para no dejar
al usuario esperando en silencio.

---

### RF02 — Visualización de la detección en realidad aumentada · CU02

| | |
|---|---|
| **Capa gráfica** | `presentation/widgets/overlay_painters.dart` → `TextHighlightPainter`, `BanknoteBoxPainter`, `CornerFramePainter`, `ScanLine` |
| **Composición** | `presentation/widgets/camera_viewport.dart` |
| **Interruptor** | `presentation/viewmodels/recognition_view_model.dart` → `toggleOverlay()`; control en `presentation/widgets/scan_top_bar.dart` |

**En funcionalidad.** Sobre la vista de cámara se dibujan, en el color de alto
contraste del módulo, el resaltado de cada línea de texto detectada, la caja del
billete con su denominación, las esquinas de encuadre y una línea de barrido
mientras se analiza. La ERS lo define como comportamiento **opcional**: el
conmutador de la barra superior lo apaga y lo enciende, y la aplicación sigue
funcionando entera sin él (que es justo lo que necesita quien no ve nada).

**El detalle que importa.** Las coordenadas que entregan el OCR y el detector
están **normalizadas 0..1** respecto de la imagen analizada, no de la pantalla.
`CameraViewport` sitúa la vista previa y las capas en el mismo sistema de
coordenadas, de modo que el recuadro queda encima del objeto real y no desplazado.

---

### RF03 — Reconocimiento de billetes colombianos · CU03

| | |
|---|---|
| **Inferencia** | `data/services/banknote_detector_service.dart` → `BanknoteDetectorService.detect()` |
| **Contrato** | `domain/repositories/i_banknote_repository.dart` |
| **Caso de uso** | `domain/usecases/detect_banknote_usecase.dart` → `DetectBanknoteUseCase.confirm()` |
| **Contraste por OCR** | `core/utils/banknote_text_parser.dart` → `BanknoteTextParser.parse()` |
| **Orquestación** | `presentation/viewmodels/money_view_model.dart` → `analyze()` |
| **Modelo y clases** | `assets/models/billetes_yolov8.tflite`, `assets/labels/billetes.txt` |

**En funcionalidad.** El módulo DINERO ejecuta el modelo YOLO entrenado sobre
cada fotograma, agrupa las cajas duplicadas, exige que la misma denominación
aparezca en varios fotogramas seguidos y entonces la anuncia.

**El detalle que importa: dos fuentes de verdad, no una.** El modelo decide por
la apariencia, y la apariencia depende de la luz — bajo un bombillo incandescente
los billetes de 5, 10 y 20 mil se vuelven del mismo tono ámbar. Por eso el
módulo de dinero **también pasa el OCR sobre el mismo fotograma** y extrae la
cifra impresa en el billete:

```dart
// money_view_model.dart
int? valorLeido;
if (detections.isNotEmpty) {
  final texto = await _recognizeText(image, rotation);
  valorLeido = BanknoteTextParser.parse(texto.fullText);
}
final best = _detectBanknote.confirm(detections, textValue: valorLeido);
```

`BanknoteTextParser` reconoce tres formas de escribir la cifra (`50.000`,
`50 MIL`, `CINCUENTA MIL`), sólo admite denominaciones reales y **devuelve
`null` si encuentra dos distintas** — ante la duda prefiere no opinar antes que
opinar mal. Cuando sí hay lectura, **la cifra impresa manda sobre el modelo**:
el color puede engañar, el número impreso no. Además, una detección verificada
por texto confirma en 2 fotogramas en lugar de 3, y queda marcada con
`verifiedByText: true`.

Contra el color se añaden dos mitigaciones más: **balance de blancos** por el
método del punto blanco en `ImageConverter._applyWhiteBalance()` (neutraliza la
dominante ámbar antes de que el modelo vea la imagen) y **encendido anticipado
de la linterna** en el módulo de dinero (`torchOnBelow => 125`, frente a un
umbral mucho más bajo en el módulo de texto).


---

### RF04 — Procesamiento local sin conexión · CU04

| | |
|---|---|
| **Garantía estructural** | `android/app/src/main/AndroidManifest.xml` — **sin el permiso `INTERNET`** |
| **Modelos embebidos** | `assets/models/`, ML Kit en versión *bundled* |
| **Aviso al usuario** | `presentation/views/home_view.dart` → `_Header` |

**En funcionalidad.** Todo el reconocimiento ocurre en el teléfono. La pantalla
de inicio lo dice explícitamente ("funciona sin conexión"), y funciona igual en
modo avión.

**El detalle que importa.** Esto no se cumple "porque el código no llama a la
red", sino **porque Android no se lo permitiría aunque quisiera**: la aplicación
no declara el permiso `INTERNET`. Es la forma más fuerte de demostrar RF04 y
RNF-S1 en la sustentación: no hay que auditar el código, basta abrir el
manifiesto. Por esa misma razón, `ModelStorageService` implementa la instalación
y verificación de modelos nuevos **pero no la descarga** (ver RF07).

---

### RF05 — Salida por voz del resultado · CU05

| | |
|---|---|
| **Motor** | `data/services/tts_service.dart` → `TtsService.speak()`, `repeat()`, `waitUntilDone()` |
| **Normalización** | `core/utils/speech_text_formatter.dart` → `forSpeech()`, `chunk()` |
| **Cifras a palabras** | `core/utils/spanish_number_speller.dart` |
| **Manifiesto** | bloque `<queries>` con `android.intent.action.TTS_SERVICE` |

**En funcionalidad.** La aplicación lee en voz alta el texto reconocido o la
denominación del billete, usando el motor y la voz que el usuario ya tiene
configurados en Android, en español (se prueban `es-CO`, `es-MX`, `es-US`,
`es-ES`, `es` en ese orden). Los botones de volumen del teléfono controlan
directamente su volumen.

**El detalle que importa: por qué no se oye entrecortada.** Tres decisiones:

1. **Cola FIFO con un solo enunciado en vuelo** y `awaitSpeakCompletion(true)`.
   Un resultado (`SpeechPriority.result`) **nunca se interrumpe**; los avisos de
   estado (`SpeechPriority.status`) se descartan si hay un resultado hablando.
   Eso elimina la causa número uno del habla tartamuda: la app pisándose a sí
   misma.
2. **Troceado sólo en límites de frase** (`SpeechTextFormatter.chunk`, 380
   caracteres) con 90 ms entre fragmentos. Cortar por número de caracteres
   partiría palabras a la mitad.
3. **Normalización previa**: `$12.500` se convierte en "doce mil quinientos
   pesos" (leído tal cual, el sintetizador dice "doce punto quinientos"), las
   palabras partidas por guión al final de línea se vuelven a unir, los símbolos
   se retiran y el texto se cierra con punto para que la entonación termine.

**Convivencia con TalkBack.** `TtsService` **no** usa `SemanticsService.announce`
ni lee las etiquetas de los controles — de eso ya se encarga el lector de
pantalla. Sólo lee el *contenido reconocido*, que TalkBack no puede conocer.
Cuando detecta un lector activo (`setScreenReaderActive()`, alimentado desde las
vistas con `MediaQuery.accessibleNavigationOf(context)`), **silencia los avisos
de estado** y espera un margen de 450 ms tras cada cambio de pantalla para no
solaparse con el anuncio de TalkBack. Los estados siguen llegando al usuario,
pero por boca de TalkBack, a través de la región viva de la barra superior.

---

### RF06 — Captura de imagen con la cámara · CU06

| | |
|---|---|
| **Servicio** | `data/services/camera_service.dart` → `initialize()`, `startStream()`, `stopStream()`, `setTorch()` |
| **Ciclo de vida** | `presentation/viewmodels/recognition_view_model.dart`; `didChangeAppLifecycleState` en cada vista |
| **Permiso** | `data/services/permission_service.dart`, `presentation/widgets/permission_gate.dart` |

**En funcionalidad.** Cámara trasera a 720p, enfoque y exposición automáticos,
formato NV21 (el que ML Kit acepta sin conversión), flujo continuo de fotogramas
y linterna controlable. Al salir de la aplicación el flujo se detiene y la voz se
calla.

**El detalle que importa.** Analizar *todos* los fotogramas sería inútil y caro:
`RecognitionViewModel` impone un intervalo mínimo entre análisis (700 ms en
dinero, algo mayor en texto) y descarta fotogramas mientras hay uno en proceso.
La **linterna se enciende sola** cuando la luminancia media baja del umbral del
módulo y se apaga al recuperarse, con histéresis para que no parpadee — y con un
pestillo (`_torchManual`) para que, si el usuario la enciende a mano, la
automática no se la apague.

---

### RF07 — Actualización de los modelos · CU07

| | |
|---|---|
| **Servicio** | `data/services/model_storage_service.dart` → `resolve()`, `sha256Of()`, `install()`, `rollback()`, `restoreBundled()`, `describe()` |
| **Consumidor** | `data/services/banknote_detector_service.dart` (carga desde archivo o desde *assets*) |
| **Pantalla** | `presentation/views/diagnostics_view.dart` |

**En funcionalidad.** El modelo activo puede sustituirse por una versión nueva
sin reinstalar la aplicación. `install()` **verifica primero la huella SHA-256**
del archivo; si no coincide, no toca nada. Si coincide, escribe a un temporal,
renombra el modelo vigente como respaldo y hace el cambio con un renombrado
atómico. `rollback()` devuelve el respaldo y `restoreBundled()` vuelve al modelo
de fábrica. En cualquier fallo, el modelo anterior sigue activo — la aplicación
nunca queda sin detector.

**Cumplimiento parcial, declarado.** La ERS describe la descarga por HTTPS.
**Está deliberadamente no implementada**, porque añadir el permiso `INTERNET`
rompería RF04 y RNF-S1, que son *Must Have*. La instalación verificada,
la sustitución atómica y la reversión —que es donde está el riesgo real— sí
están. El archivo entra hoy por el gestor de archivos del sistema o por `adb
push`. Es una decisión de diseño defendible: se prioriza el requisito de mayor
prioridad cuando dos entran en conflicto.

---

### RF08 — Modo de diagnóstico y optimización · CU08

| | |
|---|---|
| **Servicio** | `data/services/diagnostics_service.dart` → `recordRecognition()`, `recordError()`, `_sampleMemory()`, `buildReport()`, `exportReport()` |
| **Instrumentación** | `presentation/viewmodels/recognition_view_model.dart` (cronómetro alrededor de cada análisis) |
| **Pantalla** | `presentation/views/diagnostics_view.dart` |

**En funcionalidad.** Cada reconocimiento se cronometra y se registra por módulo:
número de lecturas, tiempo medio, **percentil 90**, fallos y errores. La memoria
se muestrea con `ProcessInfo.currentRss`. La pantalla de diagnóstico muestra cada
métrica **junto al límite del requisito** (≤ 2 s para texto, ≤ 1,5 s para
billetes, ≤ 350 MB de memoria), así que la evidencia para la sustentación se lee
directamente del teléfono.

**El detalle que importa.** Se usa **p90 y no el promedio** porque la métrica de
verificación de la ERS está escrita en esos términos ("≤ 2 segundos en el 90 % de
las capturas"). Y el registro se guarda en el **área privada de la aplicación**,
sin imágenes ni texto reconocido: cumple HU06 *"diagnosticar fallos sin acceder a
imágenes ni datos personales del usuario"*.

---

### RF09 — Soporte para la verificación de accesibilidad · CU09

| | |
|---|---|
| **Etiquetado** | `Semantics` en todos los controles: `big_action_button.dart`, `bottom_action_bar.dart`, `scan_top_bar.dart`, `camera_viewport.dart`, `permission_gate.dart` |
| **Regiones vivas** | `scan_top_bar.dart` → `_Chip` (`liveRegion: true`) |
| **Exclusiones deliberadas** | `result_panel.dart`, `_NoteResult` en `money_view.dart` (`ExcludeSemantics`) |
| **Textos** | `core/constants/app_strings.dart` |

**En funcionalidad.** Toda la interfaz es recorrible con TalkBack: cada elemento
interactivo tiene etiqueta descriptiva, rol y estado (`button`, `toggled`,
`enabled`), y el orden de foco sigue la lectura natural de la pantalla.

**El detalle que importa: por qué hay `ExcludeSemantics`.** El panel de resultado
está **excluido a propósito** del árbol de accesibilidad. Si no lo estuviera,
TalkBack leería el texto reconocido *además* de la voz de la aplicación, y el
usuario oiría todo dos veces, solapado. La aplicación lee el contenido; TalkBack
lee la interfaz. La frontera es explícita y es lo que hace que ambos convivan.

---

### RF10 — Registro y exportación de hallazgos · CU10

| | |
|---|---|
| **Modelo** | `data/services/diagnostics_service.dart` → `Finding`, `FindingSeverity` |
| **Alta** | `presentation/views/diagnostics_view.dart` → `_FindingDialog`, `_addFinding()` |
| **Exportación** | `DiagnosticsService.exportReport()` |

**En funcionalidad.** Durante las pruebas, el tester registra cada hallazgo con
pantalla, severidad, requisito afectado y descripción, con marca de fecha y hora.
Todo se persiste en JSON y se exporta como un archivo único para el seguimiento
del equipo.

---

## 2. Requisitos no funcionales

### Rendimiento

| Req. | Dónde se atiende | Cómo |
|---|---|---|
| **RNF-R1** texto ≤ 2 s (p90) | `RecognizeTextUseCase`, `DiagnosticsService` | Análisis continuo con confirmación en 2 fotogramas; el p90 medido se ve en la pantalla de diagnóstico |
| **RNF-R2** billetes ≤ 1,5 s (p90) | `ImageConverter.preprocess()`, `BanknoteDetectorService` | Preprocesado en **una sola pasada** sobre un `Float32List` y escritura directa en la memoria del tensor |
| **RNF-R3** capa RA ≥ 20 fps | `overlay_painters.dart` | `shouldRepaint` estricto en cada *painter*; la línea de barrido **detiene su animación** cuando no se analiza |
| **RNF-R4** arranque ≤ 3 s | `main.dart` | `ServiceLocator.warmUp()` es **no bloqueante**: la primera pantalla se pinta mientras la voz y el registro se preparan de fondo |
| **RNF-R5** memoria ≤ 350 MB | `ImageConverter`, `DiagnosticsService` | Buffer del tensor **reutilizado** entre fotogramas (no se asigna uno nuevo cada vez); RSS muestreado y mostrado |

> **Sobre RNF-R2 — esto costó trabajo y conviene contarlo.** La primera versión
> construía listas anidadas de Dart para el tensor de entrada; la librería tenía
> que recorrer unos 4,9 millones de valores por fotograma y el teléfono saltaba
> más de 200 fotogramas seguidos. La versión actual muestrea **sólo los 640×640
> píxeles de salida**, aplica la rotación inversa en la misma pasada y escribe
> directamente sobre la memoria del tensor. La cámara volvió a ir fluida.

### Seguridad y privacidad

| Req. | Dónde | Cómo |
|---|---|---|
| **RNF-S1** nada sale del dispositivo | `AndroidManifest.xml` | **Sin permiso `INTERNET`.** Verificable por inspección del manifiesto y por captura de tráfico: 0 solicitudes |
| **RNF-S2** permisos mínimos | `permission_service.dart`, `permission_gate.dart` | Un único permiso: **cámara**. Se pide en tiempo de ejecución y la pantalla explica para qué, de forma accesible |
| **RNF-S3** integridad de actualizaciones | `model_storage_service.dart` → `sha256Of()` + `install()` | Verificación **SHA-256 antes** de aplicar, sustitución atómica, respaldo y reversión |

### Fiabilidad

| Req. | Dónde | Cómo |
|---|---|---|
| **RNF-F1** exactitud billetes ≥ 95 % | `BanknoteDetectorService` (`confidenceThreshold = 0.40`, `iouThreshold = 0.35`), `DetectBanknoteUseCase`, `BanknoteTextParser` | Supresión de duplicados, confirmación en varios fotogramas y **contraste con la cifra impresa** |
| **RNF-F2** exactitud OCR ≥ 90 % | `OcrService`, `RecognizeTextUseCase` | ML Kit v2 + estabilización temporal por similitud de Jaccard |
| **RNF-F3** manejo accesible de errores | `main.dart` (`runZonedGuarded`, `FlutterError.onError`, `platformDispatcher.onError`), `RecognitionViewModel.announceProblem()`, `BottomActionBar` | Ningún error cierra la app: se anuncia en voz y por escrito, y siempre quedan a mano INICIO y REPETIR |
| **RNF-F4** no anunciar por debajo del 85 % | `domain/usecases/detect_banknote_usecase.dart` → `announceThreshold = 0.85` | Por debajo del umbral **no se anuncia**: se sigue buscando y se pide reintentar. La única excepción es una detección confirmada por la cifra impresa, donde la certeza no viene del modelo |

### Disponibilidad

| Req. | Dónde | Cómo |
|---|---|---|
| **RNF-D1** offline permanente | Modelos embebidos + sin `INTERNET` | El 100 % de las funciones principales operan sin conectividad |
| **RNF-D2** ≤ 15 % de batería / 30 min | `RecognitionViewModel` (intervalo mínimo entre análisis), `didChangeAppLifecycleState` en las vistas, `ScanLine` | Se analiza a ritmo controlado, la cámara y la voz se sueltan al pasar a segundo plano y las animaciones se detienen cuando no hacen falta |

### Usabilidad y accesibilidad

| Req. | Dónde | Cómo |
|---|---|---|
| **RNF-U1** operable con TalkBack | `Semantics` en todos los controles; `TtsService.setScreenReaderActive()` | 100 % de los elementos interactivos etiquetados; la voz de la app y la de TalkBack no se solapan |
| **RNF-U2** alto contraste | `core/theme/app_colors.dart`, `app_theme.dart` | Todos los pares texto/fondo superan 7:1 (WCAG AAA). Tema oscuro **fijo**: no sigue al sistema, porque aquí el contraste no es una preferencia |
| **RNF-U3** área táctil amplia | `core/constants/app_dimens.dart`, `big_action_button.dart`, `bottom_action_bar.dart` | Los dos destinos de inicio ocupan **media pantalla cada uno**; la barra inferior, todo el ancho en dos mitades |
| **RNF-U4** tipografía escalable | `app.dart` (factor de escala mínimo garantizado), `result_panel.dart` | El texto reconocido se muestra en cuerpo grande y nunca baja del mínimo legible |

---

## 3. Historias de usuario

| HU | Qué pidió el usuario | Dónde se cumple | Estado |
|---|---|---|---|
| **HU01** | Apuntar y escuchar texto impreso | Módulo TEXTO completo (RF01, RF05, RF06) | ✅ |
| **HU02** | Saber la denominación del billete | Módulo DINERO completo (RF03, RF05, RF06) | ✅ funcional; exactitud limitada por el modelo bajo luz cálida (ver §4) |
| **HU03** | Usar la app sin conexión | Sin permiso `INTERNET`, modelos embebidos | ✅ |
| **HU04** | Ver la detección en realidad aumentada | `overlay_painters.dart`, desactivable | ✅ |
| **HU05** | Vibración y sonido de encuadre | — | **Fuera de alcance** (*Won't Have* en la tabla MoSCoW). Hay indicación audible de estado, no guía de encuadre |
| **HU06** | Registro local de errores y caídas | `DiagnosticsService` + captura global en `main.dart` | ✅ sin imágenes ni datos personales |
| **HU07** | Probar el reconocimiento en distintas condiciones | Pantalla de diagnóstico, métricas y hallazgos | ✅ implementado; **falta ejecutar la campaña de pruebas** |
| **HU08** | Actualizar modelos sin reinstalar | `ModelStorageService` | ✅ parcial: instalación verificada y reversible, sin descarga por HTTPS (ver RF07) |

---

## 4. Lo que todavía no está cerrado

Conviene llevar esto claro a la sustentación, porque un tribunal lo va a
preguntar:

1. **Exactitud bajo luz cálida.** El modelo confunde 5, 10 y 20 mil bajo bombillo
   incandescente, porque los tres se vuelven del mismo tono. Ya están en el
   código las tres mitigaciones (balance de blancos, linterna anticipada y
   contraste con la cifra impresa por OCR), pero **la solución de fondo es
   reentrenar** con aumento de color agresivo: `hsv_h=0.02, hsv_s=0.8, hsv_v=0.5`.
2. **Monedas.** Soportadas por el código, ausentes del modelo. Se resuelve
   añadiendo las clases al dataset.
3. **Métricas por medir.** RNF-R1, R2, R3, R4, R5, D2, F1 y F2 tienen
   instrumentación lista; faltan las corridas de prueba que llenen la tabla.
4. **Recorrido con TalkBack.** RF09 y HU07 están implementados; falta ejecutar y
   documentar el recorrido completo pantalla por pantalla.
5. **Descarga de modelos por HTTPS.** No implementada por decisión de diseño
   (conflicto con RF04/RNF-S1), explicada arriba.

---

## 5. Cómo verificar cada cosa

| Qué verificar | Cómo |
|---|---|
| RF04, RNF-S1 | Abrir `AndroidManifest.xml` y comprobar que no existe `INTERNET`; poner el teléfono en modo avión y usar la app |
| RF05, "no tartamudea" | Leer un párrafo largo: debe decirse entero, sin cortes ni repeticiones |
| RNF-U1, RF09 | Activar TalkBack y recorrer las tres pantallas con deslizamientos; nada debe quedar sin anunciar ni anunciarse dos veces |
| RNF-R1, R2, R5 | Pantalla de diagnóstico: p90 por módulo y memoria, contra los límites que ya muestra |
| RNF-F4 | Alejar el billete hasta bajar la confianza: no debe anunciarse nada |
| RF03 + OCR | Con el billete enfocado, el registro imprime `TEXTO del billete -> 50000` cuando la cifra impresa confirma la detección |
| RF07, RNF-S3 | Instalar un `.tflite` con SHA-256 incorrecto: debe rechazarse y seguir activo el anterior |
| Pruebas unitarias | `flutter test` — cubre cifras a palabras, normalización para voz, troceado por frases y el analizador de la cifra impresa |
