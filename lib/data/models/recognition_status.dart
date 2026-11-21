// ==========================================================================
// Estados del reconocimiento
// Capa MVVM: Datos
//
// Ciclo de vida comun a los dos modulos, desde pedir permiso hasta el
// resultado o el fallo.
//
// Requisitos de la ERS que atiende:
//   - RNF-F3 manejo de errores
// ==========================================================================

/// Estado del ciclo de reconocimiento, comun a los dos modulos.
enum RecognitionStatus {
  /// Aun no se ha inicializado la camara.
  idle,

  /// Pidiendo o esperando el permiso de camara.
  requestingPermission,

  /// Permiso denegado: la funcion principal no puede operar.
  permissionDenied,

  /// Camara lista, buscando el objetivo.
  searching,

  /// Procesando un fotograma.
  analyzing,

  /// Hay un resultado valido.
  success,

  /// Se analizo pero no se encontro nada utilizable.
  notFound,

  /// Fallo tecnico (camara, modelo, etc.).
  error,
}

extension RecognitionStatusX on RecognitionStatus {
  bool get isBusy =>
      this == RecognitionStatus.analyzing ||
      this == RecognitionStatus.requestingPermission;

  bool get cameraReady =>
      this == RecognitionStatus.searching ||
      this == RecognitionStatus.analyzing ||
      this == RecognitionStatus.success ||
      this == RecognitionStatus.notFound;
}
