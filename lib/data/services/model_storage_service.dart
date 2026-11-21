// ==========================================================================
// Actualizacion de modelos
// Capa MVVM: Datos
//
// Resuelve que modelo se usa e instala versiones nuevas verificando su huella
// SHA-256, con sustitucion atomica y posibilidad de revertir.
//
// Requisitos de la ERS que atiende:
//   - RF07 actualizar modelos
//   - RNF-S3 integridad
// ==========================================================================

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Origen desde el que se cargara el modelo: el fichero actualizado si existe,
/// o el que viaja empaquetado en la aplicacion.
class ModelSource {
  const ModelSource.asset(this.assetPath) : file = null;
  const ModelSource.file(this.file) : assetPath = null;

  final String? assetPath;
  final File? file;

  bool get isUpdated => file != null;
}

/// Actualizacion de los modelos sin reinstalar la aplicacion
/// (RF07 - CU07, RNF-S3).
///
/// El modelo activo se busca primero en el almacenamiento privado de la
/// aplicacion; si no hay ninguno instalado se usa el que viene empaquetado.
/// Instalar uno nuevo exige **verificar su huella SHA-256** antes de activarlo,
/// la sustitucion es atomica (se escribe aparte y se renombra al final) y la
/// version anterior se conserva para poder revertir.
///
/// La descarga por HTTPS descrita en RF07 se deja deliberadamente fuera: la
/// aplicacion no declara el permiso INTERNET, que es lo que garantiza por si
/// solo el requisito RNF-S1 ("ningun dato sale del dispositivo"). El paquete
/// se entrega como fichero local, por ejemplo mediante `adb push` o el gestor
/// de archivos, y la verificacion de integridad se aplica igual.
class ModelStorageService {
  ModelStorageService({
    this.fileName = 'billetes_yolov8.tflite',
    this.assetPath = 'assets/models/billetes_yolov8.tflite',
  });

  final String fileName;
  final String assetPath;

  Future<Directory> _modelsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _activeFile() async =>
      File('${(await _modelsDir()).path}/$fileName');

  Future<File> _backupFile() async =>
      File('${(await _modelsDir()).path}/$fileName.anterior');

  /// Devuelve el origen que debe usar el detector.
  Future<ModelSource> resolve() async {
    try {
      final active = await _activeFile();
      if (await active.exists() && await active.length() > 1024) {
        debugPrint('ModelStorage: usando modelo actualizado en ${active.path}');
        return ModelSource.file(active);
      }
    } catch (e) {
      debugPrint('ModelStorage: no se pudo resolver el modelo -> $e');
    }
    return ModelSource.asset(assetPath);
  }

  /// Huella SHA-256 en minusculas de un fichero.
  Future<String> sha256Of(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// Instala [source] como modelo activo si su huella coincide con
  /// [expectedSha256]. Devuelve null si todo fue bien, o el motivo del fallo.
  ///
  /// Nada se toca hasta que la verificacion pasa, de modo que un paquete
  /// corrupto deja el modelo anterior intacto y en funcionamiento.
  Future<String?> install(File source, String expectedSha256) async {
    try {
      if (!await source.exists()) return 'El archivo no existe.';

      final real = await sha256Of(source);
      if (real.toLowerCase() != expectedSha256.trim().toLowerCase()) {
        return 'La huella no coincide. Esperada $expectedSha256, obtenida $real.';
      }

      final dir = await _modelsDir();
      final temp = File('${dir.path}/$fileName.nuevo');
      await source.copy(temp.path);

      final active = await _activeFile();
      if (await active.exists()) {
        final backup = await _backupFile();
        if (await backup.exists()) await backup.delete();
        await active.rename(backup.path);
      }

      // Renombrar es atomico dentro del mismo sistema de ficheros: o esta el
      // modelo nuevo entero, o sigue el anterior. Nunca uno a medias.
      await temp.rename(active.path);
      debugPrint('ModelStorage: modelo actualizado e instalado.');
      return null;
    } catch (e) {
      return 'Fallo al instalar: $e';
    }
  }

  /// Vuelve al modelo anterior. Devuelve true si se pudo revertir.
  Future<bool> rollback() async {
    try {
      final backup = await _backupFile();
      if (!await backup.exists()) return false;
      final active = await _activeFile();
      if (await active.exists()) await active.delete();
      await backup.rename(active.path);
      debugPrint('ModelStorage: revertido al modelo anterior.');
      return true;
    } catch (e) {
      debugPrint('ModelStorage: no se pudo revertir -> $e');
      return false;
    }
  }

  /// Elimina el modelo instalado y vuelve al empaquetado en la aplicacion.
  Future<void> restoreBundled() async {
    try {
      final active = await _activeFile();
      if (await active.exists()) await active.delete();
      final backup = await _backupFile();
      if (await backup.exists()) await backup.delete();
    } catch (e) {
      debugPrint('ModelStorage: no se pudo restaurar el empaquetado -> $e');
    }
  }

  /// Descripcion legible del estado, para la pantalla de diagnostico.
  Future<String> describe() async {
    final active = await _activeFile();
    if (await active.exists()) {
      final kb = (await active.length()) / 1024;
      final huella = (await sha256Of(active)).substring(0, 16);
      return 'Modelo actualizado (${kb.toStringAsFixed(0)} KB)\nSHA-256: $huella...';
    }
    return 'Modelo empaquetado con la aplicacion';
  }
}
