import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/payments.dart';
import 'package:sqlite3/sqlite3.dart';

import 'index.dart' show filterPaymentRequests;

/// CSV (UTF-8 with BOM so Excel reads Vietnamese) of the same filters as the
/// list - `GET /api/admin/payment-requests/export?status=approved&from=...`.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role != 'admin') return forbidden();

  final rows = filterPaymentRequests(context.read<Database>(), context.request.uri.queryParameters);
  String cell(Object? v) {
    var t = '${v ?? ''}';
    // spreadsheet formula injection guard
    if (t.isNotEmpty && '=+-@'.contains(t[0])) t = "'$t";
    return '"${t.replaceAll('"', '""')}"';
  }

  final b = StringBuffer('\u{FEFF}Mã tham chiếu,Khách hàng,Tài khoản,Gói,Số tiền,Trạng thái,Lý do,Ngày tạo,Ngày xử lý\r\n');
  for (final r in rows) {
    final j = paymentJson(r, withUser: true);
    b.write([
      j['referenceCode'], j['userName'], j['username'], j['packageType'], j['amount'],
      j['status'], j['rejectReason'], j['createdAt'], j['decidedAt'],
    ].map(cell).join(','));
    b.write('\r\n');
  }
  return Response(
    body: b.toString(),
    headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': 'attachment; filename="thanh-toan.csv"',
    },
  );
}
