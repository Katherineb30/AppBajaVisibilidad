// ==========================================================================
// Capa de realidad aumentada
// Capa MVVM: Presentacion
//
// Esquinas de encuadre, resaltado del texto, caja del billete y linea de
// barrido, todo en alto contraste.
//
// Requisitos de la ERS que atiende:
//   - RF02 realidad aumentada
//   - RNF-R3 fluidez
// ==========================================================================

import 'package:flutter/material.dart';

import '../../data/models/banknote_detection.dart';
import '../../data/models/detected_text_block.dart';

/// Esquinas del encuadre. Orientan al usuario sobre la zona util de la camara
/// sin tapar la escena.
class CornerFramePainter extends CustomPainter {
  const CornerFramePainter({required this.color, this.inset = 18});

  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final arm = size.shortestSide * 0.11;
    final l = inset;
    final t = inset;
    final r = size.width - inset;
    final b = size.height - inset;

    void corner(Offset origin, double dx, double dy) {
      canvas.drawLine(origin, origin.translate(dx * arm, 0), paint);
      canvas.drawLine(origin, origin.translate(0, dy * arm), paint);
    }

    corner(Offset(l, t), 1, 1);
    corner(Offset(r, t), -1, 1);
    corner(Offset(l, b), 1, -1);
    corner(Offset(r, b), -1, -1);
  }

  @override
  bool shouldRepaint(CornerFramePainter old) => old.color != color;
}

/// Resalta cada linea de texto reconocida (RF02 - realidad aumentada).
class TextHighlightPainter extends CustomPainter {
  const TextHighlightPainter({required this.blocks, required this.color});

  final List<DetectedTextBlock> blocks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (blocks.isEmpty) return;

    final fill = Paint()..color = color.withValues(alpha: 0.14);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    for (final block in blocks) {
      final rect = Rect.fromLTRB(
        block.rect.left * size.width,
        block.rect.top * size.height,
        block.rect.right * size.width,
        block.rect.bottom * size.height,
      ).inflate(4);
      if (rect.width < 6 || rect.height < 6) continue;

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas.drawRRect(rrect, glow);
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);
    }
  }

  @override
  bool shouldRepaint(TextHighlightPainter old) =>
      old.blocks != blocks || old.color != color;
}

/// Dibuja la caja del billete detectado con su denominacion.
class BanknoteBoxPainter extends CustomPainter {
  BanknoteBoxPainter({
    required this.detections,
    required this.color,
    required this.textDirection,
  });

  final List<BanknoteDetection> detections;
  final Color color;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final stroke = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final handle = Paint()..color = color;

    for (final d in detections) {
      final rect = Rect.fromLTRB(
        d.rect.left * size.width,
        d.rect.top * size.height,
        d.rect.right * size.width,
        d.rect.bottom * size.height,
      );
      if (rect.width < 12 || rect.height < 12) continue;

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
      canvas.drawRRect(rrect, glow);
      canvas.drawRRect(rrect, stroke);

      for (final c in [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ]) {
        canvas.drawCircle(c, 7, handle);
      }

      _paintLabel(canvas, rect, d.displayAmount);
    }
  }

  void _paintLabel(Canvas canvas, Rect rect, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          color: Colors.black,
        ),
      ),
      textDirection: textDirection,
    )..layout();

    final chip = Rect.fromCenter(
      center: Offset(rect.center.dx, rect.top - 4),
      width: painter.width + 28,
      height: painter.height + 14,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip, const Radius.circular(10)),
      Paint()..color = color,
    );
    painter.paint(
      canvas,
      Offset(chip.center.dx - painter.width / 2, chip.center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(BanknoteBoxPainter old) =>
      old.detections != detections || old.color != color;
}

/// Linea de barrido animada que indica que el analisis esta en curso.
class ScanLine extends StatefulWidget {
  const ScanLine({super.key, required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  State<ScanLine> createState() => _ScanLineState();
}

/// Estado de la linea de barrido.
///
/// La animacion se detiene cuando no se esta analizando: un AnimationController
/// corriendo sin necesidad consume bateria (RNF-D2).
class _ScanLineState extends State<ScanLine> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant ScanLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Align(
            alignment: Alignment(0, _controller.value * 2 - 1),
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.6),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
