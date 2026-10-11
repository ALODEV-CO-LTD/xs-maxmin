import 'package:flutter/material.dart';

import 'stats_logic.dart';

/// Bar chart drawn with CustomPaint (no chart package). Tap a bar to select it ([onSelect]).
class StatsBarChart extends StatelessWidget {
  const StatsBarChart({super.key, required this.points, required this.metric, required this.positive, required this.negative, required this.selected, required this.onSelect, this.height = 190});
  final List<StatPoint> points;
  final StatMetric metric;
  final Color positive, negative;
  final int selected;
  final ValueChanged<int> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final grid = Theme.of(context).colorScheme.outlineVariant;
    return LayoutBuilder(builder: (context, c) {
      final painter = _ChartPainter(points, metric, positive, negative, muted, grid, selected);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          final i = painter.indexAt(d.localPosition.dx, c.maxWidth);
          if (i != null) onSelect(i);
        },
        child: CustomPaint(size: Size(c.maxWidth, height), painter: painter),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.points, this.metric, this.pos, this.neg, this.muted, this.grid, this.selected);
  final List<StatPoint> points;
  final StatMetric metric;
  final Color pos, neg, muted, grid;
  final int selected;

  static const _l = 40.0, _r = 6.0, _t = 8.0, _b = 22.0;

  int? indexAt(double x, double width) {
    if (points.isEmpty) return null;
    final step = (width - _l - _r) / points.length;
    final i = ((x - _l) / step).floor();
    return i < 0 || i >= points.length ? null : i;
  }

  void _text(Canvas canvas, String s, Offset at, {TextAlign align = TextAlign.center}) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(fontSize: 9.5, color: muted)), textDirection: TextDirection.ltr)..layout();
    final dx = align == TextAlign.right ? at.dx - tp.width : at.dx - tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final vals = points.map((p) => p.value);
    var maxV = vals.fold<double>(0, (a, b) => b > a ? b : a);
    final minV = vals.fold<double>(0, (a, b) => b < a ? b : a);
    if (maxV == minV) maxV = minV + 1;
    final innerH = size.height - _t - _b;
    final innerW = size.width - _l - _r;
    double y(double v) => _t + ((maxV - v) / (maxV - minV)) * innerH;
    final step = innerW / points.length;
    final bw = (step * 0.45).clamp(3.0, 12.0);

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    final ticks = minV < 0 ? [maxV, 0.0, minV] : [maxV, maxV / 2, 0.0];
    for (final t in ticks) {
      canvas.drawLine(Offset(_l, y(t)), Offset(size.width - _r, y(t)), gridPaint);
      _text(canvas, shortNum(t), Offset(_l - 6, y(t)), align: TextAlign.right);
    }
    canvas.drawLine(Offset(_l, y(0)), Offset(size.width - _r, y(0)), Paint()..color = grid..strokeWidth = 1.2);

    final every = (points.length / (points.length > 12 ? 8 : 12)).ceil();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final cx = _l + step * i + step / 2;
      final y0 = y(0), y1 = y(p.value);
      final good = metric == StatMetric.profit ? p.value >= 0 : metric == StatMetric.vao;
      final dim = selected >= 0 && selected != i;
      final h = (y0 - y1).abs();
      final rect = Rect.fromLTWH(cx - bw / 2, y0 < y1 ? y0 : y1, bw, p.value == 0 ? 0 : (h < 1 ? 1 : h));
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), Paint()..color = (good ? pos : neg).withValues(alpha: dim ? 0.3 : 0.9));
      if ((points.length - 1 - i) % every == 0) _text(canvas, p.label, Offset(cx, size.height - 8));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter o) => o.points != points || o.selected != selected || o.metric != metric || o.pos != pos || o.muted != muted;
}
