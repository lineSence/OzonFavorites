import 'package:flutter/material.dart';
import '../models/price_point.dart';

/// Маленький график изменения цены по точкам истории.
/// Рисуется на CustomPainter без внешних зависимостей.
class PriceChart extends StatelessWidget {
  const PriceChart({super.key, required this.points, this.height = 140});
  final List<PricePoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return SizedBox(height: height, child: const Center(child: Text('Недостаточно данных для графика', style: TextStyle(color: Colors.black45))));
    }
    final colorScheme = Theme.of(context).colorScheme;
    final color = points.last.price < points.first.price ? Colors.green : colorScheme.primary;
    return SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _PriceChartPainter(points, color: color)));
  }
}

class _PriceChartPainter extends CustomPainter {
  _PriceChartPainter(this.points, {required this.color});
  final List<PricePoint> points;
  final Color color;

  static const _left = 42.0;
  static const _right = 10.0;
  static const _top = 10.0;
  static const _bottom = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final chartWidth = size.width - _left - _right;
    final chartHeight = size.height - _top - _bottom;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    var minPrice = points.first.price, maxPrice = points.first.price;
    for (final p in points) {
      if (p.price < minPrice) minPrice = p.price;
      if (p.price > maxPrice) maxPrice = p.price;
    }
    if (maxPrice == minPrice) { minPrice -= 1; maxPrice += 1; }
    final range = maxPrice - minPrice;

    Offset pointAt(int i) {
      final x = _left + chartWidth * (points.length == 1 ? 0 : i / (points.length - 1));
      final y = _top + chartHeight * (1 - (points[i].price - minPrice) / range);
      return Offset(x, y);
    }

    // Горизонтальная сетка.
    final gridPaint = Paint()..color = Colors.black.withValues(alpha: 0.07)..strokeWidth = 1;
    const gridLines = 3;
    for (var i = 0; i <= gridLines; i++) {
      final y = _top + chartHeight * i / gridLines;
      canvas.drawLine(Offset(_left, y), Offset(size.width - _right, y), gridPaint);
    }

    // Заливка под линией.
    final areaPath = Path()..moveTo(pointAt(0).dx, size.height - _bottom);
    for (var i = 0; i < points.length; i++) {
      areaPath.lineTo(pointAt(i).dx, pointAt(i).dy);
    }
    areaPath.lineTo(pointAt(points.length - 1).dx, size.height - _bottom);
    areaPath.close();
    canvas.drawPath(areaPath, Paint()..color = color.withValues(alpha: 0.12));

    // Линия.
    final linePath = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(pointAt(i).dx, pointAt(i).dy);
    }
    canvas.drawPath(linePath, Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round);

    // Точки; последняя выделена.
    final dotPaint = Paint()..color = color;
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(pointAt(i), i == points.length - 1 ? 4 : 2.5, dotPaint);
    }

    // Минимум и максимум слева.
    _drawLabel(canvas, _fmt(maxPrice), Offset(0, _top - 2), alignRight: true);
    _drawLabel(canvas, _fmt(minPrice), Offset(0, size.height - _bottom + 2), alignRight: true);

    // Даты первой и последней точки снизу.
    _drawLabel(canvas, _fmtDate(points.first.observedAt), Offset(pointAt(0).dx - 24, size.height - 18));
    _drawLabel(canvas, _fmtDate(points.last.observedAt), Offset(pointAt(points.length - 1).dx + 6, size.height - 18));
  }

  void _drawLabel(Canvas canvas, String text, Offset topLeft, {bool alignRight = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 10, color: Colors.black45)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, alignRight ? Offset(topLeft.dx - tp.width, topLeft.dy) : topLeft);
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _fmtDate(DateTime d) => '${d.day}.${d.month}';

  @override
  bool shouldRepaint(covariant _PriceChartPainter oldDelegate) => oldDelegate.points != points || oldDelegate.color != color;
}