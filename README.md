# VisionApp — Asistente visual offline

Aplicación Android en **Flutter** para personas con baja visión o ceguera.
Reconoce **texto impreso** y **billetes colombianos** con visión por
computador que se ejecuta íntegramente en el dispositivo, y anuncia el
resultado por voz.

Proyecto de grado — Daniel Villalba · Katherine Bolívar.

---

## 1. Qué hace

| Módulo | Requisito | Tecnología | Conexión |
|---|---|---|---|
| **TEXTO** | RF01 · CU01 | ML Kit Text Recognition **v2** (modelo empaquetado) | ninguna |
| **DINERO** | RF03 · CU03 | YOLOv8 entrenado en Colab → TensorFlow Lite | ninguna |
| **VOZ** | RF05 · CU05 | Motor TextToSpeech de Android | ninguna |
| **CÁMARA** | RF06 · CU06 | `camera` + linterna automática | ninguna |

El `AndroidManifest.xml` **no declara el permiso INTERNET**: el requisito
"ningún dato sale del dispositivo" (RNF-S1) queda garantizado por el propio
sistema operativo, no solo por el código.

---

## 2. Arquitectura (MVVM)

```
lib/
├── main.dart                     arranque, orientación fija, precalentado del TTS
├── app.dart                      MaterialApp, tema, rutas, escala de fuente
│
├── core/                         transversal
│   ├── constants/                textos y medidas de accesibilidad
│   ├── theme/                    paleta de alto contraste y tema
│   ├── utils/                    normalizador de voz, números a palabras,
│   │                             conversión NV21→RGB y letterbox
│   └── di/service_locator.dart   inyección de dependencias
│
├── data/                         (Model) fuentes de datos
│   ├── models/                   DetectedTextBlock, BanknoteDetection, estados
│   ├── services/                 TtsService, CameraService, OcrService,
│   │                             BanknoteDetectorService, PermissionService
│   └── repositories/             implementaciones concretas
│
├── domain/                       reglas de negocio, sin Flutter
│   ├── repositories/             contratos (interfaces)
│   └── usecases/                 RecognizeTextUseCase, DetectBanknoteUseCase
│
└── presentation/                 (View + ViewModel)
    ├── viewmodels/               RecognitionViewModel (base), Text, Money, Home
    ├── views/                    HomeView, TextView, MoneyView
    └── widgets/                  componentes reutilizables
```

La **View** no conoce ML Kit ni TFLite; habla solo con su **ViewModel**, que a
su vez depende de interfaces del dominio. Cambiar el motor de OCR o el detector
no obliga a tocar una sola línea de interfaz.

---

## 3. Interfaz

Reproduce el prototipo de Figma del vídeo, con un cambio pedido expresamente:

- **Se eliminó el botón "← Volver" de la esquina superior izquierda.** La
  vuelta a la pantalla principal se hace con el botón **INICIO** de la barra
  inferior, que ocupa tres cuartos del ancho, está bajo el pulgar y se puede
  encontrar sin ver la pantalla. El gesto de retroceso de Android sigue
  funcionando.
- **Inicio**: dos botones gigantes, `TEXTO` (amarillo) y `DINERO` (verde), cada
  uno de media pantalla.
- **Pantallas de escaneo**: barra superior con estado y conmutador `AUTO`,
  vista de cámara con esquinas de encuadre y capa de realidad aumentada
  (recuadros sobre el texto o sobre el billete), panel de resultado y barra
  inferior `INICIO` / `REPETIR`.

Accesibilidad: contraste ≥ 7:1, área táctil mínima de 96 dp, tipografía de 24
a 46 pt, respeto de la escala de fuente del sistema (con mínimo garantizado),
retroalimentación háptica en cada detección.

---

## 4. Voz: cómo se evita el "tartamudeo" y el choque con TalkBack

`data/services/tts_service.dart` usa el motor TextToSpeech propio de Android.

**No interfiere con TalkBack**

1. No se usa `SemanticsService.announce` para los resultados: eso pasaría por
   TalkBack y sonaría dos veces.
2. Los paneles de resultado van dentro de `ExcludeSemantics`, así el lector de
   pantalla no relee lo que la app ya está diciendo.
3. Cuando hay lector de pantalla activo
   (`MediaQuery.accessibleNavigationOf`), la app **silencia sus avisos de
   estado** ("Buscando texto", "Acerque el objeto"): de eso ya se encarga
   TalkBack. Solo se locuta el **contenido reconocido**, que TalkBack no puede
   conocer.
4. Tras cada cambio de pantalla se esperan 450 ms para que TalkBack termine de
   anunciar el título antes de hablar.
5. No se cambia el motor ni la voz del sistema: se usa la que el usuario ya
   tiene configurada, la misma que emplea TalkBack.

**Nunca se corta ni se entrecorta**

