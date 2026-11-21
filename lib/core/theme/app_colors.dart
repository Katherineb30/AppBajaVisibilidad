// ==========================================================================
// Paleta de alto contraste
// Capa MVVM: Core
//
// Todos los pares texto/fondo superan la relacion 7:1 de WCAG 2.1 AAA.
// Amarillo para el modulo de texto, verde para el de dinero.
//
// Requisitos de la ERS que atiende:
//   - RNF-U2 alto contraste
// ==========================================================================

import 'package:flutter/material.dart';

/// Paleta de alto contraste definida para baja visibilidad.
///
/// Todos los pares texto/fondo superan la relacion de contraste 7:1 exigida
/// por WCAG 2.1 nivel AAA (RNF-U2).
class AppColors {
  const AppColors._();

  // --- Base ---
  static const Color background = Color(0xFF050505);
  static const Color surface = Color(0xFF121212);
  static const Color surfaceAlt = Color(0xFF1C1C1C);
  static const Color outline = Color(0xFF2E2E2E);

  // --- Modulo TEXTO (amarillo) ---
  static const Color textAccent = Color(0xFFFFE500);
  static const Color textAccentDim = Color(0xFF6B6100);

  // --- Modulo DINERO (verde) ---
  static const Color moneyAccent = Color(0xFF00FF85);
  static const Color moneyAccentDim = Color(0xFF00693A);

  // --- Denominacion / chips ---
  static const Color chipGold = Color(0xFFE8A33D);

  // --- Texto ---
  static const Color onDark = Color(0xFFFFFFFF);
  static const Color onDarkMuted = Color(0xFFB0B0B0);
  static const Color onAccent = Color(0xFF000000);

  // --- Estados ---
  static const Color error = Color(0xFFFF5A5A);
  static const Color warning = Color(0xFFFFB020);
}
