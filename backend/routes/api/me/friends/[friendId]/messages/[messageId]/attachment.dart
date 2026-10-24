import 'package:dart_frog/dart_frog.dart';

/// Retired: friend chat is end-to-end encrypted and relayed over the WebSocket
/// without being stored (docs/MA_HOA_2_DAU.md). Nothing is kept on the server.
Response onRequest(RequestContext context, String friendId, String messageId) => Response.json(
      statusCode: 410,
      body: {'error': 'Tin nhắn bạn bè nay được mã hoá đầu cuối và không lưu trên máy chủ. Hãy cập nhật ứng dụng.'},
    );
