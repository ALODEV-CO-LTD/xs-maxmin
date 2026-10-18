// The lottery catalog built into the app (copy of backend/lib/src/lottery_stations.dart): regions, stations (đài), which
// stations draw on which weekday, and each region's prize structure. It is what the app uses until (or without) the server
// answers, so Miền Nam / Miền Trung entries can be typed and scored with no network at all. When the server answers, its
// copy replaces this one (a new station added later), and that answer is kept on the phone too (see LotteryStations).
import 'lottery_stations.dart';

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

const builtInRegions = <Region>[
  Region(
    id: 'mb',
    name: 'Miền Bắc',
    stations: {'mb': 'Miền Bắc'},
    schedule: {
      1: ['mb'],
      2: ['mb'],
      3: ['mb'],
      4: ['mb'],
      5: ['mb'],
      6: ['mb'],
      7: ['mb'],
    },
    structure: _mbStructure,
  ),
  Region(
    id: 'mt',
    name: 'Miền Trung',
    stations: {
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
    schedule: {
      1: ['mt-hue', 'mt-phuyen'],
      2: ['mt-daklak', 'mt-quangnam'],
      3: ['mt-danang', 'mt-khanhhoa'],
      4: ['mt-binhdinh', 'mt-quangtri', 'mt-quangbinh'],
      5: ['mt-gialai', 'mt-ninhthuan'],
      6: ['mt-danang', 'mt-quangngai', 'mt-daknong'],
      7: ['mt-kontum', 'mt-khanhhoa', 'mt-hue'],
    },
    structure: _southCentralStructure,
  ),
  Region(
    id: 'mn',
    name: 'Miền Nam',
    stations: {
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
    schedule: {
      1: ['mn-tphcm', 'mn-dongthap', 'mn-camau'],
      2: ['mn-bentre', 'mn-vungtau', 'mn-baclieu'],
      3: ['mn-dongnai', 'mn-cantho', 'mn-soctrang'],
      4: ['mn-tayninh', 'mn-angiang', 'mn-binhthuan'],
      5: ['mn-vinhlong', 'mn-binhduong', 'mn-travinh'],
      6: ['mn-tphcm', 'mn-longan', 'mn-binhphuoc', 'mn-haugiang'],
      7: ['mn-tiengiang', 'mn-kiengiang', 'mn-dalat'],
    },
    structure: _southCentralStructure,
  ),
];