1. `awaitSpeakCompletion(true)` + **cola FIFO propia**: solo hay un enunciado
   en vuelo; el siguiente empieza cuando el anterior ha terminado de verdad.
2. Los resultados tienen prioridad sobre los avisos y **jamás son
   interrumpidos**; un aviso de estado en cola se descarta si llega un
   resultado.
3. Los textos largos se parten **solo en límites de frase**, con 90 ms entre
   fragmentos: la lectura se percibe continua.
4. **Mientras la voz habla, no se analizan fotogramas.** La CPU queda libre
   para el sintetizador — ésta es la causa habitual del audio a trompicones.
5. El texto pasa por `SpeechTextFormatter`: `$12.500` → *"doce mil quinientos
   pesos"*, se reúnen palabras partidas por guion, se eliminan los símbolos que
   el sintetizador deletrearía y se cierra la frase con punto (algunas voces
   recortan la última sílaba si no hay puntuación final).
6. Estabilización: un texto debe repetirse en 2 fotogramas y un billete en 3
   antes de anunciarse, y no se repite un resultado idéntico. Sin esto la voz
   se reiniciaría en cada fotograma.
7. La denominación se pronuncia en palabras ("Billete de veinte mil pesos"),
   nunca como cifra.

---

## 5. Modelo de billetes

Coloque el modelo entrenado en:

```
assets/models/billetes_yolov8.tflite
```

Exportación desde Google Colab:

```python
from ultralytics import YOLO
model = YOLO("runs/detect/train/weights/best.pt")
model.export(format="tflite", imgsz=640, int8=False)
```

Renombre `best_float32.tflite` a `billetes_yolov8.tflite`.

El orden de las clases debe coincidir con `assets/labels/billetes.txt`
(el mismo orden que `names:` en su `data.yaml`).

Mientras el `.tflite` no exista la app arranca igual: el módulo DINERO avisa
que el modelo no está disponible y el módulo TEXTO funciona con normalidad.

Filtros aplicados: confianza mínima del modelo 0,55; **no se anuncia nada por
debajo del 85 %** (RNF-F4); supresión de no máximos con IoU 0,45.

---

## 6. Puesta en marcha en Visual Studio Code

1. Abrir la carpeta `App_baja_vison/baja_vision_app` en VS Code.
2. Extensiones **Flutter** y **Dart** instaladas (ya recomendadas en
   `.vscode/extensions.json`).
3. Terminal:

   ```bash
   flutter pub get
   flutter doctor        # todo en verde para Android
   ```

4. Conectar el teléfono Android por USB con **depuración USB** activada y
   comprobar que aparece:

   ```bash
   flutter devices
   ```

5. Ejecutar con `F5` o:

   ```bash
   flutter run
   ```

6. Para el APK instalable:

   ```bash
   flutter build apk --release
   ```

> Si Gradle se queja de `flutter.sdk`, cree `android/local.properties` con
> `flutter.sdk=C:\\src\\flutter` (VS Code lo genera solo al primer `flutter run`).

### Cámara y bocina

- El permiso de cámara se pide en tiempo de ejecución la primera vez; si se
  deniega, la pantalla ofrece un botón enorme para volver a concederlo o abrir
  los ajustes.
- La cámara trasera se abre a 720p con enfoque y exposición automáticos, en
  formato **NV21**, que es el que ML Kit acepta sin conversión.
- La **linterna se enciende sola** cuando la luminancia media del fotograma
  baja de 55 y se apaga al recuperarse (con histéresis para que no parpadee).
- La voz sale por el canal multimedia y los **botones físicos de volumen
  controlan directamente el volumen de la app** (`volumeControlStream` en
  `MainActivity.kt`), sin entrar en ningún menú.
- El bloque `<queries><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries>`
  del manifiesto es obligatorio desde Android 11: sin él la app no ve el motor
  de voz del sistema y no se oiría nada.

---

## 7. Pruebas

```bash
flutter test
```

Cubren la conversión de cifras a palabras, la normalización del texto para voz,
el troceado en límites de frase y el formato de la denominación.

---

## 8. Trazabilidad con la ERS (IEEE 830)

### Requisitos funcionales

| Req. | Nombre | Dónde se implementa |
|---|---|---|
| RF01 | OCR offline | `data/services/ocr_service.dart` · `domain/usecases/recognize_text_usecase.dart` |
| RF02 | Realidad aumentada **desactivable** | `widgets/overlay_painters.dart` · conmutador en `widgets/scan_top_bar.dart` (`overlayEnabled`) |
| RF03 | Billetes | `data/services/banknote_detector_service.dart` |
| RF04 | Procesamiento local | sin permiso `INTERNET` en el manifiesto · aviso "Funciona sin conexión" en la pantalla de inicio |
| RF05 | Salida por voz | `data/services/tts_service.dart` |
| RF06 | Captura con cámara, enfoque y linterna | `data/services/camera_service.dart` · `_updateTorch` en `recognition_view_model.dart` |
| RF07 | Actualizar modelos sin reinstalar | `data/services/model_storage_service.dart` (SHA-256, sustitución atómica, reversión) |
| RF08 | Modo de diagnóstico | `data/services/diagnostics_service.dart` · `views/diagnostics_view.dart` |
| RF09 | Verificación de accesibilidad | `Semantics` en todos los controles, incluida la vista de cámara |
| RF10 | Registro y exportación de hallazgos | `DiagnosticsService.addFinding` · `exportReport` · pantalla de diagnóstico |

