#!/usr/bin/env python3
"""Demo data for the admin charts (Thống kê, Thanh toán & gia hạn) on a LOCAL database.

  python3 tools/seed_demo.py [--db backend/data/xoso.db] [--users 80] [--seed 1]
  python3 tools/seed_demo.py --remove      # delete everything this script added

Adds accounts `demo001`.. (name "Khách demo N", password hash that matches nothing, so
they cannot log in) with a purchase + some renewals + matching approved payment
requests spread over the last 12 months. Re-running replaces the previous demo data.
Never run it against a database with real customers you care about without a backup.
"""
import argparse, random, shutil, sqlite3, uuid
from datetime import datetime, timedelta, timezone

ap = argparse.ArgumentParser()
ap.add_argument('--db', default='backend/data/xoso.db')
ap.add_argument('--users', type=int, default=80)
ap.add_argument('--seed', type=int, default=1)
ap.add_argument('--remove', action='store_true')
a = ap.parse_args()

now = datetime.now(timezone.utc)
iso = lambda d: d.strftime('%Y-%m-%dT%H:%M:%S.000000Z')
db = sqlite3.connect(a.db)
db.execute('PRAGMA foreign_keys = ON')

stamp = now.strftime('%Y%m%d-%H%M%S')
shutil.copy(a.db, f'{a.db}.before-demo-{stamp}')

# Remove previous demo data (transactions / payment_requests cascade with the user).
db.execute("DELETE FROM users WHERE username LIKE 'demo%' AND role = 'user'")
if a.remove:
    db.commit()
    print('Đã xoá dữ liệu demo.')
    raise SystemExit

random.seed(a.seed)
pk = db.execute("SELECT code, duration_days, price_vnd FROM packages WHERE active = 1").fetchall()
assert pk, 'bảng packages trống'
weights = [4 if p[0] == '1m' else 3 if p[0] == '3m' else 2 if p[0] == '6m' else 1 for p in pk]

n_tx = 0
for i in range(1, a.users + 1):
    # Sign-ups skew recent (growth): days_ago ~ 365 * u^1.6
    days_ago = int(365 * random.random() ** 1.6)
    created = now - timedelta(days=days_ago, hours=random.randint(0, 23), minutes=random.randint(0, 59))
    uid = str(uuid.uuid4())
    events, t, last = [], created + timedelta(hours=random.randint(1, 48)), None
    while t < now and len(events) < 6:
        code, days, price = random.choices(pk, weights)[0]
        events.append((t, code, days, price))
        t = t + timedelta(days=days - random.randint(0, 5))
        if random.random() < 0.45:
            break
    pkg_code, pkg_days, _ = (events[-1][1], events[-1][2], 0) if events else ('none', 0, 0)
    started = events[-1][0] if events else None
    expires = started + timedelta(days=pkg_days) if started else None
    db.execute(
        """INSERT INTO users (id, name, username, password_hash, role, package_type, package_started_at,
                              package_expires_at, data_quota_total, data_used, status, created_at)
           VALUES (?, ?, ?, '!demo', 'user', ?, ?, ?, 999999999, ?, 'active', ?)""",
        (uid, f'Khách demo {i}', f'demo{i:03d}', pkg_code, iso(started) if started else None,
         iso(expires) if expires else None, random.randint(0, 800), iso(created)),
    )
    for k, (when, code, days, price) in enumerate(events):
        typ = 'purchase' if k == 0 else 'renew'
        db.execute('INSERT INTO transactions (id, user_id, type, package_type, amount, created_at) VALUES (?,?,?,?,?,?)',
                   (str(uuid.uuid4()), uid, typ, code, price, iso(when)))
        db.execute("""INSERT INTO payment_requests (id, user_id, package_type, amount, status, created_at, decided_at,
                                                    reference_code) VALUES (?,?,?,?, 'approved', ?, ?, ?)""",
                   (str(uuid.uuid4()), uid, code, price, iso(when - timedelta(hours=2)), iso(when), f'DEMO{i:03d}{k}'))
        n_tx += 1
db.commit()
print(f'Đã thêm {a.users} tài khoản demo và {n_tx} giao dịch (bản sao lưu: {a.db}.before-demo-{stamp}).')
