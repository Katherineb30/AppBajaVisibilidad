// ==========================================================================
// Barra superior
// Capa MVVM: Presentacion
//
// Indicador de estado permanente y audible, conmutador de modo automatico y
// de la capa de realidad aumentada. Sin boton de volver.
//
// Requisitos de la ERS que atiende:
//   - 3.1.1 indicador audible
//   - RF02 RA desactivable
// ==========================================================================

import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';

/// Barra superior de las pantallas de reconocimiento.
///
/// No lleva boton "Volver": la navegacion de retorno se hace con el boton
/// INICIO de la barra inferior, mucho mas grande y facil de localizar sin
/// vision, y con el gesto de retroceso del sistema.
///
/// El indicador de estado es permanente y se expone a TalkBack como region
/// viva, para que el lector anuncie los cambios ("Buscando texto", "Acerque el
/// objeto", "Poca luz") tal como pide el apartado 3.1.1 de la ERS.
class ScanTopBar extends StatelessWidget {
  const ScanTopBar({
    super.key,
    required this.accent,
    required this.status,
    required this.autoMode,
    required this.onToggleAuto,
    required this.torchOn,
    required this.onToggleTorch,
    required this.overlayEnabled,
    required this.onToggleOverlay,
  });

  final Color accent;
  final String status;
  final bool autoMode;
  final VoidCallback onToggleAuto;
  final bool torchOn;

  /// La linterna se enciende sola con poca luz, pero el usuario tiene que
  /// poder apagarla sin depender de un gesto que no se ve: de ahi este boton.
  final VoidCallback onToggleTorch;

  /// RF02: la capa de realidad aumentada es opcional.
  final bool overlayEnabled;
  final VoidCallback onToggleOverlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              label: status,
              child: ExcludeSemantics(
                child: Container(
                  height: 54,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(27),
                    border: Border.all(color: accent, width: 2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onDark,
                          ),
                        ),
                      ),
                      if (torchOn)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.flashlight_on,
                            size: 22,
                            color: AppColors.warning,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _Chip(
            accent: accent,
            active: autoMode,
            label: autoMode ? AppStrings.autoOn : AppStrings.autoOff,
            semanticLabel: autoMode
                ? 'Deteccion automatica activada'
                : 'Deteccion manual activada',
            hint: AppStrings.autoHint,
            onTap: onToggleAuto,
          ),
          const SizedBox(width: 8),
          _IconToggle(
            accent: accent,
            active: torchOn,
            icon: torchOn ? Icons.flashlight_on : Icons.flashlight_off,
            semanticLabel:
                torchOn ? 'Linterna encendida' : 'Linterna apagada',
            hint: AppStrings.torchHint,
            onTap: onToggleTorch,
          ),
          const SizedBox(width: 8),
          _IconToggle(
            accent: accent,
            active: overlayEnabled,
            icon: overlayEnabled
                ? Icons.center_focus_strong
                : Icons.center_focus_weak,
            semanticLabel: overlayEnabled
                ? 'Resaltado visual activado'
                : 'Resaltado visual desactivado',
            hint: AppStrings.overlayHint,
            onTap: onToggleOverlay,
          ),
        ],
      ),
    );
  }
}

/// Etiqueta de estado de la barra superior.
///
/// Se declara como region viva de accesibilidad: TalkBack anuncia el cambio de
/// estado por si solo, que es como se cumple el aviso audible permanente sin
/// que la voz de la aplicacion se solape con la del lector de pantalla.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.accent,
    required this.active,
    required this.label,
    required this.semanticLabel,
    required this.hint,
    required this.onTap,
  });

  final Color accent;
  final bool active;
  final String label;
  final String semanticLabel;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: active,
      label: semanticLabel,
      hint: hint,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(27),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? accent : AppColors.surface,
              borderRadius: BorderRadius.circular(27),
              border: Border.all(color: accent, width: 2),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                color: active ? AppColors.onAccent : AppColors.onDarkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Conmutador de la barra superior (modo automatico y capa de realidad
/// aumentada), con etiqueta y estado expuestos al lector de pantalla.
class _IconToggle extends StatelessWidget {
  const _IconToggle({
    required this.accent,
    required this.active,
    required this.icon,
    required this.semanticLabel,
    required this.hint,
    required this.onTap,
  });

  final Color accent;
  final bool active;
  final IconData icon;
  final String semanticLabel;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: active,
      label: semanticLabel,
      hint: hint,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(27),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: active ? accent : AppColors.surface,
              borderRadius: BorderRadius.circular(27),
              border: Border.all(color: accent, width: 2),
            ),
            child: Icon(
              icon,
              size: 26,
              color: active ? AppColors.onAccent : AppColors.onDarkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
