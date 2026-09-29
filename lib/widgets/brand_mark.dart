import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Minimal logo: an isometric cube drawn with hairlines, the way a plan sheet
/// would show a volume study.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72, this.color = AppColors.ink});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CubePainter(color)),
    );
  }
}

class _CubePainter extends CustomPainter {
  _CubePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.025
      ..strokeJoin = StrokeJoin.round;

    final cx = size.width / 2;
    final top = Offset(cx, s * 0.06);
    final right = Offset(s * 0.94, s * 0.30);
    final bottomRight = Offset(s * 0.94, s * 0.72);
    final bottom = Offset(cx, s * 0.96);
    final bottomLeft = Offset(s * 0.06, s * 0.72);
    final left = Offset(s * 0.06, s * 0.30);
    final center = Offset(cx, s * 0.51);

    final outline = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..lineTo(left.dx, left.dy)
      ..close();
    canvas.drawPath(outline, stroke);

    final inner = Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(center.dx, center.dy)
      ..lineTo(right.dx, right.dy)
      ..moveTo(center.dx, center.dy)
      ..lineTo(bottom.dx, bottom.dy);
    canvas.drawPath(inner, stroke);
  }

  @override
  bool shouldRepaint(_CubePainter oldDelegate) => oldDelegate.color != color;
}
