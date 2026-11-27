// ==========================================================================
// Repositorio de preferencias
// Capa MVVM: Datos
//
// Cumple el contrato de preferencias usando la base de datos SQLite.
// Los valores si/no se guardan como "1" y "0".
// ==========================================================================

import '../../domain/repositories/i_preferences_repository.dart';
import '../services/database_service.dart';

class PreferencesRepository implements IPreferencesRepository {
  PreferencesRepository(this._db);

  final DatabaseService _db;

  @override
  Future<bool?> leerBool(String clave) async {
    final valor = await _db.leer(clave);
    if (valor == null) return null;
    return valor == '1';
  }

  @override
  Future<void> guardarBool(String clave, bool valor) =>
      _db.guardar(clave, valor ? '1' : '0');
}
