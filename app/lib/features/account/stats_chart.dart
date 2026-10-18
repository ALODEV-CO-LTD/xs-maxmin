import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import 'stats_logic.dart';

/// The most bars any period shows (30 days); every period uses the bar width that fits this many.
const denseBars = 30;

/// Bar chart drawn with CustomPaint (no chart package). Tap a bar (the whole column is the hit area) to show a tooltip.
/// Profit: green above 0, red below; points in/out use [primary].
class StatsBarChart extends StatefulWidget {
  const StatsBarChart({
    super.key,
    required this.points,
    required this.metric,
    required this.primary,
    required this.positive,
    required this.negative,
    this.height = 220,
  });
  final List<StatPoint> points;
  final StatMetric metric;
  final Color primary, positive, negative;
  final double height;
  @override
  State<StatsBarChart> createState() => _StatsBarChartState();
}

class _StatsBarChartState extends State<StatsBarChart> {
  int _sel = -1;

  @override
  void didUpdateWidget(StatsBarChart old) {
    super.didUpdateWidget(old);
    if (old.points != widget.points || old.metric != widget.metric) _sel = -1;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.62);
    final pts = widget.points;
    final axis = niceAxis(
      pts.fold<double>(0, (a, p) => p.value < a ? p.value : a),
      pts.fold<double>(0, (a, p) => p.value > a ? p.value : a),
    );
    final desc =
        'Biểu đồ cột ${statMetricLabels[widget.metric]}, ${pts.length} kỳ${_sel >= 0 && _sel < pts.length ? '. Đang chọn ${pts[_sel].full}: ${formatNumber(pts[_sel].value)}' : ''}';
    return Semantics(
      container: true,
      label: desc,
      child: LayoutBuilder(
        builder: (context, c) {
          final painter = _ChartPainter(
            pts,
            widget.metric,
            axis,
            widget.primary,
            widget.positive,
            widget.negative,
            muted,
            cs.outlineVariant,
            cs.onSurface,
            _sel,
          );
          final sel = _sel >= 0 && _sel < pts.length ? _sel : -1;
          Widget? tip;
          if (sel >= 0) {
            final cx = painter.centerX(sel, c.maxWidth);
            final p = pts[sel];
            final neg = widget.metric == StatMetric.profit && p.value < 0;
            tip = Positioned(
              top: 0,
              left: (cx - 90).clamp(
                0.0,
                (c.maxWidth - 180).clamp(0.0, double.infinity),
              ),
              width: c.maxWidth < 180 ? c.maxWidth : 180,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant),
                    boxShadow: const [
                      BoxShadow(color: Color(0x22000000), blurRadius: 6),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.full,
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                      Text(
                        formatNumber(p.value),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: widget.metric == StatMetric.profit
                              ? (neg ? widget.negative : widget.positive)
                              : widget.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final i = painter.indexAt(d.localPosition.dx, c.maxWidth);
              setState(() => _sel = i == null || i == _sel ? -1 : i);
            },
            child: SizedBox(
              height: widget.height,
              width: c.maxWidth,
              child: Stack(
                children: [
                  CustomPaint(
                    size: Size(c.maxWidth, widget.height),
                    painter: painter,
                  ),
                  ?tip,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(
    this.points,
    this.metric,
    this.axis,
    this.primary,
    this.pos,
    this.neg,
    this.muted,
    this.grid,
    this.zeroColor,
    this.selected,
  );
  final List<StatPoint> points;
  final StatMetric metric;
  final YAxis axis;
  final Color primary, pos, neg, muted, grid, zeroColor;
  final int selected;

  static const _l = 46.0, _r = 6.0, _t = 8.0, _b = 24.0;

  double _step(double width) => (width - _l - _r) / points.length;
  double centerX(int i, double width) =>
      _l + _step(width) * i + _step(width) / 2;

  int? indexAt(double x, double width) {
    if (points.isEmpty) return null;
    final i = ((x - _l) / _step(width)).floor();
    return i < 0 || i >= points.length ? null : i;
  }

  TextPainter _tp(String s) => TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontSize: 10, color: muted),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final innerH = size.height - _t - _b;
    final range = axis.max - axis.min;
    double y(double v) => _t + ((axis.max - v) / range) * innerH;
    final step = _step(size.width);
    // One bar width for every period (day / week / month / year), sized for the densest one, so switching the period never resizes the bars.
    final bw =
        ((size.width - _l - _r) / math.max(denseBars, points.length) * 0.6)
            .clamp(3.0, 22.0);

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (final t in axis.ticks) {
      canvas.drawLine(
        Offset(_l, y(t)),
        Offset(size.width - _r, y(t)),
        gridPaint,
      );
      final tp = _tp(shortNum(t));
      tp.paint(canvas, Offset(_l - 6 - tp.width, y(t) - tp.height / 2));
    }
    canvas.drawLine(
      Offset(_l, y(0)),
      Offset(size.width - _r, y(0)),
      Paint()
        ..color = zeroColor.withValues(alpha: 0.55)
        ..strokeWidth = 1.6,
    );

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final cx = centerX(i, size.width);
      final y0 = y(0), y1 = y(p.value);
      final color = metric == StatMetric.profit
          ? (p.value >= 0 ? pos : neg)
          : primary;
      final dim = selected >= 0 && selected != i;
      if (selected == i) {
        canvas.drawRect(
          Rect.fromLTWH(_l + step * i, _t, step, innerH),
          Paint()..color = color.withValues(alpha: 0.08),
        );
      }
      if (p.value != 0) {
        final h = (y0 - y1).abs();
        final rect = Rect.fromLTWH(
          cx - bw / 2,
          y0 < y1 ? y0 : y1,
          bw,
          h < 1 ? 1 : h,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()..color = color.withValues(alpha: dim ? 0.35 : 0.95),
        );
      }
    }

    // X labels: width measured from the real text so they never overlap; first and last are always shown.
    var maxW = 0.0;
    for (final p in points) {
      final w = _tp(p.label).width;
      if (w > maxW) maxW = w;
    }
    final every = labelStep(points.length, size.width - _l - _r, maxW);
    final idx = labelIndices(points.length, every);
    final kept = <(double, TextPainter)>[];
    for (final i in idx) {
      final tp = _tp(points[i].label);
      final dx = (centerX(i, size.width) - tp.width / 2).clamp(
        0.0,
        size.width - tp.width,
      );
      // Clamping the first/last label inside the chart can push it onto its neighbour: drop the neighbour instead of overlapping.
      while (kept.isNotEmpty && kept.last.$1 + kept.last.$2.width + 4 > dx) {
        if (i != idx.last) break;
        kept.removeLast();
      }
      if (kept.isNotEmpty && kept.last.$1 + kept.last.$2.width + 4 > dx) {
        continue;
      }
      kept.add((dx, tp));
    }
    for (final (dx, tp) in kept) {
      tp.paint(canvas, Offset(dx, size.height - _b + 6));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter o) =>
      o.points != points ||
      o.selected != selected ||
      o.metric != metric ||
      o.primary != primary ||
      o.pos != pos ||
      o.neg != neg ||
      o.muted != muted;
}
