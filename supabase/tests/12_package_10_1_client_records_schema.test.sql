BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(36);

SELECT ok((SELECT EXISTS (SELECT 1 FROM pg_class WHERE relkind = 'S' AND oid = 'app.client_number_seq'::regclass)), 'client number sequence exists');
SELECT is((SELECT seqstart::integer FROM pg_sequence WHERE seqrelid = 'app.client_number_seq'::regclass), 1, 'client number sequence starts at 1');
SELECT is((SELECT seqincrement::integer FROM pg_sequence WHERE seqrelid = 'app.client_number_seq'::regclass), 1, 'client number sequence increments by 1');
SELECT is((SELECT seqmin::integer FROM pg_sequence WHERE seqrelid = 'app.client_number_seq'::regclass), 1, 'client number sequence minimum is 1');
SELECT is((SELECT seqmax::integer FROM pg_sequence WHERE seqrelid = 'app.client_number_seq'::regclass), 999999, 'client number sequence maximum is 999999');
SELECT ok(NOT (SELECT seqcycle FROM pg_sequence WHERE seqrelid = 'app.client_number_seq'::regclass), 'client number sequence does not cycle');
SELECT has_type('app', 'client_record_status', 'client record status enum exists');
SELECT is(
  (SELECT array_agg(enumlabel::text ORDER BY enumsortorder) FROM pg_enum WHERE enumtypid = 'app.client_record_status'::regtype),
  ARRAY['ACTIVE', 'INACTIVE'],
  'client record status enum has exact values'
);
SELECT has_table('app', 'clients', 'clients table exists');
SELECT is(
  (SELECT array_agg(column_name::text ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'clients'),
  ARRAY['id', 'client_number', 'portal_user_id', 'display_name', 'legal_name', 'email', 'phone', 'address', 'status', 'internal_notes', 'is_active', 'archived_at', 'archived_by', 'created_at', 'created_by', 'updated_at', 'updated_by', 'version_number'],
  'clients table has exact approved columns'
);
SELECT col_type_is('app', 'clients', 'id', 'uuid', 'id is uuid');
SELECT col_type_is('app', 'clients', 'client_number', 'text', 'client_number is text');
SELECT col_type_is('app', 'clients', 'portal_user_id', 'uuid', 'portal_user_id is uuid');
SELECT col_type_is('app', 'clients', 'email', 'citext', 'email is citext');
SELECT col_type_is('app', 'clients', 'status', 'app.client_record_status', 'status uses approved enum');
SELECT col_type_is('app', 'clients', 'version_number', 'integer', 'version number is integer');
SELECT has_index('app', 'clients', 'clients_client_number_uk', 'client number unique constraint index exists');
SELECT has_index('app', 'clients', 'clients_portal_user_uk', 'portal user unique constraint index exists');
SELECT has_index('app', 'clients', 'clients_active_lookup_idx', 'active lookup index exists');
SELECT has_index('app', 'clients', 'clients_display_name_lower_idx', 'case-insensitive display-name index exists');
SELECT has_index('app', 'clients', 'clients_email_non_null_idx', 'non-null email index exists');
SELECT has_index('app', 'clients', 'clients_owner_list_order_idx', 'owner list ordering index exists');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.clients'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.clients'::regclass AND attname = 'client_number')) LIKE '%nextval(''app.client_number_seq''::regclass)%', 'client number default uses sequence');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.clients'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.clients'::regclass AND attname = 'client_number')) LIKE '%lpad%', 'client number default uses zero padding');
SELECT ok((SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef WHERE adrelid = 'app.clients'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'app.clients'::regclass AND attname = 'client_number')) LIKE '%CL-%', 'client number default uses CL prefix');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'clients_client_number_ck') LIKE '%^CL-[0-9]{6}$%', 'client number format constraint exists');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'clients_lifecycle_ck') LIKE '%portal_user_id IS NULL%', 'archive lifecycle requires no portal link');
SELECT ok((SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'clients_archive_pair_ck') LIKE '%archived_at IS NULL%', 'archive pair constraint exists');
SELECT throws_ok(
  $$ INSERT INTO app.clients (client_number, display_name, created_by, updated_by) VALUES ('BAD-1', 'Bad Client', '10000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000000') $$,
  '23514',
  'new row for relation "clients" violates check constraint "clients_client_number_ck"',
  'invalid manual Client number is rejected'
);
SELECT ok((SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgname = 'clients_no_delete') LIKE '%app.prevent_client_delete%', 'hard delete prevention trigger exists');
SELECT ok((SELECT pg_get_functiondef('app.prevent_client_delete()'::regprocedure)) LIKE '%Client records cannot be deleted.%', 'hard delete prevention function raises safely');
SELECT ok((SELECT pg_get_functiondef('app.clients_trusted_update_guard()'::regprocedure)) LIKE '%Client number is immutable.%', 'client number immutability trigger exists');
SELECT ok(lower((SELECT string_agg(pg_get_functiondef(p.oid), ' ') FROM pg_proc AS p INNER JOIN pg_namespace AS n ON n.oid = p.pronamespace WHERE n.nspname = 'app' OR (n.nspname = 'public' AND p.proname LIKE '%client%'))) NOT LIKE '%max(%+ 1%', 'no MAX plus one client-number generation exists');
SELECT ok(NOT EXISTS (
  SELECT 1
  FROM information_schema.columns
  WHERE table_schema = 'app'
    AND table_name = 'clients'
    AND column_name IN ('client_type', 'country_of_residence', 'time_zone', 'whatsapp_number', 'preferred_currency_code', 'archive_reason', 'total_paid', 'outstanding_amount', 'identification_document')
), 'forbidden document and financial columns are absent');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'app.clients'::regclass), 'clients RLS enabled');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE oid = 'app.clients'::regclass), 'clients RLS forced');

SELECT * FROM finish();
ROLLBACK;
