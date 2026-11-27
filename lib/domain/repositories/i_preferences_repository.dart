// ==========================================================================
// Contrato - preferencias del usuario
// Capa MVVM: Dominio
//
// Dice que se puede leer y guardar una preferencia de si/no, sin decir
// donde se guarda. El caso de uso depende de este contrato, no de SQLite.
// ==========================================================================

abstract class IPreferencesRepository {
  /// Devuelve la preferencia guardada, o null si nunca se ha guardado.
  Future<bool?> leerBool(String clave);

  /// Guarda la preferencia.
  Future<void> guardarBool(String clave, bool valor);
}
