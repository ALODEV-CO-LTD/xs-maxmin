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
  addUser('add_user'),

  /// Quản trị viên (Phân quyền)
  userAdmin('user_admin'),

  /// Đặt mật khẩu xoá dữ liệu
  newPassword('new_password'),

  /// Mật khẩu lớp hai
  loginLockRefresh('login_lock_refresh'),

  /// Thông báo & bảo trì
  megaphone('megaphone'),

  /// Thanh toán & gia hạn
  pay('pay'),

  /// Hiện mật khẩu / số liệu
  eye('eye'),

  /// Ẩn mật khẩu / số liệu
  eyeClosed('eye_closed'),

  /// Đổi mật khẩu
  changePassword('change_password'),

  /// Phản hồi (Admin)
  feedback('feedback'),

  /// Nhóm người / khách hàng
  usersGroup('users_group'),

  // ---- Lucide set (ISC licence, assets/icons/LICENSE-lucide.txt) + SVG Repo arrows: the small interface icons ----
  warning('triangle_alert'),
  search('search'),
  volumeOn('volume_on'),
  arrowDown('arrow_down'),
  circle('circle'),
  download('download'),
  tag('tag'),
  alertCircle('circle_alert'),
  chevronDown('chevron_down'),
  chevronUp('chevron_up'),
  close('close'),
  lock('lock'),
  backCircle('back_circle'),
  archive('archive'),
  checkboxOn('checkbox_on'),
  checkCircle('check_circle'),
  bell('bell'),
  qr('qr'),
  check('check'),
  chevronRight('chevron_right'),
  info('info'),
  arrowUp('arrow_up'),
  mic('mic'),
  chevronLeft('chevron_left'),
  badge('badge'),
  attach('attach'),
  checkboxOff('checkbox_off'),
  sync('sync'),
  send('send'),
  verified('verified'),
  clock('clock'),
  phone('phone'),
  phoneOff('phone_off'),
  plus('plus'),
  closeCircle('close_circle'),
  micOff('mic_off'),
  bellOff('bell_off'),
  userRemove('user_remove'),
  arrowLeft('arrow_left'),
  volumeOff('volume_off'),
  bookmark('bookmark');

  const AppSvg(this.name);
  final String name;
  String get asset => 'assets/icons/$name.svg';
}

/// Bộ icon có độ phủ khung khác nhau (có icon tràn sát mép, có icon chỉ chiếm nửa khung);
/// hệ số này đưa nét vẽ thật về cùng ~86% khung để các icon trông đều nhau.
const _glyphScale = <String, double>{
  'add_user': 0.86,
  'arrow_left': 1.25,
  'back_circle': 0.86,
  'change_password': 0.86,
  'check': 1.13,
  'close': 1.25,
  'config': 1.13,
  'copy': 1.25,
  'device': 0.86,
  'edit': 1.13,
  'login_lock_refresh': 0.86,
  'new_password': 0.86,
  'plus': 1.25,
  'refresh': 0.86,
  'search': 1.08, 'badge': 1.1, 'clock': 0.88,
  'support': 0.86,
  'sync': 1.25,
  'user_admin': 0.86,
  'users_group': 0.88,
};

class SvgIcon extends StatelessWidget {
  const SvgIcon(this.icon, {super.key, this.size, this.color});
  final AppSvg icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    final c = (color ?? theme.color ?? Colors.black).withValues(
      alpha: theme.opacity ?? 1,
    );
    final pic = SvgPicture.asset(
      icon.asset,
      width: s,
      height: s,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
    final k = _glyphScale[icon.name];
    return k == null
        ? pic
        : SizedBox(
            width: s,
            height: s,
            child: Transform.scale(scale: k, child: pic),
          );
  }
}
