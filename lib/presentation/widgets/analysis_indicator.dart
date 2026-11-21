// ==========================================================================
// Indicador de analisis
// Capa MVVM: Presentacion
//
// Progreso visual del analisis. La informacion equivalente se entrega por voz
// y por vibracion.
//
// Requisitos de la ERS que atiende:
//   - 3.1.1 indicador de estado
// ==========================================================================

import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';

/// Indicador de progreso del analisis: barra + etiqueta "DETECTANDO...".
/// Es puramente visual (para el resto visual del usuario); la informacion
/// equivalente se entrega por voz y por vibracion.
class AnalysisIndicator extends StatelessWidget {
  const AnalysisIndicator({
    super.key,
    required this.accent,
    required this.progress,
    required this.visible,
  });

  final Color accent;
  final double progress;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${AppStrings.analyzing}... ${(progress * 100).round()}%',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: accent,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.outline,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                AppStrings.detecting,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  color: AppColors.onAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
