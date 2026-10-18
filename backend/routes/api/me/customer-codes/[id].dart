import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/customer_codes.dart';
import 'package:sqlite3/sqlite3.dart';

/// DELETE removes one of the caller's Mã ID; PATCH `{label}` renames its label
/// (empty clears it).
Future<Response> onRequest(RequestContext context, String id) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final db = context.read<Database>();

  switch (context.request.method) {
    case HttpMethod.delete:
      final mine = db.select('SELECT code FROM customer_codes WHERE id = ? AND user_id = ?', [id, auth.userId]);
      if (mine.isEmpty) return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy mã ID'});
      // Quarantine the number (90 days) before freeing it, so it cannot be re-registered by someone else.
      retireCode(db, mine.first['code'] as String, auth.userId);
      db.execute('DELETE FROM customer_codes WHERE id = ? AND user_id = ?', [id, auth.userId]);
      return Response.json(body: {'ok': true});
    case HttpMethod.patch:
      final read = await readJsonBody(context, smallBodyMaxBytes);
      if (read.error != null) return read.error!;
      final body = read.body!;
      final rawLabel = body['label'];
      if (rawLabel != null && rawLabel is! String) {
        return Response.json(statusCode: 400, body: {'error': 'Nhãn phải là chuỗi'});
      }
      final label = (rawLabel as String?)?.trim() ?? '';
      if (label.length > 40) {
        return Response.json(statusCode: 400, body: {'error': 'Nhãn tối đa 40 ký tự'});
      }
      db.execute(
        'UPDATE customer_codes SET label = ? WHERE id = ? AND user_id = ?',
        [label.isEmpty ? null : label, id, auth.userId],
      );
      if (db.updatedRows == 0) return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy mã ID'});
      return Response.json(body: {'ok': true, 'label': label.isEmpty ? null : label});
    default:
      return Response(statusCode: 405, body: 'Method not allowed');
  }
}
