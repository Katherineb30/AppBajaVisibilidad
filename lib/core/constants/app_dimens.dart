// ==========================================================================
// Medidas de accesibilidad
// Capa MVVM: Core
//
// Tamanos pensados para baja vision: objetivos tactiles muy por encima del
// minimo de 48 dp y tipografia grande.
//
// Requisitos de la ERS que atiende:
//   - RNF-U3 area tactil amplia
//   - RNF-U4 tipografia grande
// ==========================================================================

/// Medidas pensadas para usuarios con baja vision:
/// objetivos tactiles muy superiores al minimo de 48 dp y tipografia grande.
class AppDimens {
  const AppDimens._();

  /// Altura minima de cualquier boton de la aplicacion (RNF-U3).
  static const double minTouchTarget = 96.0;

  /// Altura de los botones principales de la pantalla de inicio.
  static const double primaryButtonHeight = 190.0;

  /// Altura de la barra inferior de acciones (INICIO / REPETIR).
  static const double actionBarHeight = 120.0;

  static const double screenPadding = 20.0;
  static const double gap = 18.0;
  static const double radius = 26.0;
  static const double borderWidth = 3.0;

  // Tipografia
  static const double titleSize = 40.0;
  static const double buttonLabelSize = 34.0;
  static const double bodySize = 24.0;
  static const double captionSize = 17.0;
  static const double resultSize = 46.0;
}
