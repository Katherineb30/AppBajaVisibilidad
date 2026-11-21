// ==========================================================================
// Boton principal
// Capa MVVM: Presentacion
//
// Ocupa media pantalla: con baja vision el area util del control importa mas
// que su estetica.
//
// Requisitos de la ERS que atiende:
//   - RNF-U3 area tactil
// ==========================================================================

import 'package:flutter/material.dart';

import '../../core/constants/app_dimens.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Boton principal de la pantalla de inicio.
///
/// Ocupa media pantalla a proposito: con baja vision el area util del control
/// importa mas que su estetica. Toda la tarjeta es un unico objetivo tactil.
class BigActionButton extends StatelessWidget {
  const BigActionButton({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.semanticHint,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? semanticHint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      hint: semanticHint,
      child: ExcludeSemantics(
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(AppDimens.radius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppDimens.radius),
            child: Ink(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppDimens.radius),
                boxShadow: AppTheme.glow(color, strength: 0.7),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 22,
                  horizontal: 18,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(icon, size: 42, color: color),
                    ),
                    const SizedBox(height: 16),
                    FittedBox(
                      child: Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: AppColors.onAccent),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: AppDimens.captionSize,
                        fontWeight: FontWeight.w700,
                        color: Color(0xCC000000),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
