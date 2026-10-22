import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The icons the owner supplied as SVG files (assets/icons/*.svg). One colour each; [SvgIcon] paints them in the colour of the
/// surrounding [IconTheme] (so they follow buttons, the navigation bar, selected / disabled states) or in an explicit colour.
enum AppSvg {
  /// Tổng quan
  chart('chart'),

  /// Tính toán
  calculator('calculator'),

  /// Bạn bè
  friends('friends'),

  /// Cấu hình (sliders)
  config('config'),

  /// Tài khoản
  account('account'),

  /// Gọi (in Bạn bè)
  call('call'),

  /// Sửa
  edit('edit'),
  logout('logout'),
  delete('delete'),
  copy('copy'),

  /// Làm mới / tính lại / kiểm tra cập nhật
  refresh('refresh'),

  /// Cài đặt (bánh răng)
  gear('gear'),

  /// Thiết bị / phiên bản ứng dụng
  device('device'),

  /// Nhắn tin tới Admin (hỗ trợ)
  support('support'),

  /// Lịch / chọn ngày
  calendar('calendar'),

  /// Chụp ảnh
  camera('camera'),

  /// Chỉnh sửa nội dung (nút chỉ có icon)
  editText('edit_text'),

  /// Thêm / chọn ảnh
  photoAdd('photo_add'),

  /// Thêm người (khách hàng, bạn bè)
  addUser('add_user');

  const AppSvg(this.name);
  final String name;
  String get asset => 'assets/icons/$name.svg';
}

class SvgIcon extends StatelessWidget {
  const SvgIcon(this.icon, {super.key, this.size, this.color});
  final AppSvg icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    final c = (color ?? theme.color ?? Colors.black).withValues(alpha: theme.opacity ?? 1);
    return SvgPicture.asset(icon.asset, width: s, height: s, colorFilter: ColorFilter.mode(c, BlendMode.srcIn), excludeFromSemantics: true);
  }
}
