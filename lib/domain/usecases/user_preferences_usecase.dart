// ==========================================================================
// Caso de uso - preferencias del usuario
// Capa MVVM: Dominio
//
// Recuerda entre sesiones si el usuario dejo activada la realidad aumentada
// y la deteccion automatica. Si no hay nada guardado, ambas van activadas.
// ==========================================================================

import '../repositories/i_preferences_repository.dart';

class UserPreferencesUseCase {
  UserPreferencesUseCase(this._repository);

  final IPreferencesRepository _repository;

  static const String _realidadAumentada = 'realidad_aumentada';
  static const String _deteccionAutomatica = 'deteccion_automatica';

  Future<bool> cargarRealidadAumentada() async =>
      await _repository.leerBool(_realidadAumentada) ?? true;

  Future<void> guardarRealidadAumentada(bool activa) =>
      _repository.guardarBool(_realidadAumentada, activa);

  Future<bool> cargarDeteccionAutomatica() async =>
      await _repository.leerBool(_deteccionAutomatica) ?? true;

  Future<void> guardarDeteccionAutomatica(bool activa) =>
      _repository.guardarBool(_deteccionAutomatica, activa);
}
