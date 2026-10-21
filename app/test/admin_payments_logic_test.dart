import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/admin/payments/payments_logic.dart';

void main() {
  test('filter query matches the web: status always, q/from/to only when set, paging appended', () {
    expect(const PaymentFilter().query(), 'status=all'); // the default is Tất cả
    expect(const PaymentFilter(status: 'pending').query(), 'status=pending');
    const f = PaymentFilter(status: 'approved', q: '  Nguyễn An ', from: '2026-10-01', to: '2026-10-11');
    expect(f.query(limit: 30, offset: 60), 'status=approved&q=Nguy%E1%BB%85n+An&from=2026-10-01&to=2026-10-11&limit=30&offset=60');
    expect(f.hasExtra, isTrue);
    expect(const PaymentFilter(status: 'all').hasExtra, isFalse);
    expect(f.copyWith(status: 'all').status, 'all');
  });

  test('status list: Tất cả is the first entry and the default', () {
    expect(paymentStatusFilters.first, ('all', 'Tất cả'));
    expect(paymentStatusFilters.first.$1, const PaymentFilter().status);
    expect(paymentStatusFilters.map((e) => e.$1).toSet().length, paymentStatusFilters.length);
  });

  test('page parsing is null-safe and paging flags come from the server', () {
    final p = PaymentPage.fromJson({
      'requests': [
        {
          'id': 'a',
          'userName': 'An',
          'username': 'an',
          'packageType': 'p1',
          'amount': 150000,
          'status': 'pending',
          'referenceCode': 'MB1',
          'rejectReason': null,
          'createdAt': '2026-10-11T03:00:00.000Z',
          'decidedAt': null,
        },
        'garbage',
      ],
      'total': 31,
      'hasMore': true,
      'summary': {'pending': 1, 'approvedCount': 4, 'revenueToday': 0, 'revenue7d': 7, 'revenue30d': 30, 'revenueAll': 100},
    });
    expect(p.requests, hasLength(1));
    expect(p.requests.first.pending, isTrue);
    expect(p.total, 31);
    expect(p.hasMore, isTrue);
    expect(p.summary!.revenueAll, 100);
    final empty = PaymentPage.fromJson({});
    expect(empty.requests, isEmpty);
    expect(empty.hasMore, isFalse);
    expect(empty.summary, isNull);
  });

  test('money, dates, csv file name', () {
    expect(formatVnd(1500000), '1.500.000 đ');
    expect(viDateTime(null), '');
    expect(viDateTime('not a date'), 'not a date');
    expect(viDateTime('2026-10-11T03:04:00Z'), matches(RegExp(r'^\d\d/\d\d/2026 \d\d:04$')));
    expect(paymentsCsvName(DateTime(2026, 10, 1)), 'thanh-toan-2026-10-01.csv');
    expect(paymentStatusFilters.map((e) => e.$1), ['all', 'pending', 'approved', 'rejected', 'cancelled']);
  });

  test('renewal parsing', () {
    final r = Renewal.fromJson({'id': 1, 'userName': 'B', 'type': 'renew', 'packageType': 'p', 'amount': '200', 'createdAt': null});
    expect(r.amount, 200);
    expect(renewalTypeLabels[r.type], 'Gia hạn');
  });
}