### Requisitos no funcionales

| Req. | Métrica | Cómo se cumple / verifica |
|---|---|---|
| RNF-R1 | OCR ≤ 2 s en el 90 % | Medido en vivo; percentil 90 en la pantalla de diagnóstico |
| RNF-R2 | Billetes ≤ 1,5 s en el 90 % | Ídem, con su propio umbral |
| RNF-R3 | RA ≥ 20 fps | Preprocesado en una sola pasada; el análisis se detiene mientras habla la voz |
| RNF-R4 | Arranque ≤ 3 s | TTS y registro se preparan en segundo plano, no bloquean `runApp` |
| RNF-R5 | ≤ 350 MB RAM | Búferes reutilizados entre fotogramas; sin copias del fotograma completo |
| RNF-S1 | 0 peticiones de red | Sin permiso `INTERNET`: lo garantiza el sistema operativo, no solo el código |
| RNF-S2 | Permisos mínimos | Solo `CAMERA` y `FLASHLIGHT`, explicados en `widgets/permission_gate.dart` |
| RNF-S3 | Integridad de actualizaciones | SHA-256 verificado antes de activar el modelo (`ModelStorageService.install`) |
| RNF-F1 | ≥ 95 % en billetes | Depende del modelo; umbral de anuncio y NMS en el detector |
| RNF-F2 | ≥ 90 % en OCR | ML Kit v2 + estabilización por palabras entre fotogramas |
| RNF-F3 | Errores accesibles, 0 cierres | `runZonedGuarded` + `FlutterError.onError` registran y no cierran; los errores se **dicen en voz** y ofrecen alternativa |
| RNF-F4 | Confianza ≥ 85 % | `DetectBanknoteUseCase.announceThreshold`; por debajo se pide repetir la captura en voz alta |
| RNF-D1 | 100 % offline | Todos los modelos empaquetados; nada requiere red |
| RNF-D2 | ≤ 15 % batería / 30 min | Intervalo mínimo entre análisis y pausa mientras habla la voz |
| RNF-U1 | 100 % etiquetado | `Semantics` en botones, conmutadores, panel de resultado y vista de cámara |
| RNF-U2 | Alto contraste | `core/theme/app_colors.dart`, todos los pares ≥ 7:1 |
| RNF-U3 | Área táctil amplia | Mínimo 96 dp (`core/constants/app_dimens.dart`) |

### Indicadores audibles (apartado 3.1.1)

"Buscando texto", "Buscando billete", "Acerque el objeto", "Poca luz",
"Billete detectado" y los mensajes de error se anuncian por voz y se exponen a
TalkBack como región viva en la barra superior.

---

## 9. Modo de diagnóstico

Pulsación **larga** sobre el pie de la pantalla de inicio ("Diseñado para baja
visibilidad"). Es intencionadamente discreto: sirve al desarrollador y al
tester, no al usuario final.

Contiene:

- Tiempos de inferencia por módulo con el percentil 90 y el veredicto frente a
  RNF-R1 y RNF-R2.
- Tasa de fallos de reconocimiento.
- Registro local de errores y excepciones no controladas.
- Registro de hallazgos de pruebas (pantalla, descripción, severidad, requisito
  afectado) con cierre y borrado.
- Exportación de todo a un informe de texto en el área privada de la aplicación.

Nada de esto contiene imágenes, texto reconocido ni datos personales.

---

## 10. Actualizar el modelo sin reinstalar (RF07)

`ModelStorageService` busca primero un modelo en el almacenamiento privado de
la aplicación y solo usa el empaquetado si no hay ninguno instalado.

Para instalar uno nuevo se verifica su **SHA-256** antes de activarlo; la
sustitución es atómica y la versión anterior se conserva para revertir.

La descarga por HTTPS que menciona la ERS se deja fuera a propósito: añadir el
permiso `INTERNET` debilitaría la garantía de RNF-S1, que hoy la impone el
propio sistema operativo. El paquete se entrega como archivo local y la
verificación de integridad se aplica igual.

---

## 11. Lo que queda fuera de esta versión

- **Estabilización de vídeo por hardware**: el plugin `camera` no la expone.
- **Descarga automática de modelos por HTTPS**: ver el apartado anterior.
