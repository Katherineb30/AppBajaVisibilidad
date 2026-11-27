// ==========================================================================
// Servicio de base de datos local
// Capa MVVM: Datos
//
// Base de datos SQLite guardada dentro del celular (archivo visionapp.db).
// Tiene una sola tabla, "preferencias", con pares clave-valor. No necesita
// Internet ni guarda imagenes ni texto reconocido.
//
// Requisitos de la ERS que atiende:
//   - RF-03 procesamiento local
//   - RNF-01 funcionamiento sin conexion
// ==========================================================================

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static const String _nombreArchivo = 'visionapp.db';
  static const String tablaPreferencias = 'preferencias';

  Database? _db;

  /// Abre la base de datos la primera vez que se necesita.
  /// Si el archivo no existe, lo crea junto con la tabla.
  Future<Database> _abrir() async {
    final abierta = _db;
    if (abierta != null) return abierta;
    final ruta = join(await getDatabasesPath(), _nombreArchivo);
    final db = await openDatabase(
      ruta,
      version: 1,
      onCreate: (db, version) => db.execute(
        'CREATE TABLE $tablaPreferencias ('
        'clave TEXT PRIMARY KEY, '
        'valor TEXT NOT NULL)',
      ),
    );
    _db = db;
    return db;
  }

  /// Devuelve el valor guardado para [clave], o null si no existe.
  Future<String?> leer(String clave) async {
    final db = await _abrir();
    final filas = await db.query(
      tablaPreferencias,
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [clave],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return filas.first['valor'] as String?;
  }

  /// Guarda [valor] en [clave]. Si la clave ya existe, la reemplaza.
  Future<void> guardar(String clave, String valor) async {
    final db = await _abrir();
    await db.insert(
      tablaPreferencias,
      {'clave': clave, 'valor': valor},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
