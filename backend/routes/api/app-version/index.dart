import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/app_version.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET /api/app-version` (public, no login: the app asks before the user signs in)
/// -> `{latestVersion, minVersion, downloadUrl, notes}` (empty strings = not set). Set by the Admin in Cài đặt.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  return Response.json(body: loadAppVersion(context.read<Database>()).toJson());
}
