BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE SCHEMA IF NOT EXISTS app;

DO $migration$
BEGIN
  CREATE TYPE app.user_status AS ENUM (
    'INVITED',
    'ACTIVE',
    'SUSPENDED',
    'DISABLED'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$migration$;

DO $migration$
BEGIN
  CREATE TYPE app.user_type AS ENUM ('STAFF', 'CLIENT');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$migration$;

COMMIT;
