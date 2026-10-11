import 'package:mamba_app/core/lottery_stations.dart';

const _mbStructure = [
  Prize('dacBiet', 'Đặc biệt', 1, 5),
  Prize('giaiNhat', 'Giải nhất', 1, 5),
  Prize('giaiNhi', 'Giải nhì', 2, 5),
  Prize('giaiBa', 'Giải ba', 6, 5),
  Prize('giaiTu', 'Giải tư', 4, 4),
  Prize('giaiNam', 'Giải năm', 6, 4),
  Prize('giaiSau', 'Giải sáu', 3, 3),
  Prize('giaiBay', 'Giải bảy', 4, 2),
];

const _scStructure = [
  Prize('dacBiet', 'Đặc biệt', 1, 6),
  Prize('giaiNhat', 'Giải nhất', 1, 5),
  Prize('giaiNhi', 'Giải nhì', 1, 5),
  Prize('giaiBa', 'Giải ba', 2, 5),
  Prize('giaiTu', 'Giải tư', 7, 5),
  Prize('giaiNam', 'Giải năm', 1, 4),
  Prize('giaiSau', 'Giải sáu', 3, 4),
  Prize('giaiBay', 'Giải bảy', 1, 3),
  Prize('giaiTam', 'Giải tám (MN, MT)', 1, 2),
];

Map<int, List<String>> _everyDay(List<String> s) => {for (var d = 1; d <= 7; d++) d: s};

/// A catalog like the backend's, but the same stations every day (so tests do not depend on the weekday).
LotteryStations testStations() {
  final s = LotteryStations();
  s.regions = [
    Region(id: 'mb', name: 'Miền Bắc', stations: const {'mb': 'Miền Bắc'}, schedule: _everyDay(const ['mb']), structure: _mbStructure),
    Region(
      id: 'mt',
      name: 'Miền Trung',
      stations: const {'mt-hue': 'Thừa Thiên Huế', 'mt-phuyen': 'Phú Yên'},
      schedule: _everyDay(const ['mt-hue', 'mt-phuyen']),
      structure: _scStructure,
    ),
    Region(
      id: 'mn',
      name: 'Miền Nam',
      stations: const {'mn-dongnai': 'Đồng Nai', 'mn-cantho': 'Cần Thơ', 'mn-soctrang': 'Sóc Trăng', 'mn-tphcm': 'TP. Hồ Chí Minh'},
      schedule: _everyDay(const ['mn-dongnai', 'mn-cantho', 'mn-soctrang']),
      structure: _scStructure,
    ),
  ];
  s.loaded = true;
  return s;
}

const allBaseTiers = ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay'];
