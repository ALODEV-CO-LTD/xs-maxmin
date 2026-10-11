import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import 'admin_stats_logic.dart';

class ChartPoint {
  const ChartPoint(this.date, this.value);
  final String date;
  final num value;
}

/// One time-series chart (bars or line) drawn with CustomPaint; tap/drag to read a bucket.
class AdminSeriesChart extends StatefulWidget {
  const AdminSeriesChart({super.key, required this.points, required this.line, required this.color, required this.label, this.money = false});
  final List<ChartPoint> points;
  final bool line, money;
  final Color color;
  final String label;
  @override
  State<AdminSeriesChart> createState() => _AdminSeriesChartState();
}

class _AdminSeriesChartState extends State<AdminSeriesChart> {
  int _sel = -1;

  String _full(num v) => widget.money ? '${formatNumber(v)} đ' : '$v';

  @override
  Widget build(BuildContext context) {
    final total = widget.points.fold<num>(0, (a, p) => a + p.value);
    final sel = _sel >= 0 && _sel < widget.points.length ? widget.points[_sel] : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(widget.line ? 5 : 2))),
            const SizedBox(width: 6),
            Expanded(child: Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(_full(total), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          SizedBox(
            height: 18,
            child: Text(sel == null ? 'Chạm vào biểu đồ để xem từng mốc' : '${longDate(sel.date)}: ${_full(sel.value)}', style: TextStyle(fontSize: 12, color: context.mutedColor)),
          ),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (context, c) {
            final painter = _Painter(widget.points, widget.line, widget.money, widget.color, context.mutedColor, Theme.of(context).colorScheme.outlineVariant, _sel);
            void pick(Offset o) {
              final i = painter.indexAt(o.dx, c.maxWidth);
              if (i != _sel) setState(() => _sel = i ?? -1);
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => pick(d.localPosition),
              onHorizontalDragUpdate: (d) => pick(d.localPosition),
              child: CustomPaint(size: Size(c.maxWidth, 190), painter: painter),
            );
          }),
        ]),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.points, this.line, this.money, this.color, this.muted, this.grid, this.sel);
  final List<ChartPoint> points;
  final bool line, money;
  final Color color, muted, grid;
  final int sel;

  double get _l => money ? 44 : 28;
  static const _r = 8.0, _t = 8.0, _b = 22.0;

  int? indexAt(double x, double width) {
    if (points.isEmpty) return null;
    final step = (width - _l - _r) / points.length;
    final i = ((x - _l) / step).floor();
    return i < 0 || i >= points.length ? null : i;
  }

  void _text(Canvas canvas, String s, Offset at, {bool right = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(fontSize: 9.5, color: muted)), textDirection: TextDirection.ltr)..layout();
    canvas.save();
    tp.paint(canvas, Offset(right ? at.dx - tp.width : at.dx - tp.width / 2, at.dy - tp.height / 2));
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final raw = points.fold<double>(0, (a, p) => p.value > a ? p.value.toDouble() : a);
    final maxV = money ? niceMax(raw) : (niceMax(raw) < 4 ? 4.0 : niceMax(raw));
    final innerH = size.height - _t - _b, innerW = size.width - _l - _r;
    double y(num v) => _t + innerH - (v / maxV) * innerH;
    final step = innerW / points.length;
    double x(int i) => _l + step * (i + 0.5);

    final gp = Paint()..color = grid.withValues(alpha: 0.7)..strokeWidth = 1;
    for (var t = 0; t <= 4; t++) {
      final v = maxV / 4 * t;
      canvas.drawLine(Offset(_l, y(v)), Offset(size.width - _r, y(v)), gp);
      _text(canvas, shortAxis(v, money: money), Offset(_l - 5, y(v)), right: true);
    }

    final dim = sel >= 0;
    if (!line) {
      final bw = (step * 0.6).clamp(2.0, 24.0);
      for (var i = 0; i < points.length; i++) {
        final h = (y(0) - y(points[i].value));
        final rect = Rect.fromLTWH(x(i) - bw / 2, y(points[i].value), bw, h < 0 ? 0 : h);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), Paint()..color = color.withValues(alpha: dim && sel != i ? 0.35 : 0.9));
      }
    } else {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final o = Offset(x(i), y(points[i].value));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);
      for (var i = 0; i < points.length; i++) {
        if (points.length <= 40 || i == sel) canvas.drawCircle(Offset(x(i), y(points[i].value)), i == sel ? 5 : 3, Paint()..color = color);
      }
    }

    // X labels: keep ~ one per 52px so they never overlap on a small phone.
    final every = (points.length / (innerW / 52).floor().clamp(3, 12)).ceil();
    for (var i = 0; i < points.length; i++) {
      if ((points.length - 1 - i) % every == 0) _text(canvas, shortDate(points[i].date), Offset(x(i), size.height - 8));
    }
  }

  @override
  bool shouldRepaint(_Painter o) => o.points != points || o.sel != sel || o.color != color || o.muted != muted || o.line != line;
}
