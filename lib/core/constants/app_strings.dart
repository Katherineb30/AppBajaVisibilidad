// ==========================================================================
// Textos y guiones de voz
// Capa MVVM: Core
//
// Un unico lugar para el texto de la interfaz y lo que se dice en voz alta,
// de modo que la etiqueta accesible y el guion hablado no se desincronicen.
//
// Requisitos de la ERS que atiende:
//   - RNF-U1 etiquetas para TalkBack
//   - 3.1.1 indicadores audibles
// ==========================================================================

/// Textos de la interfaz y guiones de voz.
///
/// Se centralizan aqui para que el guion hablado y la etiqueta accesible
/// (TalkBack) de cada control se mantengan sincronizados.
class AppStrings {
  const AppStrings._();

  static const String appName = 'VisionApp';
  static const String appTagline = 'Asistente visual inteligente';
  static const String appFooter = 'Disenado para baja visibilidad';

  // --- Inicio ---
  static const String textModuleTitle = 'TEXTO';
  static const String textModuleSubtitle = 'Leer texto con la camara';
  static const String moneyModuleTitle = 'DINERO';
  static const String moneyModuleSubtitle = 'Identificar billetes';

  static const String homeWelcome =
      'Vision App. Asistente visual. Toque la parte superior de la pantalla '
      'para leer texto. Toque la parte inferior para identificar billetes. '
      'Todo funciona sin conexion a Internet.';

  // --- Barra de acciones ---
  static const String actionHome = 'INICIO';
  static const String actionRepeat = 'REPETIR';
  static const String actionHomeHint = 'Volver a la pantalla de inicio';
  static const String actionRepeatHint = 'Repetir en voz alta el ultimo resultado';

  // --- Modo automatico ---
  static const String autoOn = 'AUTO';
  static const String autoOff = 'MANUAL';
  static const String autoHint =
      'Alternar entre deteccion automatica continua y deteccion manual';

  // --- Estados de camara / deteccion ---
  static const String searchingText = 'Buscando texto';
  static const String searchingMoney = 'Buscando billete';
  static const String analyzing = 'ANALIZANDO';
  static const String detecting = 'DETECTANDO...';
  static const String preparingModel = 'Preparando el detector...';
  static const String moveCloser = 'Acerque el objeto';
  static const String lowLight = 'Poca luz. Encendiendo la linterna';
  static const String torchOnStatus = 'Poca luz. Linterna encendida';
  static const String torchForColor =
      'Encendiendo la linterna para distinguir mejor el color del billete';
  static const String torchOnSpoken = 'Linterna encendida';
  static const String torchOffSpoken = 'Linterna apagada';
  static const String torchHint =
      'Mantenga pulsada la vista de la camara para encender o apagar la linterna';
  static const String holdSteady = 'Mantenga el telefono quieto';

  // --- Resultados ---
  static const String detectedTextLabel = 'TEXTO DETECTADO';
  static const String detectedNoteLabel = 'BILLETE DETECTADO';
  static const String noTextFound = 'No se encontro texto. Acerque la camara al papel.';
  static const String noNoteFound = 'No se detecto ningun billete. Muestre el billete completo.';
  static const String lowConfidence =
      'No estoy seguro del billete. Cambie el angulo e intente de nuevo.';

  // --- Permisos y errores ---
  static const String cameraPermissionTitle = 'Permiso de camara';
  static const String cameraPermissionBody =
      'La aplicacion necesita la camara para reconocer texto y billetes. '
      'Toque el boton para conceder el permiso.';
  static const String grantPermission = 'CONCEDER PERMISO';
  static const String openSettings = 'ABRIR AJUSTES';
  static const String cameraUnavailable =
      'Sin acceso a la camara. Modo demostracion activo.';
  static const String modelMissing =
      'El modelo de billetes no esta disponible. Revise la instalacion.';
  static const String modelBroken =
      'El modelo de billetes no se pudo ejecutar. El archivo esta incompleto.';

  /// RNF-F3: todo error debe ofrecer una alternativa al usuario.
  static const String errorAlternative =
      'Pulse el boton inicio, abajo a la izquierda, para volver y elegir otro modo.';

  /// RF04 / RNF-D1: se informa de que la aplicacion funciona sin conexion.
  static const String offlineNotice = 'Funciona sin conexion a Internet';

  static const String cameraViewLabel = 'Vista de la camara';
  static const String cameraViewHintManual =
      'Toque dos veces para analizar. Mantenga pulsado para la linterna';
  static const String cameraViewHintAuto =
      'El analisis es automatico y continuo. '
      'Mantenga pulsado para encender o apagar la linterna';

  static const String overlayOn = 'RESALTADO';
  static const String overlayHint =
      'Activar o desactivar el resaltado visual sobre la camara';

  // --- Diagnostico (RF08 / RF10) ---
  static const String diagnosticsTitle = 'Diagnostico';
  static const String diagnosticsHint =
      'Abrir el modo de diagnostico y el registro de hallazgos';
  static const String genericError = 'Ocurrio un problema. Intente de nuevo.';
}
