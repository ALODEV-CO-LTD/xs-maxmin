import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/lottery_stations.dart';

/// The lottery regions and stations (đài), and which stations draw on a day.
/// `GET ?date=YYYY-MM-DD` -> `{regions: [{id, name, stations: {id: name}, today: [ids drawing that
/// day], structure: [{tier, label, count, digits}]}]}`. `today` is empty without `date`; `schedule` maps weekday 1-7 to the station ids.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  if (requireAuth(context) == null) return unauthorized();
  final raw = context.request.uri.queryParameters['date'];
  final date = raw == null ? null : DateTime.tryParse(raw);
  return Response.json(body: {
    'regions': [
      for (final r in regions.values)
        {
          'id': r.id,
          'name': r.name,
          'stations': r.stations,
          'today': date == null ? const <String>[] : stationsOn(r.id, date),
          // weekday (1 = Monday ... 7 = Sunday) -> station ids drawing that day
          'schedule': {for (final e in r.schedule.entries) '${e.key}': e.value},
          'structure': [
            for (final p in r.structure) {'tier': p.tier, 'label': p.label, 'count': p.count, 'digits': p.digits},
          ],
        },
    ],
  });
}
