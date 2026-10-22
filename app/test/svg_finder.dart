import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/widgets/svg_icon.dart';

/// The icons are SVG now ([SvgIcon]), so tests look for them by [AppSvg] instead of `find.byIcon(Icons.x)`.
Finder bySvg(AppSvg icon) => find.byWidgetPredicate((w) => w is SvgIcon && w.icon == icon, description: 'SvgIcon(${icon.name})');
