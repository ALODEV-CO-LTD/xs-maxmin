# server

[![style: dart frog lint][dart_frog_lint_badge]][dart_frog_lint_link]
[![License: MIT][license_badge]][license_link]
[![Powered by Dart Frog](https://img.shields.io/endpoint?url=https://tinyurl.com/dartfrog-badge)](https://dart-frog.dev)

An example application built with dart_frog

[dart_frog_lint_badge]: https://img.shields.io/badge/style-dart_frog_lint-1DF9D2.svg
[dart_frog_lint_link]: https://pub.dev/packages/dart_frog_lint
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT

## First boot / local development

A brand-new database (`data/xoso.db` missing) is seeded with ONE admin, username `1`. There is no default password:

- `XOSO_ADMIN_PASSWORD=<password>` sets it; otherwise a random password is printed once to stderr (`[seed] admin password: ...`).
- `XOSO_SEED_DEMO=1` additionally creates five demo customers (usernames 2-6). Never set it in production.

Local dev on a fresh `data/` folder:

    XOSO_SEED_DEMO=1 XOSO_ADMIN_PASSWORD=dev-password XOSO_JWT_SECRET=dev-secret-0123456789 dart_frog dev

Existing databases are not changed.
