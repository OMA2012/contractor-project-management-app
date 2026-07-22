BEGIN;

-- Package 09.1 deliberately creates no application-facing policies.
-- Until the next reviewed package adds narrowly scoped policies/functions,
-- anonymous and authenticated users receive no direct table access.
ALTER TABLE app.currencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.currencies FORCE ROW LEVEL SECURITY;
ALTER TABLE app.contractor_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.contractor_profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE app.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.users FORCE ROW LEVEL SECURITY;
ALTER TABLE app.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.user_profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE app.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.roles FORCE ROW LEVEL SECURITY;
ALTER TABLE app.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.user_roles FORCE ROW LEVEL SECURITY;

REVOKE ALL ON SCHEMA app FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA app FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA app FROM anon, authenticated;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA app
  REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
  REVOKE ALL ON SEQUENCES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;

COMMIT;
