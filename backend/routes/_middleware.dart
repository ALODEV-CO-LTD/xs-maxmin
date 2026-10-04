import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';

Handler middleware(Handler handler) {
  return handler
      .use(provider<Database>((_) => appDatabase))
      .use(authProvider);
}
