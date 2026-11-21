// ==========================================================================
// Tema de la aplicacion
// Capa MVVM: Core
//
// Tema unico oscuro, sin seguir al sistema: el alto contraste es la razon de
// ser de la aplicacion, no una preferencia.
//
// Requisitos de la ERS que atiende:
//   - RNF-U2 alto contraste
// ==========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_dimens.dart';
import 'app_colors.dart';

/// Tema unico de alto contraste. La aplicacion siempre usa fondo negro puro:
/// es la combinacion que mejor aprovecha el resto visual en baja vision y la
/// que menos fatiga produce en pantallas OLED.
class AppTheme {
  const AppTheme._();

  static const SystemUiOverlayStyle overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData build() {
    const base = ColorScheme.dark(
      primary: AppColors.textAccent,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.moneyAccent,
      onSecondary: AppColors.onAccent,
      surface: AppColors.surface,
      onSurface: AppColors.onDark,
      error: AppColors.error,
      onError: AppColors.onAccent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: base,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashFactory: InkRipple.splashFactory,
      // Fuentes gruesas: el trazo grueso es mas legible que el tamano por si solo.
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: AppDimens.resultSize,
          fontWeight: FontWeight.w900,
          color: AppColors.onDark,
          height: 1.1,
        ),
        headlineLarge: TextStyle(
          fontSize: AppDimens.titleSize,
          fontWeight: FontWeight.w900,
          color: AppColors.onDark,
          letterSpacing: 0.5,
        ),
        titleLarge: TextStyle(
          fontSize: AppDimens.buttonLabelSize,
          fontWeight: FontWeight.w900,
          color: AppColors.onDark,
          letterSpacing: 2.0,
        ),
        bodyLarge: TextStyle(
          fontSize: AppDimens.bodySize,
          fontWeight: FontWeight.w700,
          color: AppColors.onDark,
          height: 1.35,
        ),
        bodyMedium: TextStyle(
          fontSize: AppDimens.captionSize,
          fontWeight: FontWeight.w600,
          color: AppColors.onDarkMuted,
        ),
        labelLarge: TextStyle(
          fontSize: AppDimens.captionSize,
          fontWeight: FontWeight.w800,
          color: AppColors.onDarkMuted,
          letterSpacing: 1.6,
        ),
      ),
    );
  }

  /// Resplandor exterior que rodea a los elementos activos.
  /// Ayuda a localizar el foco cuando la agudeza visual es baja.
  static List<BoxShadow> glow(Color color, {double strength = 1.0}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.45 * strength),
          blurRadius: 26 * strength,
          spreadRadius: 1.5 * strength,
        ),
      ];
}
