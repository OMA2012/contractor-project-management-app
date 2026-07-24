BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(53);

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000901', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.09@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000902', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client.09@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000903', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other.09@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000904', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'existing.invited.09@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000905', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'existing.active.09@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000906', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'existing.suspended.09@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000907', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'existing.disabled.09@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000908', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'existing.staff.09@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000909', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'revoked.client.09@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000910', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'staff.invite.09@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000911', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rollback.client.09@example.test', '', now(), '{}', '{}', now(), now());

SELECT throws_ok(
  $$ SELECT * FROM app.bootstrap_first_owner(
       '00000000-0000-0000-0000-000000000901',
       'owner.09@example.test',
       '   ',
       decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'hex'),
       'req',
       'corr'
     ) $$,
  '23514',
  'Owner name is required.',
  'bootstrap rejects blank owner name'
);

SELECT * FROM app.bootstrap_first_owner(
  '00000000-0000-0000-0000-000000000901',
  'owner.09@example.test',
  'Owner Nine',
  decode('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'hex'),
  'req',
  'corr'
);
SELECT is((SELECT full_name FROM app.user_profiles WHERE user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000901')), 'Owner Nine'::varchar(160), 'bootstrap creates owner profile');
SELECT is((SELECT status::text FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000901'), 'INVITED', 'bootstrap creates invited owner');
SELECT ok(EXISTS (SELECT 1 FROM app.user_roles WHERE role_code = 'owner_admin'), 'bootstrap assigns owner_admin');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action IN ('first_owner_bootstrap','role_assigned','invitation_created')), 3, 'bootstrap writes three activity rows');
SELECT throws_ok(
  $$ SELECT * FROM app.bootstrap_first_owner(
       '00000000-0000-0000-0000-000000000903',
       'other.09@example.test',
       'Other Owner',
       decode('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'hex'),
       'req',
       'corr'
     ) $$,
  '42501',
  'Privileged operation denied.',
  'bootstrap refuses historical owner state'
);
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000901', true);
SELECT public.activate_current_invited_owner();
SELECT is((SELECT status::text FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000901'), 'ACTIVE', 'owner activation transitions to active');
SELECT is((SELECT status FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000901')), 'ACCEPTED'::varchar(20), 'owner activation accepts invitation');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'account_activated' AND effective_role_code = 'owner_admin'), 1, 'owner activation logs owner_admin snapshot');
SELECT throws_ok($$ SELECT public.activate_current_invited_owner() $$, '23514', NULL, 'repeated owner activation rejected');

INSERT INTO app.users (auth_subject, email, user_type, status, is_active, deactivated_at, deactivated_by)
VALUES
  ('00000000-0000-0000-0000-000000000904', 'existing.invited.09@example.test', 'CLIENT', 'INVITED', false, NULL, NULL),
  ('00000000-0000-0000-0000-000000000905', 'existing.active.09@example.test', 'CLIENT', 'ACTIVE', true, NULL, NULL),
  ('00000000-0000-0000-0000-000000000906', 'existing.suspended.09@example.test', 'CLIENT', 'SUSPENDED', false, NULL, NULL),
  ('00000000-0000-0000-0000-000000000907', 'existing.disabled.09@example.test', 'CLIENT', 'DISABLED', false, now(), (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000901')),
  ('00000000-0000-0000-0000-000000000908', 'existing.staff.09@example.test', 'STAFF', 'INVITED', false, NULL, NULL);

SELECT throws_ok($$ SELECT * FROM app.create_client_invitation('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000903','existing.invited.09@example.test',decode('0101010101010101010101010101010101010101010101010101010101010101','hex')) $$, '23505', NULL, 'create rejects existing invited client email');
SELECT throws_ok($$ SELECT * FROM app.create_client_invitation('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000903','existing.active.09@example.test',decode('0202020202020202020202020202020202020202020202020202020202020202','hex')) $$, '23505', NULL, 'create rejects existing active client email');
SELECT throws_ok($$ SELECT * FROM app.create_client_invitation('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000903','existing.suspended.09@example.test',decode('0303030303030303030303030303030303030303030303030303030303030303','hex')) $$, '23505', NULL, 'create rejects existing suspended client email');
SELECT throws_ok($$ SELECT * FROM app.create_client_invitation('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000903','existing.disabled.09@example.test',decode('0404040404040404040404040404040404040404040404040404040404040404','hex')) $$, '23505', NULL, 'create rejects existing disabled client email');
SELECT throws_ok($$ SELECT * FROM app.create_client_invitation('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000903','existing.staff.09@example.test',decode('0505050505050505050505050505050505050505050505050505050505050505','hex')) $$, '23505', NULL, 'create rejects existing staff email');

SELECT * FROM app.create_client_invitation('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000902','client.09@example.test',decode('1111111111111111111111111111111111111111111111111111111111111111','hex'),'req','corr');
SELECT is((SELECT status::text FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'), 'INVITED', 'client create makes invited user');
SELECT is((SELECT count(*)::integer FROM app.user_profiles WHERE user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902')), 0, 'client create does not create profile');
SELECT is((SELECT count(*)::integer FROM app.user_roles WHERE user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902')), 0, 'client create does not assign role');
SELECT throws_ok($$ SELECT * FROM app.create_client_invitation('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000902','newmail.09@example.test',decode('1212121212121212121212121212121212121212121212121212121212121212','hex')) $$, '23505', NULL, 'create rejects existing auth subject');

SELECT * FROM app.create_client_invitation('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000909','revoked.client.09@example.test',decode('1313131313131313131313131313131313131313131313131313131313131313','hex'),'req','corr');
SELECT lives_ok($$ SELECT app.revoke_client_invitation('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000909')),'  duplicate request  ','req','corr') $$, 'active owner revokes a valid pending client invitation');
SELECT is((SELECT status FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000909')), 'REVOKED'::varchar(20), 'revoked client invitation has revoked status');
SELECT ok((SELECT revoked_at IS NOT NULL AND revoked_by = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000901') AND revoke_reason = 'duplicate request' FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000909')), 'revoked invitation stores timestamp actor and trimmed reason');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action = 'invitation_revoked' AND entity_id = (SELECT id FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000909'))), 1, 'client revocation writes one activity row');
SELECT ok((SELECT user_type = 'CLIENT' AND status = 'INVITED' AND NOT is_active FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000909'), 'revocation leaves linked client invited and inactive');
SELECT throws_ok($$ SELECT app.revoke_client_invitation('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000909')),'again') $$, '23514', NULL, 'repeated revocation is rejected');
SELECT is((SELECT status FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000909')), 'REVOKED'::varchar(20), 'rejected repeated revocation leaves terminal status unchanged');

INSERT INTO app.users (auth_subject, email, user_type, status, is_active)
VALUES ('00000000-0000-0000-0000-000000000910', 'staff.invite.09@example.test', 'STAFF', 'INVITED', false);
INSERT INTO app.user_invitations (invited_user_id, token_hash, status, expires_at, invited_by)
VALUES ((SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000910'), decode('1414141414141414141414141414141414141414141414141414141414141414','hex'), 'PENDING', now() + interval '7 days', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000901'));
SELECT throws_ok($$ SELECT app.revoke_client_invitation('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000910')),'owner revoke') $$, '23514', NULL, 'pending first-owner/staff invitation cannot be revoked through client function');
SELECT throws_ok($$ SELECT app.revoke_client_invitation('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000910')),'staff revoke') $$, '23514', NULL, 'staff-linked invitation cannot be revoked through client function');

SELECT * FROM app.resend_client_invitation('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'),decode('2222222222222222222222222222222222222222222222222222222222222222','hex'),'req','corr');
SELECT is((SELECT count(*)::integer FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902') AND status = 'PENDING'), 1, 'resend leaves one pending invite');
SELECT ok(EXISTS (SELECT 1 FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902') AND status = 'REVOKED'), 'resend revoked previous pending');
UPDATE app.user_invitations SET status = 'EXPIRED' WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902') AND status = 'PENDING';
SELECT lives_ok($$ SELECT * FROM app.resend_client_invitation('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'),decode('2323232323232323232323232323232323232323232323232323232323232323','hex')) $$, 'resend from expired invitation creates replacement');
UPDATE app.user_invitations SET status = 'REVOKED', revoked_at = now(), revoked_by = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000901'), revoke_reason = 'test' WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902') AND status = 'PENDING';
SELECT lives_ok($$ SELECT * FROM app.resend_client_invitation('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'),decode('2424242424242424242424242424242424242424242424242424242424242424','hex')) $$, 'resend from revoked invitation creates replacement');

SELECT throws_ok($$ SELECT app.accept_client_invitation('00000000-0000-0000-0000-000000000902',decode('2424242424242424242424242424242424242424242424242424242424242424','hex'),'   ') $$, '23514', 'Full name is required.', 'client acceptance rejects blank name');
SELECT app.accept_client_invitation('00000000-0000-0000-0000-000000000902',decode('2424242424242424242424242424242424242424242424242424242424242424','hex'),' Client Nine ');
SELECT is((SELECT full_name FROM app.user_profiles WHERE user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902')), 'Client Nine'::varchar(160), 'client acceptance creates trimmed profile');
SELECT ok(EXISTS (SELECT 1 FROM app.user_roles WHERE user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902') AND role_code = 'client' AND is_active), 'client acceptance assigns only client role');
SELECT is((SELECT status::text FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'), 'ACTIVE', 'client acceptance activates user');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE action IN ('invitation_accepted','role_assigned','account_activated') AND entity_id IN ((SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'), (SELECT id FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902') AND status = 'ACCEPTED'), (SELECT id FROM app.user_roles WHERE user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902') AND role_code='client'))), 3, 'client acceptance writes expected activity rows');
SELECT throws_ok($$ SELECT app.accept_client_invitation('00000000-0000-0000-0000-000000000902',decode('2424242424242424242424242424242424242424242424242424242424242424','hex'),'Client Again') $$, '23514', NULL, 'repeated acceptance rejected');
SELECT throws_ok($$ SELECT * FROM app.resend_client_invitation('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'),decode('2525252525252525252525252525252525252525252525252525252525252525','hex')) $$, '23514', NULL, 'resend after accepted is rejected');
SELECT throws_ok($$ SELECT app.revoke_client_invitation('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902') AND status = 'ACCEPTED'),'accepted revoke') $$, '23514', NULL, 'accepted invitation cannot be revoked');
SELECT is((SELECT status FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902') AND token_hash = decode('2424242424242424242424242424242424242424242424242424242424242424','hex')), 'ACCEPTED'::varchar(20), 'failed accepted revocation leaves status unchanged');

SELECT * FROM app.create_client_invitation('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000911','rollback.client.09@example.test',decode('2626262626262626262626262626262626262626262626262626262626262626','hex'),'req','corr');
CREATE FUNCTION pg_temp.fail_acceptance_activity_log()
RETURNS trigger
LANGUAGE plpgsql
AS $trigger$
BEGIN
  IF NEW.action = 'role_assigned' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'test activity failure';
  END IF;
  RETURN NEW;
END
$trigger$;
CREATE TRIGGER test_acceptance_activity_log_failure
BEFORE INSERT ON app.activity_logs
FOR EACH ROW
EXECUTE FUNCTION pg_temp.fail_acceptance_activity_log();
SELECT throws_ok($$ SELECT app.accept_client_invitation('00000000-0000-0000-0000-000000000911',decode('2626262626262626262626262626262626262626262626262626262626262626','hex'),'Rollback Client') $$, 'P0001', 'test activity failure', 'client acceptance rolls back when activity logging fails');
DROP TRIGGER test_acceptance_activity_log_failure ON app.activity_logs;
SELECT is((SELECT count(*)::integer FROM app.user_profiles WHERE user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000911')), 0, 'rollback leaves no profile');
SELECT is((SELECT count(*)::integer FROM app.user_roles WHERE user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000911') AND role_code = 'client'), 0, 'rollback leaves no client role');
SELECT ok((SELECT status = 'INVITED' AND NOT is_active FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000911'), 'rollback leaves user invited and inactive');
SELECT is((SELECT status FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000911')), 'PENDING'::varchar(20), 'rollback leaves invitation pending');
SELECT is((SELECT count(*)::integer FROM app.activity_logs WHERE entity_id IN ((SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000911'), (SELECT id FROM app.user_invitations WHERE invited_user_id = (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000911')))), 1, 'rollback leaves only initial invitation activity row');

SELECT app.suspend_client_account('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'),'suspend test');
SELECT is((SELECT status::text FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'), 'SUSPENDED', 'client suspended');
SELECT app.reactivate_client_account('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'),'reactivate test');
SELECT is((SELECT status::text FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'), 'ACTIVE', 'client reactivated');
SELECT app.disable_client_account('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'),'disable test');
SELECT is((SELECT status::text FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'), 'DISABLED', 'client disabled');
SELECT throws_ok($$ SELECT app.reactivate_client_account('00000000-0000-0000-0000-000000000901',(SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'),'nope') $$, '23514', NULL, 'disabled client is terminal');
SELECT throws_ok($$ DELETE FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902' $$, '23514', 'users rows cannot be permanently deleted.', 'no hard deletion remains enforced');
SELECT throws_ok($$ INSERT INTO app.user_roles (user_id, role_code, assigned_by) VALUES ((SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000902'), 'project_manager', (SELECT id FROM app.users WHERE auth_subject = '00000000-0000-0000-0000-000000000901')) $$, '23514', NULL, '0907 trigger still prevents reserved role assignment to client');

SELECT * FROM finish();
ROLLBACK;
