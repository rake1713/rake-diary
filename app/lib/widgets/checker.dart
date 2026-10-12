import 'package:flutter/material.dart';

/// Шашечки такси — фирменный знак приложения, без картинок.
class CheckerStrip extends StatelessWidget {
  const CheckerStrip({
    super.key,
    required this.color,
    this.cell = 10,
    this.rows = 2,
  });

  final Color color;
  final double cell;
  final int rows;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: cell * rows,
      width: double.infinity,
      child: CustomPaint(painter: _CheckerPainter(color, cell, rows)),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter(this.color, this.cell, this.rows);

  final Color color;
  final double cell;
  final int rows;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final cols = (size.width / cell).ceil();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if ((r + c).isEven) {
          canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) =>
      old.color != color || old.cell != cell || old.rows != rows;
}
