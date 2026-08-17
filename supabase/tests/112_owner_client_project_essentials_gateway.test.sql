BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(20);

SELECT has_table('app', 'client_invitation_links', 'client_invitation_links table exists');
SELECT has_column('app', 'client_invitation_links', 'invitation_id', 'client_invitation_links.invitation_id exists');
SELECT has_column('app', 'client_invitation_links', 'client_id', 'client_invitation_links.client_id exists');
SELECT has_column('app', 'client_invitation_links', 'invited_user_id', 'client_invitation_links.invited_user_id exists');
SELECT has_column('app', 'client_invitation_links', 'created_by', 'client_invitation_links.created_by exists');
SELECT col_is_pk('app', 'client_invitation_links', 'invitation_id', 'client_invitation_links uses invitation as primary key');
SELECT fk_ok('app', 'client_invitation_links', 'invitation_id', 'app', 'user_invitations', 'id', 'invitation link references user_invitations');
SELECT fk_ok('app', 'client_invitation_links', 'client_id', 'app', 'clients', 'id', 'invitation link references clients');
SELECT fk_ok('app', 'client_invitation_links', 'invited_user_id', 'app', 'users', 'id', 'invitation link references users');
SELECT ok(relrowsecurity, 'client_invitation_links has RLS enabled') FROM pg_class WHERE oid = 'app.client_invitation_links'::regclass;
SELECT ok(relforcerowsecurity, 'client_invitation_links forces RLS') FROM pg_class WHERE oid = 'app.client_invitation_links'::regclass;
SELECT ok(NOT has_table_privilege('authenticated', 'app.client_invitation_links', 'SELECT,INSERT,UPDATE,DELETE'), 'authenticated has no direct invitation link table access');

SELECT has_function(
  'public',
  'server_create_client_record_invitation',
  ARRAY['uuid', 'uuid', 'uuid', 'bytea', 'text', 'text', 'text', 'inet']::name[],
  'linked Client invitation server wrapper exists'
);
SELECT has_function(
  'app',
  'accept_client_invitation_and_link_record',
  ARRAY['uuid', 'bytea', 'text', 'text', 'text', 'text', 'inet']::name[],
  'acceptance linkage wrapper exists'
);
SELECT has_function(
  'public',
  'server_owner_client_invitation_status',
  ARRAY['uuid', 'uuid']::name[],
  'linked invitation status server wrapper exists'
);
SELECT function_privs_are(
  'public',
  'server_owner_client_invitation_status',
  ARRAY['uuid', 'uuid']::name[],
  'service_role',
  ARRAY['EXECUTE']::text[],
  'service_role can execute linked invitation status wrapper'
);
SELECT function_privs_are(
  'public',
  'server_create_client_record_invitation',
  ARRAY['uuid', 'uuid', 'uuid', 'bytea', 'text', 'text', 'text', 'inet']::name[],
  'authenticated',
  ARRAY[]::text[],
  'authenticated cannot execute linked invitation server wrapper'
);
SELECT function_privs_are(
  'public',
  'server_create_client_record_invitation',
  ARRAY['uuid', 'uuid', 'uuid', 'bytea', 'text', 'text', 'text', 'inet']::name[],
  'service_role',
  ARRAY['EXECUTE']::text[],
  'service_role can execute linked invitation server wrapper'
);
SELECT function_privs_are(
  'public',
  'server_accept_client_invitation',
  ARRAY['uuid', 'bytea', 'text', 'text', 'text', 'text', 'inet']::name[],
  'service_role',
  ARRAY['EXECUTE']::text[],
  'service_role can execute updated acceptance wrapper'
);
SELECT isnt(
  pg_get_functiondef('public.server_accept_client_invitation(uuid,bytea,text,text,text,text,inet)'::regprocedure),
  NULL,
  'acceptance gateway definition is available'
);

SELECT * FROM finish();

ROLLBACK;
