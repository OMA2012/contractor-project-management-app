#!/bin/sh
set -eu

if [ -z "${SCANNER_TOKEN:-}" ]; then
  echo "SCANNER_TOKEN is required" >&2
  exit 1
fi

mkdir -p /run/clamav /var/lib/clamav /var/log/clamav
chown -R clamav:clamav /var/lib/clamav /var/log/clamav
chown clamav:clamav /run/clamav

# Try an update on every start. A failed network update is acceptable only when
# an existing signature database is present and clamd can prove it is usable.
if ! freshclam --config-file=/etc/clamav/freshclam.conf; then
  signature_database=""
  for candidate in /var/lib/clamav/*.cvd /var/lib/clamav/*.cld; do
    if [ -f "$candidate" ]; then signature_database="$candidate"; break; fi
  done
  if [ -z "$signature_database" ]; then
    echo "ClamAV signatures are unavailable" >&2
    exit 1
  fi
fi

clamd --config-file=/etc/clamav/clamd.conf &
clamd_pid=$!
freshclam_pid=""
http_pid=""

shutdown() {
  trap - EXIT INT TERM
  for pid in "$http_pid" "$freshclam_pid" "$clamd_pid"; do
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
  done
  wait 2>/dev/null || true
}
trap shutdown EXIT INT TERM

if ! su clamav -s /bin/sh -c \
  'deno run --allow-net --allow-read=/run/clamav/clamd.ctl --allow-write=/run/clamav/clamd.ctl /app/main.ts --wait-for-clamd'; then
  echo "ClamAV failed to become ready" >&2
  exit 1
fi

freshclam --config-file=/etc/clamav/freshclam.conf --daemon &
freshclam_pid=$!
su clamav -s /bin/sh -c \
  'exec deno run --allow-env=PORT,SCANNER_TOKEN --allow-net --allow-read=/run/clamav/clamd.ctl --allow-write=/run/clamav/clamd.ctl /app/main.ts' &
http_pid=$!

set +e
wait -n "$clamd_pid" "$freshclam_pid" "$http_pid"
status=$?
set -e
if [ "$status" -eq 0 ]; then status=1; fi
exit "$status"
