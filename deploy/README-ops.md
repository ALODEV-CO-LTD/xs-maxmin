# Ops notes (xs.massagehomeriyadh.com, container 501)

- Security headers: `nginx-security-headers.conf` is installed at
  `/etc/nginx/xs-maxmin-security-headers.conf` and included from the server block of
  `/etc/nginx/sites-enabled/xs-maxmin.conf`. CSP is Report-Only; review before enforcing.
  Always `nginx -t` before `nginx -s reload`; keep backups outside sites-enabled.
- DB backup: `xs-maxmin-backup.sh` -> `/usr/local/bin/` (chmod 755); `xs-maxmin-backup.cron`
  -> `/etc/cron.d/xs-maxmin-backup`. Uses `sqlite3 .backup` (safe while the service runs),
  verifies integrity, keeps newest 14 in `/var/backups/xs-maxmin` (700/600), logs to
  `/var/log/xs-maxmin/backup.log`.
- Restore: stop xs-maxmin-backend, copy a backup over `xoso.db`, chmod 600, start the service.
- Permissions: DB dir contents are 600 (backend runs as root).
