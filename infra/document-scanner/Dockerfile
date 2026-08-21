FROM denoland/deno:alpine-2.9.4@sha256:13851184d6705150b8b230c5377f26c3bd182865d28700bb72bc0b2c271b504a AS deno-runtime
FROM clamav/clamav:1.4.6@sha256:c3bfbf2a2c9abc1fc179e63832a9e8bfac901ede83853e3fa10acf6f1fb5c803 AS clamav-runtime
FROM scratch

USER root

COPY --from=clamav-runtime / /
COPY --from=deno-runtime /bin/deno /bin/deno
COPY --from=deno-runtime /lib64 /lib64
COPY --from=deno-runtime /usr/local/lib/glibc /usr/local/lib/glibc
COPY clamd.conf /etc/clamav/clamd.conf
COPY freshclam.conf /etc/clamav/freshclam.conf
COPY --chown=clamav:clamav main.ts /app/main.ts
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod 0755 /app/entrypoint.sh

ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=120s --retries=3 \
  CMD wget -q -O - "http://127.0.0.1:${PORT:-8080}/health" | grep -q '"status":"ready"'

ENTRYPOINT ["/sbin/tini", "--", "/app/entrypoint.sh"]
