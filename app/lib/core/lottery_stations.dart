import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// One prize group of a region: how many numbers it has and how many digits each number has.
class Prize {
  const Prize(this.tier, this.label, this.count, this.digits);
  final String tier;
  final String label;
  final int count;
  final int digits;
}

class Region {
  const Region({required this.id, required this.name, required this.stations, required this.schedule, required this.structure});
  final String id;
  final String name;
  final Map<String, String> stations; // station id -> name
  final Map<int, List<String>> schedule; // weekday 1 (Mon) .. 7 (Sun) -> station ids
  final List<Prize> structure;

  factory Region.fromJson(Map<String, dynamic> j) => Region(
        id: j['id'] as String,
        name: j['name'] as String,
        stations: {for (final e in (j['stations'] as Map).entries) e.key as String: e.value as String},
        schedule: {
          for (final e in ((j['schedule'] ?? const {}) as Map).entries) int.parse('${e.key}'): [for (final s in e.value as List) s as String],
        },
        structure: [
          for (final p in (j['structure'] as List))
            Prize(p['tier'] as String, p['label'] as String, (p['count'] as num).toInt(), (p['digits'] as num).toInt()),
        ],
      );
}

/// Built-in Miền Bắc so everything works before (or without) the catalog.
const _mbFallback = Region(
  id: 'mb',
  name: 'Miền Bắc',
  stations: {'mb': 'Miền Bắc'},
  schedule: {1: ['mb'], 2: ['mb'], 3: ['mb'], 4: ['mb'], 5: ['mb'], 6: ['mb'], 7: ['mb']},
  structure: [
    Prize('dacBiet', 'Đặc biệt', 1, 5),
    Prize('giaiNhat', 'Giải nhất', 1, 5),
    Prize('giaiNhi', 'Giải nhì', 2, 5),
    Prize('giaiBa', 'Giải ba', 6, 5),
    Prize('giaiTu', 'Giải tư', 4, 4),
    Prize('giaiNam', 'Giải năm', 6, 4),
    Prize('giaiSau', 'Giải sáu', 3, 3),
    Prize('giaiBay', 'Giải bảy', 4, 2),
  ],
);

const regionIds = ['mb', 'mt', 'mn'];

/// Regions and stations (đài), loaded once from `GET /lottery-stations` (backend/lib/src/lottery_stations.dart is the
/// source of truth). An entry's `station` is 'mb' (or empty), a region code ('mt'/'mn' = every station of that region
/// drawing that day) or one station id ('mn-tphcm').
class LotteryStations extends ChangeNotifier {
  List<Region> regions = [];
  bool loaded = false;
  Future<void>? _loading;

  Future<void> load(ApiClient api) {
    if (loaded) return Future.value();
    return _loading ??= api.get('/lottery-stations').then((res) {
      regions = [for (final r in (res['regions'] as List)) Region.fromJson(Map<String, dynamic>.from(r as Map))];
      loaded = true;
      notifyListeners();
    }).catchError((_) {/* offline: Miền Bắc keeps working */}).whenComplete(() => _loading = null);
  }

  List<Region> get regionList => regions.isEmpty ? [_mbFallback] : regions;

  /// Region for a region code or a station id; Miền Bắc when empty or unknown.
  Region regionOf(String? code) {
    final list = regionList;
    final mb = list.firstWhere((r) => r.id == 'mb', orElse: () => _mbFallback);
    if (code == null || code.isEmpty) return mb;
    return list.firstWhere((r) => r.id == code || r.stations.containsKey(code), orElse: () => mb);
  }

  bool isRegionCode(String? code) => code != null && regionIds.contains(code);

  /// ISO date (YYYY-MM-DD) -> weekday 1 (Monday) .. 7 (Sunday), computed in UTC so the time zone never shifts the day.
  static int weekdayOf(String iso) => DateTime.parse('${iso.substring(0, 10)}T00:00:00Z').weekday;

  /// Stations of [regionId] drawing on [iso].
  List<String> stationsOn(String regionId, String iso) {
    final r = regionOf(regionId);
    return r.schedule[weekdayOf(iso)] ?? (r.id == 'mb' ? const ['mb'] : const []);
  }

  /// The concrete stations an entry counts for on its date.
  List<String> entryStations(String? station, String entryDate) {
    if (station == null || station.isEmpty || station == 'mb') return const ['mb'];
    if (isRegionCode(station)) return stationsOn(station, entryDate);
    return [station];
  }

  String stationName(String id) {
    for (final r in regionList) {
      final n = r.stations[id];
      if (n != null) return n;
    }
    return id;
  }

  String stationLabel(String? code) {
    if (code == null || code.isEmpty || code == 'mb') return 'Miền Bắc';
    if (isRegionCode(code)) return '${regionOf(code).name} (tất cả đài trong ngày)';
    return '${stationName(code)} (${regionOf(code).name})';
  }

  /// Options for an "Đài" picker on [iso]: Miền Bắc, each region as "all stations drawing that day", and that day's stations.
  List<({String value, String label})> stationOptions(String iso) {
    final out = <({String value, String label})>[(value: 'mb', label: 'Miền Bắc')];
    for (final r in regionList) {
      if (r.id == 'mb') continue;
      final today = stationsOn(r.id, iso);
      out.add((value: r.id, label: '${r.name}${today.isEmpty ? '' : ' (${today.length} đài: ${today.map(stationName).join(', ')})'}'));
      for (final s in today) {
        out.add((value: s, label: '   ${stationName(s)} (${r.name})'));
      }
    }
    return out;
  }

  /// Every station, for choosing a customer's default (not tied to a day).
  List<({String value, String label})> allStationOptions() {
    final out = <({String value, String label})>[(value: 'mb', label: 'Miền Bắc')];
    for (final r in regionList) {
      if (r.id == 'mb') continue;
      out.add((value: r.id, label: '${r.name} (tất cả đài trong ngày)'));
      for (final e in r.stations.entries) {
        out.add((value: e.key, label: '   ${e.value} (${r.name})'));
      }
    }
    return out;
  }
}
