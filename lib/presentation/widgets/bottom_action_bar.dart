// ==========================================================================
// Barra inferior
// Capa MVVM: Presentacion
//
// INICIO y REPETIR. Sustituyen al boton de volver: al estar abajo y ocupar
// todo el ancho se alcanzan con el pulgar sin mirar.
//
// Requisitos de la ERS que atiende:
//   - RNF-U1
//   - RNF-U3
//   - RNF-F3 alternativa ante errores
// ==========================================================================

import 'package:flutter/material.dart';

import '../../core/constants/app_dimens.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Barra inferior fija con las dos acciones permanentes:
/// **INICIO** (vuelve a la pantalla principal) y **REPETIR** (relee el
/// resultado). Sustituye al boton "Volver" de la barra superior: al estar
/// abajo y ocupar todo el ancho es alcanzable con el pulgar y localizable
/// sin necesidad de ver la pantalla.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.accent,
    required this.onHome,
    required this.onRepeat,
    this.repeatEnabled = true,
  });

  final Color accent;
  final VoidCallback onHome;
  final VoidCallback onRepeat;
  final bool repeatEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: SizedBox(
        height: AppDimens.actionBarHeight,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: _ActionTile(
                label: AppStrings.actionHome,
                hint: AppStrings.actionHomeHint,
                icon: Icons.home_rounded,
                accent: accent,
                enabled: true,
                onTap: onHome,
                emphasized: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: _ActionTile(
                label: AppStrings.actionRepeat,
                hint: AppStrings.actionRepeatHint,
                icon: Icons.volume_up_rounded,
                accent: accent,
                enabled: repeatEnabled,
                onTap: onRepeat,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cada una de las dos mitades de la barra inferior.
///
/// Ocupa la mitad exacta del ancho para que la posicion sea predecible al
/// tacto: izquierda siempre INICIO, derecha siempre REPETIR.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.label,
    required this.hint,
    required this.icon,
    required this.accent,
    required this.enabled,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;
  final String hint;
  final IconData icon;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? accent : AppColors.outline;
    final textColor = enabled ? accent : AppColors.onDarkMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      hint: hint,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(AppDimens.radius),
            child: Ink(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppDimens.radius),
                border: Border.all(color: color, width: AppDimens.borderWidth),
                boxShadow:
                    enabled && emphasized ? AppTheme.glow(accent, strength: 0.5) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: emphasized ? 38 : 32, color: textColor),
                  const SizedBox(height: 6),
                  FittedBox(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: emphasized ? 26 : 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
