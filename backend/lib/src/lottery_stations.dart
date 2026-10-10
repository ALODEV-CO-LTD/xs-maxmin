/// Lottery regions, stations (đài) and prize structure (docs: Nhập kết quả).
///
/// Miền Bắc has ONE draw a day (station 'mb'); Miền Trung ('mt') and Miền Nam ('mn') draw
/// at 2 to 4 provinces a day, which rotate by weekday. An entry's `station` is either a
/// region code ('mt' / 'mn' = every station of that region drawing that day) or one
/// station id ('mn-tphcm'); null/'mb' = Miền Bắc (all entries from before stations existed).
class Region {
  const Region(this.id, this.name, this.stations, this.schedule, this.structure);
  final String id;
  final String name;
  final Map<String, String> stations; // station id -> display name
  final Map<int, List<String>> schedule; // DateTime.weekday (1 = Monday) -> station ids
  final List<Prize> structure;
}

/// One prize group: how many numbers it has and how many digits each number has.
class Prize {
  const Prize(this.tier, this.label, this.count, this.digits);
  final String tier; // dacBiet, giaiNhat, ... giaiTam
  final String label;
  final int count;
  final int digits;
}

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

// Miền Nam / Miền Trung: 18 numbers, 6-digit special prize and an eighth prize (2 digits).
const _southCentralStructure = [
  Prize('dacBiet', 'Đặc biệt', 1, 6),
  Prize('giaiNhat', 'Giải nhất', 1, 5),
  Prize('giaiNhi', 'Giải nhì', 1, 5),
  Prize('giaiBa', 'Giải ba', 2, 5),
  Prize('giaiTu', 'Giải tư', 7, 5),
  Prize('giaiNam', 'Giải năm', 1, 4),
  Prize('giaiSau', 'Giải sáu', 3, 4),
  Prize('giaiBay', 'Giải bảy', 1, 3),
  Prize('giaiTam', 'Giải tám', 1, 2),
];

const regions = <String, Region>{
  'mb': Region('mb', 'Miền Bắc', {'mb': 'Miền Bắc'}, {1: ['mb'], 2: ['mb'], 3: ['mb'], 4: ['mb'], 5: ['mb'], 6: ['mb'], 7: ['mb']}, _mbStructure),
  'mt': Region(
    'mt',
    'Miền Trung',
    {
      'mt-hue': 'Thừa Thiên Huế',
      'mt-phuyen': 'Phú Yên',
      'mt-daklak': 'Đắk Lắk',
      'mt-quangnam': 'Quảng Nam',
      'mt-danang': 'Đà Nẵng',
      'mt-khanhhoa': 'Khánh Hoà',
      'mt-binhdinh': 'Bình Định',
      'mt-quangtri': 'Quảng Trị',
      'mt-quangbinh': 'Quảng Bình',
      'mt-gialai': 'Gia Lai',
      'mt-ninhthuan': 'Ninh Thuận',
      'mt-quangngai': 'Quảng Ngãi',
      'mt-daknong': 'Đắk Nông',
      'mt-kontum': 'Kon Tum',
    },
    {
      1: ['mt-hue', 'mt-phuyen'],
      2: ['mt-daklak', 'mt-quangnam'],
      3: ['mt-danang', 'mt-khanhhoa'],
      4: ['mt-binhdinh', 'mt-quangtri', 'mt-quangbinh'],
      5: ['mt-gialai', 'mt-ninhthuan'],
      6: ['mt-danang', 'mt-quangngai', 'mt-daknong'],
      7: ['mt-kontum', 'mt-khanhhoa', 'mt-hue'],
    },
    _southCentralStructure,
  ),
  'mn': Region(
    'mn',
    'Miền Nam',
    {
      'mn-tphcm': 'TP. Hồ Chí Minh',
      'mn-dongthap': 'Đồng Tháp',
      'mn-camau': 'Cà Mau',
      'mn-bentre': 'Bến Tre',
      'mn-vungtau': 'Vũng Tàu',
      'mn-baclieu': 'Bạc Liêu',
      'mn-dongnai': 'Đồng Nai',
      'mn-cantho': 'Cần Thơ',
      'mn-soctrang': 'Sóc Trăng',
      'mn-tayninh': 'Tây Ninh',
      'mn-angiang': 'An Giang',
      'mn-binhthuan': 'Bình Thuận',
      'mn-vinhlong': 'Vĩnh Long',
      'mn-binhduong': 'Bình Dương',
      'mn-travinh': 'Trà Vinh',
      'mn-longan': 'Long An',
      'mn-binhphuoc': 'Bình Phước',
      'mn-haugiang': 'Hậu Giang',
      'mn-tiengiang': 'Tiền Giang',
      'mn-kiengiang': 'Kiên Giang',
      'mn-dalat': 'Đà Lạt',
    },
    {
      1: ['mn-tphcm', 'mn-dongthap', 'mn-camau'],
      2: ['mn-bentre', 'mn-vungtau', 'mn-baclieu'],
      3: ['mn-dongnai', 'mn-cantho', 'mn-soctrang'],
      4: ['mn-tayninh', 'mn-angiang', 'mn-binhthuan'],
      5: ['mn-vinhlong', 'mn-binhduong', 'mn-travinh'],
      6: ['mn-tphcm', 'mn-longan', 'mn-binhphuoc', 'mn-haugiang'],
      7: ['mn-tiengiang', 'mn-kiengiang', 'mn-dalat'],
    },
    _southCentralStructure,
  ),
};

/// The region a station id (or region code) belongs to; null if unknown.
Region? regionOf(String code) {
  if (regions.containsKey(code)) return regions[code];
  for (final r in regions.values) {
    if (r.stations.containsKey(code)) return r;
  }
  return null;
}

/// Stations of [regionId] that draw on [date] (weekday schedule).
List<String> stationsOn(String regionId, DateTime date) => regions[regionId]?.schedule[date.weekday] ?? const [];

/// A station id a RESULT can be stored for (not a bare region code except 'mb').
bool isResultStation(String code) => code == 'mb' || (!regions.containsKey(code) && regionOf(code) != null);

/// A value an entry's `station` may hold: 'mb', a region code or a station id.
bool isEntryStation(String code) => regionOf(code) != null;
