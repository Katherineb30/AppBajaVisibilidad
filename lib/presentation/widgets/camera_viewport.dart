// ==========================================================================
// Vista de camara
// Capa MVVM: Presentacion
//
// Vista previa recortada y capas de realidad aumentada en el mismo sistema
// de coordenadas. Tambien es un control accesible.
//
// Requisitos de la ERS que atiende:
//   - RF02 realidad aumentada
//   - RNF-U1 etiquetado
// ==========================================================================

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';

/// Muestra la vista previa recortada al espacio disponible (efecto "cover")
/// y superpone las capas de realidad aumentada EN EL MISMO sistema de
/// coordenadas, de modo que las cajas normalizadas 0..1 que devuelven el OCR y
/// el detector caen exactamente sobre lo que se ve.
class CameraViewport extends StatelessWidget {
  const CameraViewport({
    super.key,
    required this.controller,
    this.overlays = const [],
    this.onTap,
    this.onLongPress,
    this.autoMode = true,
  });

  final CameraController? controller;
  final List<Widget> overlays;
  final VoidCallback? onTap;

  /// Control manual de la linterna.
  final VoidCallback? onLongPress;

  /// Cambia la ayuda que anuncia TalkBack: en manual la vista es pulsable.
  final bool autoMode;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null || !controller.value.isInitialized) {
      return _Placeholder(overlays: overlays);
    }


    final preview = controller.value.previewSize;
    // previewSize llega en orientacion horizontal del sensor; en retrato hay
    // que invertir los lados.
    final previewAspect =
        preview == null ? 3 / 4 : preview.height / preview.width;

    // RNF-U1: la vista de camara tambien se expone al lector de pantalla; en
    // modo manual es el control que dispara el analisis.
    return Semantics(
      label: AppStrings.cameraViewLabel,
      button: onTap != null,
      hint: autoMode
          ? AppStrings.cameraViewHintAuto
          : AppStrings.cameraViewHintManual,
      onTap: onTap,
      onLongPress: onLongPress,
      child: GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boxAspect = constraints.maxWidth / constraints.maxHeight;
          var scale = previewAspect / boxAspect;
          if (scale < 1) scale = 1 / scale;

          return ClipRect(
            child: Transform.scale(
              scale: scale,
              child: Center(
                child: AspectRatio(
                  aspectRatio: previewAspect,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(controller),
                      ...overlays,
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}

/// Relleno mientras la camara todavia no entrega imagen.
///
/// Evita el salto de composicion (y el parpadeo) que produciria montar la
/// vista previa a mitad de construccion.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.overlays});

  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.background),
        ...overlays,
      ],
    );
  }
}
