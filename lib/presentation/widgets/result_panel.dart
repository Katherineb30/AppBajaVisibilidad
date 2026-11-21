// ==========================================================================
// Panel de resultado
// Capa MVVM: Presentacion
//
// Texto reconocido en tipografia grande. Se excluye del arbol de
// accesibilidad a proposito para no duplicar la voz de la aplicacion.
//
// Requisitos de la ERS que atiende:
//   - 3.1.1 pantalla de resultado
//   - RNF-U1
// ==========================================================================

import 'package:flutter/material.dart';

import '../../core/constants/app_dimens.dart';
import '../../core/theme/app_colors.dart';

/// Panel de resultado bajo la vista previa.
///
/// El contenido se envuelve en [ExcludeSemantics] a proposito: el resultado ya
/// se esta leyendo con el motor de voz de la aplicacion y, si ademas lo
/// expusieramos al lector de pantalla como region viva, TalkBack lo repetiria
/// encima y se oirian dos voces a la vez. El acceso con TalkBack se hace por
/// el boton REPETIR, que si esta etiquetado.
class ResultPanel extends StatelessWidget {
  const ResultPanel({
    super.key,
    required this.accent,
    required this.label,
    required this.content,
    this.trailing,
    this.maxHeight = 210,
  });

  final Color accent;
  final String label;
  final String content;
  final Widget? trailing;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) return const SizedBox.shrink();

    return ExcludeSemantics(
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: accent, width: 2)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  content,
                  style: TextStyle(
                    fontSize: AppDimens.bodySize,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
