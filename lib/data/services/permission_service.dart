// ==========================================================================
// Permisos
// Capa MVVM: Datos
//
// Unico permiso sensible de la aplicacion: la camara.
//
// Requisitos de la ERS que atiende:
//   - RNF-S2 permisos minimos
// ==========================================================================

import 'package:permission_handler/permission_handler.dart';

/// Gestion del unico permiso sensible que necesita la aplicacion: la camara.
///
/// No se pide almacenamiento, ni ubicacion, ni red: el procesamiento es
/// integramente local (RNF-S1).
class PermissionService {
  const PermissionService();

  Future<bool> hasCamera() async => Permission.camera.isGranted;

  /// Solicita el permiso. Devuelve true si quedo concedido.
  Future<bool> requestCamera() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<bool> isPermanentlyDenied() async =>
      Permission.camera.isPermanentlyDenied;

  Future<void> openSettings() => openAppSettings();
}
