import '../../../core/format.dart';

/// Pure logic of "Thanh toán & gia hạn" (frontend/src/views/admin/PaymentRequestsView.vue, RenewalsView.vue).

const kPaymentPageSize = 30;

/// Status filter, in the order of the web dropdown: key -> label.
const paymentStatusFilters = <(String, String)>[('pending', 'Chờ duyệt'), ('approved', 'Đã duyệt'), ('rejected', 'Đã từ chối'), ('cancelled', 'Đã huỷ'), ('all', 'Tất cả')];

const paymentStatusLabels = {'pending': 'Chờ duyệt', 'approved': 'Đã duyệt', 'rejected': 'Đã từ chối', 'cancelled': 'Người dùng huỷ'};

const rejectReasonPresets = ['Chưa nhận được tiền', 'Số tiền không khớp', 'Sai nội dung chuyển khoản', 'Yêu cầu trùng'];

const renewalTypeLabels = {'purchase': 'Mua mới', 'renew': 'Gia hạn'};

String formatVnd(num v) => '${formatNumber(v)} đ';

/// "2026-10-11T03:04:05.000Z" -> "11/10/2026 10:04" (local time); unparsable input comes back unchanged.
String viDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final l = d.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(l.day)}/${p(l.month)}/${l.year} ${p(l.hour)}:${p(l.minute)}';
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class PaymentRequest {
  const PaymentRequest({
    required this.id,
    required this.userName,
    required this.username,
    required this.packageType,
    required this.amount,
    required this.status,
    required this.referenceCode,
    this.rejectReason,
    this.createdAt,
    this.decidedAt,
  });

  final String id;
  final String userName;
  final String username;
  final String packageType;
  final int amount;
  final String status;
  final String referenceCode;
  final String? rejectReason;
  final String? createdAt;
  final String? decidedAt;

  bool get pending => status == 'pending';

  factory PaymentRequest.fromJson(Map<String, dynamic> j) => PaymentRequest(
    id: '${j['id'] ?? ''}',
    userName: '${j['userName'] ?? ''}',
    username: '${j['username'] ?? ''}',
    packageType: '${j['packageType'] ?? ''}',
    amount: _int(j['amount']),
    status: '${j['status'] ?? ''}',
    referenceCode: '${j['referenceCode'] ?? ''}',
    rejectReason: j['rejectReason'] as String?,
    createdAt: j['createdAt'] as String?,
    decidedAt: j['decidedAt'] as String?,
  );
}

class PaymentSummary {
  const PaymentSummary({this.pending = 0, this.approvedCount = 0, this.revenueToday = 0, this.revenue7d = 0, this.revenue30d = 0, this.revenueAll = 0});
  final int pending, approvedCount, revenueToday, revenue7d, revenue30d, revenueAll;

  factory PaymentSummary.fromJson(Map<String, dynamic> j) => PaymentSummary(
    pending: _int(j['pending']),
    approvedCount: _int(j['approvedCount']),
    revenueToday: _int(j['revenueToday']),
    revenue7d: _int(j['revenue7d']),
    revenue30d: _int(j['revenue30d']),
    revenueAll: _int(j['revenueAll']),
  );
}

/// One answer of `GET /admin/payment-requests`.
class PaymentPage {
  const PaymentPage({required this.requests, required this.total, required this.hasMore, this.summary});
  final List<PaymentRequest> requests;
  final int total;
  final bool hasMore;
  final PaymentSummary? summary;

  factory PaymentPage.fromJson(Map<String, dynamic> j) => PaymentPage(
    requests: [
      for (final r in (j['requests'] as List? ?? const []))
        if (r is Map<String, dynamic>) PaymentRequest.fromJson(r),
    ],
    total: _int(j['total']),
    hasMore: j['hasMore'] == true,
    summary: j['summary'] is Map<String, dynamic> ? PaymentSummary.fromJson(j['summary'] as Map<String, dynamic>) : null,
  );
}

/// Filters of the list; also the query of the CSV export.
class PaymentFilter {
  const PaymentFilter({this.status = 'pending', this.q = '', this.from = '', this.to = ''});
  final String status;
  final String q;
  final String from;
  final String to;

  bool get hasExtra => q.trim().isNotEmpty || from.isNotEmpty || to.isNotEmpty;

  PaymentFilter copyWith({String? status, String? q, String? from, String? to}) => PaymentFilter(status: status ?? this.status, q: q ?? this.q, from: from ?? this.from, to: to ?? this.to);

  /// Same parameters as the web `query()` (status, q, from, to) plus optional paging.
  String query({int? limit, int? offset}) {
    final p = <String, String>{'status': status};
    if (q.trim().isNotEmpty) p['q'] = q.trim();
    if (from.isNotEmpty) p['from'] = from;
    if (to.isNotEmpty) p['to'] = to;
    if (limit != null) p['limit'] = '$limit';
    if (offset != null) p['offset'] = '$offset';
    return p.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
  }
}

/// "thanh-toan-2026-10-11.csv"
String paymentsCsvName(DateTime now) => 'thanh-toan-${isoOf(now)}.csv';

class Renewal {
  const Renewal({required this.id, required this.userName, required this.type, required this.packageType, required this.amount, this.createdAt});
  final String id, userName, type, packageType;
  final int amount;
  final String? createdAt;

  factory Renewal.fromJson(Map<String, dynamic> j) => Renewal(
    id: '${j['id'] ?? ''}',
    userName: '${j['userName'] ?? ''}',
    type: '${j['type'] ?? ''}',
    packageType: '${j['packageType'] ?? ''}',
    amount: _int(j['amount']),
    createdAt: j['createdAt'] as String?,
  );
}
