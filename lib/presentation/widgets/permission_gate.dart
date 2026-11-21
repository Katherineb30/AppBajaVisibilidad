// ==========================================================================
// Pantalla de permiso
// Capa MVVM: Presentacion
//
// Explica para que se necesita la camara y ofrece una unica accion enorme.
//
// Requisitos de la ERS que atiende:
//   - RNF-S2 permisos minimos explicados
//   - RNF-F3 alternativa
// ==========================================================================

import 'package:flutter/material.dart';

import '../../core/constants/app_dimens.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';

/// Pantalla que se muestra cuando falta el permiso de camara o la camara no
/// esta disponible. Un solo boton, enorme y etiquetado para TalkBack.
class PermissionGate extends StatelessWidget {
  const PermissionGate({
    super.key,
    required this.accent,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final Color accent;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppDimens.screenPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.no_photography_rounded, size: 92, color: accent),
          const SizedBox(height: 24),
          Text(
            AppStrings.cameraPermissionTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: AppDimens.bodySize,
              fontWeight: FontWeight.w600,
              color: AppColors.onDarkMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 32),
          Semantics(
            button: true,
            label: actionLabel,
            child: ExcludeSemantics(
              child: SizedBox(
                width: double.infinity,
                height: AppDimens.minTouchTarget,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: AppColors.onAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimens.radius),
                    ),
                  ),
                  onPressed: onAction,
                  child: Text(
                    actionLabel,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
