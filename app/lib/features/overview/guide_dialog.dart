import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/svg_icon.dart';

/// Hướng dẫn nhanh: what each tab of the app is for and the usual order of work (opened from the Tổng quan top-left button).
Future<void> showGuideDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _GuideDialog());

const guideSections = <(AppSvg, String, String)>[
  (AppSvg.chart, 'Tổng quan', 'Xem gói đang dùng và số liệu theo kỳ: chọn Tiền gửi, Tiền trúng hoặc Lợi nhuận, rồi Ngày, Tuần, Tháng, Năm. Số lớn là kỳ hiện tại (hôm nay, tuần này, tháng này, năm nay), dòng nhỏ so với kỳ liền trước. Cuối trang là số liệu toàn bộ và nút xoá dữ liệu.'),
  (AppSvg.calculator, 'Tính toán', 'Gồm 4 tab theo thứ tự làm việc: Nhập số, Kết quả, Tính điểm, Khách hàng.'),
  (AppSvg.edit, '1. Nhập số', 'Chọn khách và ngày, nhập từng dòng (hạng mục, số, điểm vào) hoặc dán tin nhắn / chụp ảnh để app đọc sẵn rồi kiểm tra lại trước khi lưu.'),
  (AppSvg.check, '2. Kết quả', 'Nhập kết quả xổ số các miền rồi bấm "Lưu kết quả". Điểm ra của khách hàng sẽ tự được tính ở màn hình Tính điểm.'),
  (AppSvg.calculator, '3. Tính điểm', 'Xem điểm ra, tiền vào / ra và lợi nhuận theo từng khách và từng ngày. Ngày nào chưa có kết quả xổ số thì chưa tính lợi nhuận.'),
  (AppSvg.usersGroup, '4. Khách hàng', 'Thêm khách, chỉnh bảng giá và tỉ lệ ăn riêng cho từng khách, lọc và sắp xếp danh sách, xem tiền vào / ra / lợi nhuận mỗi khách.'),
  (AppSvg.friends, 'Nhắn tin', 'Nhập ID bạn bè để kết bạn. Tin nhắn mã hoá đầu cuối, không lưu trên máy chủ; có gọi thoại và đặt tin tự xoá trong từng cuộc trò chuyện.'),
  (AppSvg.config, 'Cấu hình', 'Cấu hình tính điểm mặc định cho khách mới. Khách nào cần khác thì chỉnh riêng ở tab Khách hàng.'),
  (AppSvg.account, 'Tài khoản', 'Thông tin cá nhân, mật khẩu, gói sử dụng và gia hạn, thiết bị đăng nhập, lịch xoá dữ liệu tự động.'),
  (AppSvg.support, 'Liên hệ Admin', 'Biểu tượng màu đỏ ở góc trên bên phải: gửi câu hỏi hoặc báo lỗi cho Admin, số đỏ là trả lời chưa đọc.'),
];

class _GuideDialog extends StatelessWidget {
  const _GuideDialog();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      title: 'Hướng dẫn sử dụng',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (icon, title, text) in guideSections)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: SvgIcon(icon, size: 18, color: theme.colorScheme.primary)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(text, style: TextStyle(fontSize: 13.5, color: context.mutedColor, height: 1.35)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}
