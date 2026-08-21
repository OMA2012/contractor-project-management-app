# Document scanner

This directory builds one HTTP adapter backed by an internal ClamAV daemon. It
retains no uploaded files: each bounded request is held in memory only for the
duration of its scan.

## Configuration

- `SCANNER_TOKEN` (required): private bearer token accepted by `POST /scan`.
- `PORT`: HTTP port supplied by the hosting provider (defaults to `8080` for
  local Docker use).

The expected public endpoint is:

```text
https://<scanner-host>/scan
```

## Railway deployment

1. Deploy this directory using its `Dockerfile`.
2. Set `SCANNER_TOKEN` as a private Railway variable.
3. Generate an HTTPS domain for the service's HTTP port.

Set these secrets in Supabase staging:

```text
DOCUMENT_SCANNER_URL=https://<scanner-host>/scan
DOCUMENT_SCANNER_TOKEN=<same secret>
```

Only the HTTP adapter should be publicly routed. `clamd` uses an internal Unix
socket and has no public TCP listener.
