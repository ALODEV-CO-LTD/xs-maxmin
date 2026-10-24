import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/widgets/svg_icon.dart';

void main() {
  testWidgets('an icon in a TextField prefix/suffix keeps its own size (the slot forces 48x48)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: const [
          TextField(decoration: InputDecoration(prefixIcon: SvgIcon(AppSvg.search, size: 14), suffixIcon: SvgIcon(AppSvg.calendar, size: 14))),
          TextField(decoration: InputDecoration(suffixIcon: SvgIcon(AppSvg.clock, size: 14))),
        ]),
      ),
    ));
    final pics = tester.widgetList<SvgPicture>(find.byType(SvgPicture)).toList();
    expect(pics, hasLength(3));
    for (final e in find.byType(SvgPicture).evaluate()) {
      final box = e.renderObject! as RenderBox;
      expect(box.size.width, 14, reason: 'icon must not be stretched to the 48x48 slot');
      expect(box.size.height, 14);
    }
  });
}
