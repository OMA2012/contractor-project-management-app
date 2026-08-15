BEGIN;
SELECT plan(12);

ALTER SEQUENCE app.financial_account_number_seq RESTART WITH 1;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000010701', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.107@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000010702', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.107@example.test', '', now(), '{}', '{}', now(), now());

SELECT * FROM app.bootstrap_first_owner('00000000-0000-0000-0000-000000010701', 'owner.107@example.test', 'Owner 107', decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'hex'), 'req-107', 'corr-107');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000010701', true);
SELECT public.activate_current_invited_owner();

INSERT INTO app.contractor_profiles (legal_name, display_name, default_reporting_currency_code, time_zone, created_by, updated_by)
VALUES ('Safe Metadata Contractor', 'Safe Metadata Contractor', 'USD', 'Asia/Singapore', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010701'));

INSERT INTO app.users (id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
VALUES ('10000000-0000-0000-0000-000000010702', '00000000-0000-0000-0000-000000010702', 'client.107@example.test', 'CLIENT', 'ACTIVE', true, (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010701'));

INSERT INTO app.user_profiles (user_id, full_name, created_by, updated_by)
VALUES ('10000000-0000-0000-0000-000000010702', 'Client 107', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010701'), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010701'));

INSERT INTO app.user_roles (user_id, role_code, assigned_by, is_active)
VALUES ('10000000-0000-0000-0000-000000010702', 'client', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000010701'), true);

SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000010701', 'Secret Bank', 'BANK', 'USD', 'Bank 107', '****0107', decode('bbbbbbbbbbbbbbbb', 'hex'), true, 'old note');
SELECT * FROM public.server_owner_create_financial_account('00000000-0000-0000-0000-000000010701', 'Plain Cash', 'CASH', 'USD');

SELECT lives_ok($$ SELECT * FROM public.server_owner_update_financial_account_metadata('00000000-0000-0000-0000-000000010701', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 1, 'Secret Bank Updated', 'BANK', 'USD', 'Bank 107 Updated', '****9999', 'new note') $$, 'metadata update succeeds without encrypted payload input');
SELECT is((SELECT encrypted_account_details FROM app.financial_accounts WHERE account_number = 'FA-000001'), decode('bbbbbbbbbbbbbbbb', 'hex'), 'metadata update preserves existing encrypted details');
SELECT results_eq($$ SELECT name, bank_name, masked_account_identifier, notes, version_number FROM app.financial_accounts WHERE account_number = 'FA-000001' $$, $$ VALUES ('Secret Bank Updated'::varchar(160), 'Bank 107 Updated'::varchar(160), '****9999'::varchar(80), 'new note'::text, 2) $$, 'safe metadata fields and optimistic version update');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_financial_account_metadata('00000000-0000-0000-0000-000000010701', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 1, 'Conflict', 'BANK', 'USD', 'Bank 107', '****0107') $$, '40001', 'Financial account version conflict.', 'optimistic version conflict remains enforced');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_financial_account_metadata('00000000-0000-0000-0000-000000010701', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 2, 'Unsafe Cash', 'CASH', 'USD') $$, '23514', 'Financial account encrypted metadata cannot be silently cleared.', 'BANK to CASH with encrypted payload is rejected without clearing data');
SELECT is((SELECT encrypted_account_details FROM app.financial_accounts WHERE account_number = 'FA-000001'), decode('bbbbbbbbbbbbbbbb', 'hex'), 'failed BANK to CASH conversion still preserves encrypted details');
SELECT lives_ok($$ SELECT * FROM public.server_owner_update_financial_account_metadata('00000000-0000-0000-0000-000000010701', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000002'), 1, 'Plain Bank', 'BANK', 'SAR', 'Plain Bank 107', '****0202') $$, 'pre-history CASH to BANK and currency update remain allowed under DB rules');
SELECT results_eq($$ SELECT fa.currency_code, la.currency_code FROM app.financial_accounts fa JOIN app.ledger_accounts la ON la.financial_account_id = fa.id WHERE fa.account_number = 'FA-000002' $$, $$ VALUES ('SAR'::char(3), 'SAR'::char(3)) $$, 'ledger-account synchronization remains active');
SELECT throws_ok($$ SELECT * FROM public.server_owner_update_financial_account_metadata('00000000-0000-0000-0000-000000010702', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 2, 'Client Attempt', 'BANK', 'USD', 'Bank 107', '****0107') $$, '42501', 'Privileged operation denied.', 'Client actor is denied by Owner/Admin authorization');
SELECT throws_ok($$ SET ROLE authenticated; SELECT * FROM public.server_owner_update_financial_account_metadata('00000000-0000-0000-0000-000000010701', (SELECT id FROM app.financial_accounts WHERE account_number = 'FA-000001'), 2, 'Direct Auth', 'BANK', 'USD', 'Bank 107', '****0107') $$, '42501', NULL, 'authenticated direct execution is not granted');
RESET ROLE;
SELECT has_function('public', 'server_owner_update_financial_account_metadata', ARRAY['uuid','uuid','integer','text','app.financial_account_type','char','text','text','text','text','text','text','inet']::name[], 'service wrapper exists without encrypted parameter');
SELECT ok(EXISTS (SELECT 1 FROM app.activity_logs WHERE action = 'financial_account_metadata_updated' AND entity_type = 'financial_account'), 'activity logging records metadata update');

SELECT * FROM finish();
ROLLBACK;
