#!/usr/bin/env python3
from pathlib import Path
import re
import sys
import tomllib
import yaml
from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []
passes: list[str] = []

def require(condition: bool, message: str) -> None:
    (passes if condition else errors).append(message)

migrations = sorted((ROOT / 'supabase/migrations').glob('*.sql'))
tests = sorted((ROOT / 'supabase/tests').glob('*.sql'))
required_09_1_migrations = {
    '20260721220100_0901_extensions_and_identity_types.sql',
    '20260721220200_0902_currency_reference.sql',
    '20260721220300_0903_contractor_profiles.sql',
    '20260721220400_0904_users_and_user_profiles.sql',
    '20260721220500_0905_predefined_roles.sql',
    '20260721220600_0906_user_role_assignments.sql',
    '20260721220700_0907_foundation_integrity_triggers.sql',
    '20260721220800_0908_default_deny_rls.sql',
}
required_09_1_tests = {
    '00_package_09_1_schema.test.sql',
    '01_package_09_1_constraints.test.sql',
    '02_package_09_1_default_deny.test.sql',
}
migration_names = {p.name for p in migrations}
test_names = {p.name for p in tests}
for name in sorted(required_09_1_migrations):
    require(name in migration_names, f'required Package 09.1 migration exists: {name}')
for name in sorted(required_09_1_tests):
    require(name in test_names, f'required Package 09.1 pgTAP suite exists: {name}')
require(
    '20260723092000_0909_public_current_account_rpc.sql' in migration_names,
    'required Package 09.2B migration exists: 20260723092000_0909_public_current_account_rpc.sql',
)
require(
    '03_package_09_2_current_account_rpc.test.sql' in test_names,
    'required Package 09.2B pgTAP suite exists: 03_package_09_2_current_account_rpc.test.sql',
)
required_09_2c1_migrations = {
    '20260724094000_0910_first_release_current_account_access.sql',
    '20260724094100_0911_central_activity_logs.sql',
    '20260724094200_0912_client_user_invitations.sql',
}
required_09_2c1_tests = {
    '04_package_09_2_first_release_access.test.sql',
    '05_package_09_2_activity_logs.test.sql',
    '06_package_09_2_client_invitations.test.sql',
}
for name in sorted(required_09_2c1_migrations):
    require(name in migration_names, f'required Package 09.2C1 migration exists: {name}')
for name in sorted(required_09_2c1_tests):
    require(name in test_names, f'required Package 09.2C1 pgTAP suite exists: {name}')
required_09_2c2_migrations = {
    '20260724095000_0913_identity_mutation_private_functions.sql',
    '20260724095100_0914_identity_mutation_public_gateways.sql',
    '20260724095200_0915_identity_mutation_security_grants.sql',
}
required_09_2c2_tests = {
    '07_package_09_2_identity_private_functions.test.sql',
    '08_package_09_2_identity_gateways.test.sql',
    '09_package_09_2_identity_mutations.test.sql',
}
for name in sorted(required_09_2c2_migrations):
    require(name in migration_names, f'required Package 09.2C2 migration exists: {name}')
for name in sorted(required_09_2c2_tests):
    require(name in test_names, f'required Package 09.2C2 pgTAP suite exists: {name}')
required_09_2c3b_migrations = {
    '20260724095300_0916_identity_service_lookup_context.sql',
}
required_09_2c3b_tests = {
    '10_package_09_2_identity_service_context.test.sql',
}
for name in sorted(required_09_2c3b_migrations):
    require(name in migration_names, f'required Package 09.2C3B migration exists: {name}')
for name in sorted(required_09_2c3b_tests):
    require(name in test_names, f'required Package 09.2C3B pgTAP suite exists: {name}')
require(
    '20260724095400_0917_first_owner_delivery_recovery_context.sql' in migration_names,
    'required Package 09.2C3E migration exists: 20260724095400_0917_first_owner_delivery_recovery_context.sql',
)
require(
    '11_package_09_2_first_owner_delivery_recovery.test.sql' in test_names,
    'required Package 09.2C3E pgTAP suite exists: 11_package_09_2_first_owner_delivery_recovery.test.sql',
)
required_10_1_migrations = {
    '20260724095500_1001_client_business_records.sql',
    '20260724095600_1002_client_business_record_functions.sql',
    '20260724095700_1003_client_business_record_grants.sql',
}
required_10_1_tests = {
    '12_package_10_1_client_records_schema.test.sql',
    '13_package_10_1_client_records_security.test.sql',
    '14_package_10_1_client_records_operations.test.sql',
}
for name in sorted(required_10_1_migrations):
    require(name in migration_names, f'required Package 10.1 migration exists: {name}')
for name in sorted(required_10_1_tests):
    require(name in test_names, f'required Package 10.1 pgTAP suite exists: {name}')
required_10_2_migrations = {
    '20260724095800_1004_project_business_records.sql',
    '20260724095900_1005_project_business_record_functions.sql',
    '20260724100000_1006_project_business_record_grants.sql',
}
required_10_2_tests = {
    '15_package_10_2_project_records_schema.test.sql',
    '16_package_10_2_project_records_security.test.sql',
    '17_package_10_2_project_records_operations.test.sql',
}
for name in sorted(required_10_2_migrations):
    require(name in migration_names, f'required Package 10.2 migration exists: {name}')
for name in sorted(required_10_2_tests):
    require(name in test_names, f'required Package 10.2 pgTAP suite exists: {name}')
required_10_3_migrations = {
    '20260724100100_1007_project_staff_assignments.sql',
    '20260724100200_1008_project_staff_assignment_functions.sql',
    '20260724100300_1009_project_staff_assignment_grants.sql',
}
required_10_3_tests = {
    '18_package_10_3_project_staff_assignments_schema.test.sql',
    '19_package_10_3_project_staff_assignments_security.test.sql',
    '20_package_10_3_project_staff_assignments_operations.test.sql',
}
for name in sorted(required_10_3_migrations):
    require(name in migration_names, f'required Package 10.3 migration exists: {name}')
for name in sorted(required_10_3_tests):
    require(name in test_names, f'required Package 10.3 pgTAP suite exists: {name}')
required_11_1_migrations = {
    '20260724100400_1101_project_phases.sql',
    '20260724100500_1102_project_phase_functions.sql',
    '20260724100600_1103_project_phase_grants.sql',
}
required_11_1_tests = {
    '21_package_11_1_project_phases_schema.test.sql',
    '22_package_11_1_project_phases_security.test.sql',
    '23_package_11_1_project_phases_operations.test.sql',
}
for name in sorted(required_11_1_migrations):
    require(name in migration_names, f'required Package 11.1 migration exists: {name}')
for name in sorted(required_11_1_tests):
    require(name in test_names, f'required Package 11.1 pgTAP suite exists: {name}')
required_11_2_migrations = {
    '20260724100700_1104_project_milestones.sql',
    '20260724100800_1105_project_milestone_functions.sql',
    '20260724100900_1106_project_milestone_grants.sql',
}
required_11_2_tests = {
    '24_package_11_2_project_milestones_schema.test.sql',
    '25_package_11_2_project_milestones_security.test.sql',
    '26_package_11_2_project_milestones_operations.test.sql',
}
for name in sorted(required_11_2_migrations):
    require(name in migration_names, f'required Package 11.2 migration exists: {name}')
for name in sorted(required_11_2_tests):
    require(name in test_names, f'required Package 11.2 pgTAP suite exists: {name}')
required_11_3_migrations = {
    '20260724101000_1107_project_tasks.sql',
    '20260724101100_1108_project_task_functions.sql',
    '20260724101200_1109_project_task_grants.sql',
}
required_11_3_tests = {
    '27_package_11_3_project_tasks_schema.test.sql',
    '28_package_11_3_project_tasks_security.test.sql',
    '29_package_11_3_project_tasks_operations.test.sql',
}
for name in sorted(required_11_3_migrations):
    require(name in migration_names, f'required Package 11.3 migration exists: {name}')
for name in sorted(required_11_3_tests):
    require(name in test_names, f'required Package 11.3 pgTAP suite exists: {name}')
required_11_4_migrations = {
    '20260724101300_1110_task_assignments.sql',
    '20260724101400_1111_task_assignment_functions.sql',
    '20260724101500_1112_task_assignment_grants.sql',
}
required_11_4_tests = {
    '30_package_11_4_task_assignments_schema.test.sql',
    '31_package_11_4_task_assignments_security.test.sql',
    '32_package_11_4_task_assignments_operations.test.sql',
}
for name in sorted(required_11_4_migrations):
    require(name in migration_names, f'required Package 11.4 migration exists: {name}')
for name in sorted(required_11_4_tests):
    require(name in test_names, f'required Package 11.4 pgTAP suite exists: {name}')
required_11_5_migrations = {
    '20260724101600_1113_task_updates.sql',
    '20260724101700_1114_task_update_functions.sql',
    '20260724101800_1115_task_update_grants.sql',
}
required_11_5_tests = {
    '33_package_11_5_task_updates_schema.test.sql',
    '34_package_11_5_task_updates_security.test.sql',
    '35_package_11_5_task_updates_operations.test.sql',
}
for name in sorted(required_11_5_migrations):
    require(name in migration_names, f'required Package 11.5 migration exists: {name}')
for name in sorted(required_11_5_tests):
    require(name in test_names, f'required Package 11.5 pgTAP suite exists: {name}')
require([p.name for p in migrations] == sorted(p.name for p in migrations), 'migration names are ordered')

for path in migrations:
    try:
        parse_sql(path.read_text(encoding='utf-8'))
        passes.append(f'PostgreSQL syntax parsed: {path.name}')
    except Exception as exc:
        errors.append(f'PostgreSQL parse failed: {path.name}: {exc}')

assertion_pattern = re.compile(
    r'(?im)^\s*SELECT\s+'
    r'(?:has_schema|has_type|has_table|hasnt_table|has_column|has_index|columns_are|col_is_pk|fk_ok|'
    r'hasnt_column|col_type_is|col_default_is|has_function|has_sequence_privilege|function_lang_is|volatility_is|isnt|is|is_empty|ok|lives_ok|'
    r'throws_ok|results_eq)\s*\('
)
for path in tests:
    text = path.read_text(encoding='utf-8')
    try:
        parse_sql(text)
        passes.append(f'pgTAP SQL syntax parsed: {path.name}')
    except Exception as exc:
        errors.append(f'pgTAP parse failed: {path.name}: {exc}')
        continue

    plan_match = re.search(r'(?i)SELECT\s+plan\((\d+)\)', text)
    actual_assertions = len(assertion_pattern.findall(text))
    require(plan_match is not None, f'pgTAP plan exists: {path.name}')
    if plan_match is not None:
        require(int(plan_match.group(1)) == actual_assertions,
                f'pgTAP plan matches {actual_assertions} assertions: {path.name}')

all_sql = '\n'.join(p.read_text(encoding='utf-8').lower() for p in migrations)
for required in (
    'create table app.contractor_profiles',
    'create table app.users',
    'create table app.user_profiles',
    'create table app.roles',
    'create table app.user_roles',
):
    require(required in all_sql, f'required object present: {required}')

for prohibited in (
    'create table app.financial_transactions',
    'create table app.ledger_entries',
    'create table app.client_payments',
    'create table app.project_expenses',
):
    require(prohibited not in all_sql, f'prohibited Package 09.1 object absent: {prohibited}')

roles_sql = (ROOT / 'supabase/migrations/20260721220500_0905_predefined_roles.sql').read_text(encoding='utf-8')
for code in ('owner_admin', 'project_manager', 'accountant', 'site_supervisor', 'client'):
    require(code in roles_sql, f'approved role seeded: {code}')

require('purchasing' not in all_sql, 'Purchasing Staff role absent')
require('worker' not in all_sql, 'Worker account/role absent')
require('supplier' not in all_sql, 'Supplier account/role absent')
require('organization' not in all_sql and 'organisation' not in all_sql, 'multi-organisation schema absent')
require('app.last_active_owner' in all_sql, 'concurrency-safe last-owner guard present')
require('enable row level security' in all_sql, 'RLS enabled in default-deny migration')
require('create policy' not in all_sql, 'no application-facing policies added in Package 09.1')

with (ROOT / 'supabase/config.toml').open('rb') as fh:
    config = tomllib.load(fh)
passes.append('supabase/config.toml parsed')
api_config = config.get('api', {})
require('app' not in api_config.get('schemas', []),
        'app schema is not exposed through PostgREST schemas')
require('app' not in api_config.get('extra_search_path', []),
        'app schema is not exposed through PostgREST extra_search_path')
require(config.get('auth', {}).get('email', {}).get('otp_expiry') == 604800,
        'local Auth email OTP expiry is seven days')

current_account_path = ROOT / 'supabase/migrations/20260723092000_0909_public_current_account_rpc.sql'
current_account_sql = current_account_path.read_text(encoding='utf-8').lower()
for required in (
    'create or replace function public.current_account()',
    'stable',
    'security definer',
    "set search_path = ''",
    'from app.users',
    'from app.user_roles',
    'join app.roles',
    'left join app.user_profiles',
    'auth.uid()',
    'revoke all on function public.current_account() from public',
    'revoke all on function public.current_account() from anon',
    'grant execute on function public.current_account() to authenticated',
    'revoke usage on schema app from public, anon, authenticated',
    'revoke all on app.users from anon, authenticated',
    'revoke all on app.user_profiles from anon, authenticated',
    'revoke all on app.user_roles from anon, authenticated',
    'revoke all on app.roles from anon, authenticated',
):
    require(required in current_account_sql,
            f'current_account migration contains required clause: {required}')

first_release_current_account_path = ROOT / 'supabase/migrations/20260724094000_0910_first_release_current_account_access.sql'
if first_release_current_account_path.exists():
    first_release_current_account_sql = first_release_current_account_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function public.current_account()',
        'stable',
        'security definer',
        "set search_path = ''",
        "array['owner_admin']::varchar(40)[]",
        "array['client']::varchar(40)[]",
        "'project_manager'",
        "'accountant'",
        "'site_supervisor'",
        'revoke all on function public.current_account() from public',
        'grant execute on function public.current_account() to authenticated',
    ):
        require(required in first_release_current_account_sql,
                f'0910 current_account replacement contains required clause: {required}')

activity_log_path = ROOT / 'supabase/migrations/20260724094100_0911_central_activity_logs.sql'
if activity_log_path.exists():
    activity_log_sql = activity_log_path.read_text(encoding='utf-8').lower()
    for required in (
        'create table app.activity_logs',
        'actor_user_id uuid',
        'actor_auth_subject uuid',
        'effective_role_code varchar(40)',
        'project_id uuid',
        'previous_values jsonb',
        'new_values jsonb',
        'metadata jsonb',
        'foreign key (actor_user_id) references app.users(id) on delete restrict',
        'foreign key (effective_role_code) references app.roles(code) on delete restrict',
        'create or replace function app.mask_audit_json',
        'create or replace function app.write_activity_log',
        'before update on app.activity_logs',
        'before delete on app.activity_logs',
        'before truncate on app.activity_logs',
        'alter table app.activity_logs enable row level security',
        'alter table app.activity_logs force row level security',
        'revoke all on app.activity_logs from public, anon, authenticated',
        'revoke all on function app.mask_audit_json(jsonb) from public',
        'revoke all on function app.write_activity_log',
    ):
        require(required in activity_log_sql,
                f'0911 activity log migration contains required clause: {required}')
    require('foreign key (project_id)' not in activity_log_sql,
            '0911 does not add Stage 09 project_id foreign key')

invitation_path = ROOT / 'supabase/migrations/20260724094200_0912_client_user_invitations.sql'
if invitation_path.exists():
    invitation_sql = invitation_path.read_text(encoding='utf-8').lower()
    for required in (
        'create table app.user_invitations',
        'invited_user_id uuid not null',
        'token_hash bytea not null',
        'status varchar(20) not null',
        'expires_at timestamptz not null',
        'accepted_at timestamptz',
        'revoked_at timestamptz',
        'revoked_by uuid',
        'revoke_reason text',
        'invited_by uuid not null',
        'created_at timestamptz not null default now()',
        'resent_from_invitation_id uuid',
        'version_number integer not null default 1',
        'foreign key (invited_user_id) references app.users(id) on delete restrict',
        'foreign key (invited_by) references app.users(id) on delete restrict',
        "status in ('pending', 'accepted', 'revoked', 'expired')",
        'octet_length(token_hash) = 32',
        "expires_at = created_at + interval '7 days'",
        'on app.user_invitations(token_hash)',
        'where status = \'pending\'',
        'alter table app.user_invitations enable row level security',
        'alter table app.user_invitations force row level security',
        'revoke all on app.user_invitations from public, anon, authenticated',
    ):
        require(required in invitation_sql,
                f'0912 invitation migration contains required clause: {required}')
    for prohibited in (' email ', ' auth_subject ', 'plaintext_token', 'application_user_id'):
        require(prohibited not in invitation_sql,
                f'0912 invitation migration omits prohibited duplicate column/token: {prohibited.strip()}')

private_functions_path = ROOT / 'supabase/migrations/20260724095000_0913_identity_mutation_private_functions.sql'
if private_functions_path.exists():
    private_sql = private_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.require_active_owner_admin',
        'stable',
        'create or replace function app.record_denied_privileged_operation',
        'p_reason_code varchar(40)',
        "p_action !~ '^[a-z][a-z0-9_]{0,119}$'",
        "p_entity_type !~ '^[a-z][a-z0-9_]{0,79}$'",
        "'authorization_denied'",
        "'inactive_actor'",
        "'insufficient_role'",
        "'invalid_actor_type'",
        "'invalid_target_state'",
        'create or replace function app.create_client_invitation',
        'create or replace function app.resend_client_invitation',
        'create or replace function app.revoke_client_invitation',
        'create or replace function app.accept_client_invitation',
        'create or replace function app.suspend_client_account',
        'create or replace function app.reactivate_client_account',
        'create or replace function app.disable_client_account',
        'create or replace function app.bootstrap_first_owner',
        'p_owner_full_name text',
        'create or replace function app.activate_current_invited_owner',
        'security definer',
        "set search_path = ''",
        'volatile',
        "pg_advisory_xact_lock(hashtextextended('app.first_owner_bootstrap'",
        'for update',
        'app.write_activity_log',
        "set_config('app.allow_owner_bootstrap', 'on', true)",
        'where i.id = p_invitation_id',
        'where u.id = invite_row.invited_user_id',
        "invited_row.user_type <> 'client'",
        "invited_row.status <> 'invited'",
        'invited_row.is_active',
        'invite_row.accepted_at is not null',
        'invite_row.revoked_at is not null',
    ):
        require(required in private_sql,
                f'0913 private mutation migration contains required clause: {required}')
    for prohibited in (
        'disable trigger',
        'drop trigger',
        "role_code = 'project_manager' and",
        "role_code = 'accountant' and",
        "role_code = 'site_supervisor' and",
    ):
        require(prohibited not in private_sql,
                f'0913 avoids prohibited trigger/reserved-role pattern: {prohibited}')
    require(not re.search(r'(?im)^\s*delete\s+from\s+app\.', private_sql),
            '0913 performs no hard deletes from app tables')

gateways_path = ROOT / 'supabase/migrations/20260724095100_0914_identity_mutation_public_gateways.sql'
if gateways_path.exists():
    gateways_sql = gateways_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function public.server_create_client_invitation',
        'create or replace function public.server_resend_client_invitation',
        'create or replace function public.server_revoke_client_invitation',
        'create or replace function public.server_accept_client_invitation',
        'create or replace function public.server_suspend_client_account',
        'create or replace function public.server_reactivate_client_account',
        'create or replace function public.server_disable_client_account',
        'create or replace function public.server_bootstrap_first_owner',
        'p_owner_full_name text',
        'create or replace function public.server_record_denied_privileged_operation',
        'p_reason_code varchar(40)',
        'create or replace function public.activate_current_invited_owner()',
        'volatile',
        'security definer',
        "set search_path = ''",
    ):
        require(required in gateways_sql,
                f'0914 gateway migration contains required clause: {required}')

grants_path = ROOT / 'supabase/migrations/20260724095200_0915_identity_mutation_security_grants.sql'
if grants_path.exists():
    grants_sql = grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on function app.create_client_invitation',
        'from public, anon, authenticated, service_role',
        'grant execute on function public.server_create_client_invitation',
        'to service_role',
        'grant execute on function public.server_record_denied_privileged_operation',
        'public.server_record_denied_privileged_operation(uuid, varchar, varchar, uuid, varchar, text, text, text, inet, jsonb)',
        'grant execute on function public.activate_current_invited_owner() to authenticated',
    ):
        require(required in grants_sql,
                f'0915 grants migration contains required clause: {required}')
    require('grant execute on function app.' not in grants_sql,
            '0915 does not grant private app functions')

service_context_path = ROOT / 'supabase/migrations/20260724095300_0916_identity_service_lookup_context.sql'
if service_context_path.exists():
    service_context_sql = service_context_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.client_identity_context_for_service',
        'returns table',
        'client_user_id uuid',
        'auth_subject uuid',
        'normalized_email text',
        'account_status text',
        'is_active boolean',
        'latest_invitation_id uuid',
        'latest_invitation_status text',
        'language sql',
        'stable',
        'security definer',
        "set search_path = ''",
        'app.require_active_owner_admin',
        "u.user_type = 'client'",
        'order by ui.created_at desc, ui.id desc',
        'create or replace function public.server_client_identity_context',
        'from app.client_identity_context_for_service',
        'revoke all on function app.client_identity_context_for_service(uuid, uuid) from public, anon, authenticated, service_role',
        'revoke all on function public.server_client_identity_context(uuid, uuid) from public, anon, authenticated',
        'grant execute on function public.server_client_identity_context(uuid, uuid) to service_role',
    ):
        require(required in service_context_sql,
                f'0916 service context migration contains required clause: {required}')
    for prohibited in (
        'app.user_profiles',
        'app.activity_logs',
        'grant execute on function app.client_identity_context_for_service',
        'grant select on app.',
        'create policy',
    ):
        require(prohibited not in service_context_sql,
                f'0916 service context omits prohibited exposure/grant: {prohibited}')

first_owner_delivery_context_path = ROOT / 'supabase/migrations/20260724095400_0917_first_owner_delivery_recovery_context.sql'
if first_owner_delivery_context_path.exists():
    delivery_sql = first_owner_delivery_context_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.first_owner_delivery_context_for_service',
        'p_owner_auth_subject uuid',
        'p_normalized_email citext',
        'returns table',
        'owner_user_id uuid',
        'auth_subject uuid',
        'normalized_email text',
        'account_status text',
        'is_active boolean',
        'invitation_id uuid',
        'invitation_status text',
        'expires_at timestamptz',
        'stable',
        'security definer',
        "set search_path = ''",
        "u.user_type = 'staff'",
        "u.status = 'invited'",
        'not u.is_active',
        "ur.role_code = 'owner_admin'",
        'ur.is_active',
        "latest_invitation.status = 'pending'",
        'latest_invitation.expires_at > now()',
        'order by ui.created_at desc, ui.id desc',
        'create or replace function public.server_first_owner_delivery_context',
        'from app.first_owner_delivery_context_for_service',
        'revoke all on function app.first_owner_delivery_context_for_service(uuid, citext) from public, anon, authenticated, service_role',
        'revoke all on function public.server_first_owner_delivery_context(uuid, citext) from public, anon, authenticated',
        'grant execute on function public.server_first_owner_delivery_context(uuid, citext) to service_role',
    ):
        require(required in delivery_sql,
                f'0917 delivery recovery migration contains required clause: {required}')
    for prohibited in (
        'grant select on app.',
        'create policy',
        'app.activity_logs',
        'full_name text',
        'role_history',
    ):
        require(prohibited not in delivery_sql,
                f'0917 delivery recovery omits prohibited exposure/grant: {prohibited}')

client_schema_path = ROOT / 'supabase/migrations/20260724095500_1001_client_business_records.sql'
client_functions_path = ROOT / 'supabase/migrations/20260724095600_1002_client_business_record_functions.sql'
client_grants_path = ROOT / 'supabase/migrations/20260724095700_1003_client_business_record_grants.sql'
if client_schema_path.exists():
    client_schema_sql = client_schema_path.read_text(encoding='utf-8').lower()
    for required in (
        'create sequence app.client_number_seq',
        'start with 1',
        'increment by 1',
        'minvalue 1',
        'maxvalue 999999',
        'no cycle',
        "create type app.client_record_status as enum ('active', 'inactive')",
        'create table app.clients',
        "default ('cl-' || lpad(nextval('app.client_number_seq')::text, 6, '0'))",
        'constraint clients_client_number_uk unique (client_number)',
        'constraint clients_portal_user_uk unique (portal_user_id)',
        "client_number ~ '^cl-[0-9]{6}$'",
        'alter table app.clients enable row level security',
        'alter table app.clients force row level security',
        'create or replace function app.prevent_client_delete',
        'create or replace function app.clients_trusted_update_guard',
        'new.client_number is distinct from old.client_number',
        'new.version_number := old.version_number + 1',
        'before delete on app.clients',
        'before update on app.clients',
        'revoke all on app.clients from public, anon, authenticated',
        'revoke all on sequence app.client_number_seq from public, anon, authenticated, service_role',
    ):
        require(required in client_schema_sql,
                f'1001 client schema migration contains required clause: {required}')
    approved_client_columns = [
        'id', 'client_number', 'portal_user_id', 'display_name', 'legal_name', 'email',
        'phone', 'address', 'status', 'internal_notes', 'is_active', 'archived_at',
        'archived_by', 'created_at', 'created_by', 'updated_at', 'updated_by',
        'version_number',
    ]
    for column in approved_client_columns:
        require(re.search(rf'(?m)^\s*{column}\s+', client_schema_sql) is not None,
                f'1001 app.clients approved column exists: {column}')
    for forbidden in (
        'client_type',
        'country_of_residence',
        'time_zone',
        'whatsapp_number',
        'preferred_currency_code',
        'archive_reason',
        'total_paid',
        'outstanding_amount',
        'identification_document',
        'editable_balance',
        'max(',
    ):
        require(forbidden not in client_schema_sql,
                f'1001 app.clients omits forbidden field/pattern: {forbidden}')
    require(client_schema_sql.count('unique (portal_user_id)') == 1,
            '1001 has exactly one portal_user_id uniqueness declaration')
if client_functions_path.exists():
    client_functions_sql = client_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.create_client_record',
        'create or replace function app.update_client_record',
        'create or replace function app.link_client_portal_user',
        'create or replace function app.unlink_client_portal_user',
        'create or replace function app.archive_client_record',
        'create or replace function app.owner_client_record_detail',
        'create or replace function app.owner_client_record_list',
        'create or replace function app.current_client_record_for_authenticated_user',
        'create or replace function public.current_client_record()',
        'create or replace function public.server_create_client_record',
        'create or replace function public.server_update_client_record',
        'create or replace function public.server_link_client_portal_user',
        'create or replace function public.server_unlink_client_portal_user',
        'create or replace function public.server_archive_client_record',
        'create or replace function public.server_owner_client_record_detail',
        'create or replace function public.server_owner_client_record_list',
        'security definer',
        "set search_path = ''",
        'app.require_active_owner_admin',
        "u.user_type = 'client'",
        "u.status = 'active'",
        "ur.role_code = 'client'",
        'r.is_staff_role',
        "c.status = 'active'",
        'c.archived_at is null',
        'auth.uid()',
        'p_expected_version_number',
        'client record version conflict',
        'portal_user_id = null',
        "client_record_created",
        "client_record_updated",
        "client_portal_user_linked",
        "client_portal_user_unlinked",
        "client_portal_user_replaced",
        "client_record_archived",
        "'[masked]'",
    ):
        require(required in client_functions_sql,
                f'1002 client function migration contains required clause: {required}')
    for forbidden in (
        'delete from app.clients',
        'drop table',
        'disable trigger',
        'execute ',
        'format(',
        'internal_notes' + ', portal_user_id',
    ):
        require(forbidden not in client_functions_sql,
                f'1002 avoids prohibited dynamic/destructive/exposure pattern: {forbidden}')
    public_self_read_match = re.search(
        r'create or replace function public\.current_client_record\(\).*?returns table \((.*?)\)',
        client_functions_sql,
        re.S,
    )
    if public_self_read_match:
        public_self_fields = public_self_read_match.group(1)
        for safe_field in ('id uuid', 'client_number text', 'display_name text', 'legal_name text', 'email text', 'phone text', 'address text', 'status text'):
            require(safe_field in public_self_fields,
                    f'public.current_client_record returns safe field: {safe_field}')
        for forbidden_field in ('internal_notes', 'portal_user_id', 'created_by', 'updated_by', 'archived_by'):
            require(forbidden_field not in public_self_fields,
                    f'public.current_client_record omits private field: {forbidden_field}')
if client_grants_path.exists():
    client_grants_sql = client_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.clients from public, anon, authenticated, service_role',
        'revoke all on sequence app.client_number_seq from public, anon, authenticated, service_role',
        'revoke all on function app.create_client_record',
        'from public, anon, authenticated, service_role',
        'revoke all on function public.current_client_record() from public, anon, service_role',
        'grant execute on function public.current_client_record() to authenticated',
        'grant execute on function public.server_create_client_record',
        'grant execute on function public.server_update_client_record',
        'grant execute on function public.server_link_client_portal_user',
        'grant execute on function public.server_unlink_client_portal_user',
        'grant execute on function public.server_archive_client_record',
        'grant execute on function public.server_owner_client_record_detail',
        'grant execute on function public.server_owner_client_record_list',
        'to service_role',
    ):
        require(required in client_grants_sql,
                f'1003 client grants migration contains required clause: {required}')
    require('grant select on app.clients' not in client_grants_sql, '1003 grants no direct clients table SELECT')
    require('grant insert on app.clients' not in client_grants_sql, '1003 grants no direct clients table INSERT')
    require('grant update on app.clients' not in client_grants_sql, '1003 grants no direct clients table UPDATE')
    require('grant delete on app.clients' not in client_grants_sql, '1003 grants no direct clients table DELETE')

project_schema_path = ROOT / 'supabase/migrations/20260724095800_1004_project_business_records.sql'
project_functions_path = ROOT / 'supabase/migrations/20260724095900_1005_project_business_record_functions.sql'
project_grants_path = ROOT / 'supabase/migrations/20260724100000_1006_project_business_record_grants.sql'
if project_schema_path.exists():
    project_schema_sql = project_schema_path.read_text(encoding='utf-8').lower()
    for required in (
        'create type app.project_record_status as enum',
        "'draft'",
        "'quotation'",
        "'approved'",
        "'active'",
        "'on_hold'",
        "'completed'",
        "'cancelled'",
        "'archived'",
        'create table app.project_number_counters',
        'project_year integer primary key',
        'last_value integer not null',
        'last_value between 1 and 9999',
        'create or replace function app.generate_project_number()',
        'from app.contractor_profiles',
        'cp.time_zone',
        'at time zone contractor_time_zone',
        'on conflict (project_year)',
        'last_value = app.project_number_counters.last_value + 1',
        'last_value < 9999',
        "return ('prj-' || resolved_year::text || '-' || lpad(allocated_value::text, 4, '0'))",
        'create table app.projects',
        'project_number public.citext not null default app.generate_project_number()',
        'numeric(20,6)',
        'constraint projects_project_number_uk unique (project_number)',
        "project_number::text ~ '^prj-[0-9]{4}-[0-9]{4}$'",
        'foreign key (client_id) references app.clients(id) on delete restrict',
        'foreign key (contract_currency_code) references app.currencies(code) on delete restrict',
        'foreign key (budget_currency_code) references app.currencies(code) on delete restrict',
        'foreign key (reporting_currency_code) references app.currencies(code) on delete restrict',
        'contract_amount >= 0',
        'budget_amount >= 0',
        'status in (',
        'new.project_number is distinct from old.project_number',
        'app.allow_project_status_change',
        'app.allow_project_client_change',
        'new.version_number := old.version_number + 1',
        'before delete on app.projects',
        'alter table app.projects enable row level security',
        'alter table app.projects force row level security',
        'alter table app.project_number_counters enable row level security',
        'alter table app.project_number_counters force row level security',
    ):
        require(required in project_schema_sql,
                f'1004 Project schema migration contains required clause: {required}')
    approved_project_columns = [
        'id', 'project_number', 'client_id', 'name', 'project_type', 'location',
        'status', 'start_date', 'end_date', 'contract_amount',
        'contract_currency_code', 'budget_amount', 'budget_currency_code',
        'reporting_currency_code', 'client_visible_summary', 'internal_notes',
        'completed_at', 'cancelled_at', 'cancellation_reason', 'archived_at',
        'archived_by', 'created_at', 'created_by', 'updated_at', 'updated_by',
        'version_number',
    ]
    for column in approved_project_columns:
        require(re.search(rf'(?m)^\s*{column}\s+', project_schema_sql) is not None,
                f'1004 app.projects approved column exists: {column}')
    for forbidden in (
        'is_active',
        'completion_percent',
        'current_balance',
        'total_paid',
        'total_expenses',
        'outstanding_amount',
        'assigned_project_manager_id',
        'assigned_supervisor_id',
        'ledger_entries',
        'financial_transactions',
        'exchange_rate',
        'max(',
    ):
        require(forbidden not in project_schema_sql,
                f'1004 Project schema omits forbidden field/table/pattern: {forbidden}')
if project_functions_path.exists():
    project_functions_sql = project_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.create_project_record',
        'create or replace function app.update_project_record',
        'create or replace function app.change_project_client',
        'create or replace function app.change_project_status',
        'create or replace function app.complete_project_record',
        'create or replace function app.cancel_project_record',
        'create or replace function app.archive_project_record',
        'create or replace function app.owner_project_record_detail',
        'create or replace function app.owner_project_record_list',
        'create or replace function app.current_client_project_records_for_authenticated_user',
        'create or replace function app.current_client_project_record_for_authenticated_user',
        'create or replace function public.current_client_project_records',
        'create or replace function public.current_client_project_record',
        'create or replace function public.server_create_project_record',
        'create or replace function public.server_change_project_client',
        'security definer',
        "set search_path = ''",
        'app.require_active_owner_admin',
        'app.require_active_client_record',
        "existing_row.status not in ('draft', 'quotation', 'approved')",
        "'draft'::app.project_record_status, 'quotation'::app.project_record_status",
        "'completed'::app.project_record_status, 'archived'::app.project_record_status",
        "'cancelled'::app.project_record_status, 'archived'::app.project_record_status",
        'project terminal transitions require dedicated functions',
        'auth.uid()',
        'p.client_id = c.id',
        'project_record_created',
        'project_record_updated',
        'project_client_changed',
        'project_status_changed',
        'project_completed',
        'project_cancelled',
        'project_archived',
        "'[masked]'",
        'future_dependent_record_guard_required',
    ):
        require(required in project_functions_sql,
                f'1005 Project function migration contains required clause: {required}')
    public_project_list_match = re.search(
        r'create or replace function public\.current_client_project_records\(.*?returns table \((.*?)\)\s+language',
        project_functions_sql,
        re.S,
    )
    if public_project_list_match:
        public_fields = public_project_list_match.group(1)
        for safe_field in ('id uuid', 'project_number text', 'name text', 'project_type text', 'location text', 'status text', 'start_date date', 'end_date date', 'reporting_currency_code char(3)', 'client_visible_summary text'):
            require(safe_field in public_fields,
                    f'public.current_client_project_records returns safe field: {safe_field}')
        for forbidden_field in ('contract_amount', 'contract_currency_code', 'budget_amount', 'budget_currency_code', 'internal_notes', 'cancellation_reason', 'created_by', 'updated_by', 'archived_by'):
            require(forbidden_field not in public_fields,
                    f'public.current_client_project_records omits private field: {forbidden_field}')
    for forbidden in (
        'delete from app.projects',
        'assigned_project_manager',
        'assigned_supervisor',
        'ledger_entries',
        'financial_transactions',
        'format(',
        'execute ',
    ):
        require(forbidden not in project_functions_sql,
                f'1005 Project functions omit prohibited pattern: {forbidden}')
if project_grants_path.exists():
    project_grants_sql = project_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.projects from public, anon, authenticated, service_role',
        'revoke all on app.project_number_counters from public, anon, authenticated, service_role',
        'revoke all on function app.generate_project_number() from public, anon, authenticated, service_role',
        'revoke all on function app.create_project_record',
        'from public, anon, authenticated, service_role',
        'grant execute on function public.current_client_project_records',
        'to authenticated',
        'grant execute on function public.server_create_project_record',
        'grant execute on function public.server_change_project_client',
        'grant execute on function public.server_owner_project_record_list',
        'to service_role',
    ):
        require(required in project_grants_sql,
                f'1006 Project grants migration contains required clause: {required}')
    require('grant select on app.projects' not in project_grants_sql, '1006 grants no direct Project table SELECT')
    require('grant insert on app.projects' not in project_grants_sql, '1006 grants no direct Project table INSERT')
    require('grant update on app.projects' not in project_grants_sql, '1006 grants no direct Project table UPDATE')
    require('grant delete on app.projects' not in project_grants_sql, '1006 grants no direct Project table DELETE')

assignment_schema_path = ROOT / 'supabase/migrations/20260724100100_1007_project_staff_assignments.sql'
assignment_functions_path = ROOT / 'supabase/migrations/20260724100200_1008_project_staff_assignment_functions.sql'
assignment_grants_path = ROOT / 'supabase/migrations/20260724100300_1009_project_staff_assignment_grants.sql'
if assignment_schema_path.exists():
    assignment_schema_sql = assignment_schema_path.read_text(encoding='utf-8').lower()
    for required in (
        'create type app.project_staff_assignment_status as enum',
        "'active'",
        "'removed'",
        'create table app.project_staff_assignments',
        'id uuid primary key default gen_random_uuid()',
        'project_id uuid not null',
        'user_id uuid not null',
        'assignment_role_code varchar(40) not null',
        'status app.project_staff_assignment_status not null default',
        'assigned_at timestamptz not null default now()',
        'assigned_by uuid not null',
        'removed_at timestamptz',
        'removed_by uuid',
        'notes text',
        'foreign key (project_id) references app.projects(id) on delete restrict',
        'foreign key (user_id) references app.users(id) on delete restrict',
        'foreign key (assignment_role_code) references app.roles(code) on delete restrict',
        "assignment_role_code in ('project_manager', 'site_supervisor')",
        'length(btrim(notes)) <= 4000',
        "status = 'active'",
        "status = 'removed'",
        'create unique index project_staff_assignments_one_active_idx',
        'where status = \'active\'',
        'before delete on app.project_staff_assignments',
        'before update on app.project_staff_assignments',
        'alter table app.project_staff_assignments enable row level security',
        'alter table app.project_staff_assignments force row level security',
        'revoke all on app.project_staff_assignments from public, anon, authenticated, service_role',
    ):
        require(required in assignment_schema_sql,
                f'1007 assignment schema migration contains required clause: {required}')
    approved_assignment_columns = [
        'id', 'project_id', 'user_id', 'assignment_role_code', 'status',
        'assigned_at', 'assigned_by', 'removed_at', 'removed_by', 'notes',
    ]
    for column in approved_assignment_columns:
        require(re.search(rf'(?m)^\s*{column}\s+', assignment_schema_sql) is not None,
                f'1007 app.project_staff_assignments approved column exists: {column}')
    for forbidden in (
        'client_id',
        'phase_id',
        'milestone_id',
        'task_id',
        'permission_flags',
        'financial_flags',
        'is_project_owner',
        'version_number',
        'created_at',
        'created_by',
        'updated_at',
        'updated_by',
        'removal_reason',
        'deleted_at',
        'archived_at',
        "'accountant'",
        "'owner_admin'",
        "'client'",
        'delete from app.project_staff_assignments',
    ):
        require(forbidden not in assignment_schema_sql,
                f'1007 assignment schema omits forbidden field/pattern: {forbidden}')
if assignment_functions_path.exists():
    assignment_functions_sql = assignment_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.create_project_staff_assignment',
        'create or replace function app.remove_project_staff_assignment',
        'create or replace function app.owner_project_staff_assignment_list',
        'create or replace function app.owner_project_staff_assignment_detail',
        'create or replace function app.owner_eligible_project_staff_list',
        'create or replace function app.has_active_project_assignment',
        'create or replace function app.has_active_project_assignment_role',
        'create or replace function public.server_create_project_staff_assignment',
        'create or replace function public.server_remove_project_staff_assignment',
        'create or replace function public.server_owner_project_staff_assignment_list',
        'create or replace function public.server_owner_project_staff_assignment_detail',
        'create or replace function public.server_owner_eligible_project_staff_list',
        'security definer',
        "set search_path = ''",
        'app.require_active_owner_admin',
        "p_assignment_role_code not in ('project_manager', 'site_supervisor')",
        "u.user_type = 'staff'",
        "u.status = 'active'",
        'u.is_active',
        'ur.is_active',
        "project_row.status not in ('draft', 'quotation', 'approved', 'active', 'on_hold')",
        'project staff assignment already exists',
        'app.allow_project_staff_assignment_removal',
        'project_staff_assignment_created',
        'project_staff_assignment_removed',
        "'[masked]'",
        "existing_row.status not in ('draft', 'quotation', 'approved')",
        'project client cannot be changed after staff assignment history exists',
        "psa.status = 'active'",
        'project cannot be archived while active staff assignments exist',
    ):
        require(required in assignment_functions_sql,
                f'1008 assignment functions migration contains required clause: {required}')
    for forbidden in (
        'delete from app.project_staff_assignments',
        'insert into app.user_roles',
        'update app.user_roles',
        'create or replace function public.current_staff_project',
        'create or replace function public.current_project_manager_project',
        'create or replace function public.current_site_supervisor_project',
        'execute ',
        'format(',
        'raw_app_meta_data',
        'staff email',
    ):
        require(forbidden not in assignment_functions_sql,
                f'1008 assignment functions omit prohibited pattern: {forbidden}')
if assignment_grants_path.exists():
    assignment_grants_sql = assignment_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.project_staff_assignments from public, anon, authenticated, service_role',
        'revoke all on function app.create_project_staff_assignment',
        'revoke all on function app.has_active_project_assignment',
        'from public, anon, authenticated, service_role',
        'grant execute on function public.server_create_project_staff_assignment',
        'grant execute on function public.server_remove_project_staff_assignment',
        'grant execute on function public.server_owner_project_staff_assignment_list',
        'grant execute on function public.server_owner_project_staff_assignment_detail',
        'grant execute on function public.server_owner_eligible_project_staff_list',
        'to service_role',
    ):
        require(required in assignment_grants_sql,
                f'1009 assignment grants migration contains required clause: {required}')
    for forbidden in (
        'grant select on app.project_staff_assignments',
        'grant insert on app.project_staff_assignments',
        'grant update on app.project_staff_assignments',
        'grant delete on app.project_staff_assignments',
        'to authenticated',
        'to anon',
    ):
        require(forbidden not in assignment_grants_sql,
                f'1009 assignment grants omit prohibited grant: {forbidden}')

if first_release_current_account_path.exists():
    current_account_10_3_sql = first_release_current_account_path.read_text(encoding='utf-8').lower()
    require("then array['owner_admin']::varchar(40)[]" in current_account_10_3_sql,
            '10.3 preserves owner_admin as usable staff role')
    require("then array['client']::varchar(40)[]" in current_account_10_3_sql,
            '10.3 preserves client as usable client role')
    require("then array['project_manager']" not in current_account_10_3_sql
            and "then array['site_supervisor']" not in current_account_10_3_sql
            and "then array['accountant']" not in current_account_10_3_sql,
            '10.3 does not activate reserved roles in current_account')
require('create policy' not in all_sql, '10.3 adds no broad application-facing policies')
phase_schema_path = ROOT / 'supabase/migrations/20260724100400_1101_project_phases.sql'
phase_functions_path = ROOT / 'supabase/migrations/20260724100500_1102_project_phase_functions.sql'
phase_grants_path = ROOT / 'supabase/migrations/20260724100600_1103_project_phase_grants.sql'
if phase_schema_path.exists():
    phase_schema_sql = phase_schema_path.read_text(encoding='utf-8').lower()
    for required in (
        'create table app.project_phases',
        'id uuid primary key default gen_random_uuid()',
        'project_id uuid not null',
        'name varchar(160) not null',
        'description text',
        'sequence_no integer not null',
        'client_visible boolean not null default true',
        'is_active boolean not null default true',
        'version_number integer not null default 1',
        'foreign key (project_id) references app.projects(id) on delete restrict',
        'foreign key (created_by) references app.users(id) on delete restrict',
        'foreign key (updated_by) references app.users(id) on delete restrict',
        'unique (project_id, sequence_no)',
        'deferrable initially immediate',
        'btrim(name) <>',
        'length(btrim(description)) <= 4000',
        'sequence_no > 0',
        'start_date <= end_date',
        'version_number >= 1',
        'before delete on app.project_phases',
        'before update on app.project_phases',
        'alter table app.project_phases enable row level security',
        'alter table app.project_phases force row level security',
        'revoke all on app.project_phases from public, anon, authenticated, service_role',
    ):
        require(required in phase_schema_sql,
                f'1101 phase schema migration contains required clause: {required}')
    approved_phase_columns = [
        'id', 'project_id', 'name', 'description', 'sequence_no', 'start_date', 'end_date',
        'client_visible', 'is_active', 'created_at', 'created_by', 'updated_at', 'updated_by',
        'version_number',
    ]
    for column in approved_phase_columns:
        require(re.search(rf'(?m)^\s*{column}\s+', phase_schema_sql) is not None,
                f'1101 app.project_phases approved column exists: {column}')
    for forbidden in (
        'completion_percent',
        'weight_percent',
        'milestone_count',
        'task_count',
        'completed_at',
        'archived_at',
        'archived_by',
        'phase_number',
        'colour',
        'template_id',
        'delete from app.project_phases',
    ):
        require(forbidden not in phase_schema_sql,
                f'1101 phase schema omits forbidden field/pattern: {forbidden}')
    require('status ' not in re.sub(r'project_record_status|status =|status <>|status not', '', phase_schema_sql),
            '1101 phase schema omits phase status column')
if phase_functions_path.exists():
    phase_functions_sql = phase_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.create_project_phase',
        'create or replace function app.update_project_phase',
        'create or replace function app.reorder_project_phases',
        'create or replace function app.archive_project_phase',
        'create or replace function app.owner_project_phase_list',
        'create or replace function app.owner_project_phase_detail',
        'create or replace function app.current_client_project_phases_for_authenticated_user',
        'create or replace function app.current_client_project_phase_for_authenticated_user',
        'create or replace function public.current_client_project_phases',
        'create or replace function public.current_client_project_phase',
        'create or replace function public.server_create_project_phase',
        'create or replace function public.server_update_project_phase',
        'create or replace function public.server_reorder_project_phases',
        'create or replace function public.server_archive_project_phase',
        'create or replace function public.server_owner_project_phase_list',
        'create or replace function public.server_owner_project_phase_detail',
        'security definer',
        "set search_path = ''",
        'app.require_active_owner_admin',
        "p_project.status not in ('draft', 'quotation', 'approved', 'active', 'on_hold')",
        "project_row.status = 'archived'",
        'p_ordered_phase_ids uuid[]',
        'p_expected_version_numbers integer[]',
        'project phase order version conflict',
        'app.allow_project_phase_ordering_maintenance',
        'app.allow_project_phase_archive',
        'project client cannot be changed after phase history exists',
        'project_phase_created',
        'project_phase_updated',
        'project_phases_reordered',
        'project_phase_archived',
        "'[masked]'",
    ):
        require(required in phase_functions_sql,
                f'1102 phase functions migration contains required clause: {required}')
    safe_phase_return = re.search(
        r'create or replace function public\.current_client_project_phases\(.*?returns table \((.*?)\)\s+language',
        phase_functions_sql,
        re.S,
    )
    require(safe_phase_return is not None, '1102 public.current_client_project_phases return shape is inspectable')
    if safe_phase_return:
        returned = safe_phase_return.group(1)
        for safe_field in ('id uuid', 'project_id uuid', 'name text', 'description text', 'sequence_no integer', 'start_date date', 'end_date date'):
            require(safe_field in returned, f'1102 Client phase read returns safe field: {safe_field}')
        for forbidden_field in ('is_active', 'client_visible', 'created_by', 'updated_by', 'version_number'):
            require(forbidden_field not in returned, f'1102 Client phase read omits private field: {forbidden_field}')
    for forbidden in (
        'create or replace function public.current_staff_project_phase',
        'create or replace function public.current_project_manager_project_phase',
        'create or replace function public.current_site_supervisor_project_phase',
        'execute ',
        'format(',
        'raw_app_meta_data',
        'full description',
    ):
        require(forbidden not in phase_functions_sql,
                f'1102 phase functions omit prohibited pattern: {forbidden}')
if phase_grants_path.exists():
    phase_grants_sql = phase_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.project_phases from public, anon, authenticated, service_role',
        'revoke all on function app.create_project_phase',
        'revoke all on function app.reorder_project_phases',
        'from public, anon, authenticated, service_role',
        'grant execute on function public.current_client_project_phases',
        'to authenticated',
        'grant execute on function public.server_create_project_phase',
        'grant execute on function public.server_reorder_project_phases',
        'grant execute on function public.server_owner_project_phase_list',
        'to service_role',
    ):
        require(required in phase_grants_sql,
                f'1103 phase grants migration contains required clause: {required}')
    for forbidden in (
        'grant select on app.project_phases',
        'grant insert on app.project_phases',
        'grant update on app.project_phases',
        'grant delete on app.project_phases',
        'current_staff_project_phase',
        'current_project_manager_project_phase',
        'current_site_supervisor_project_phase',
    ):
        require(forbidden not in phase_grants_sql,
                f'1103 phase grants omit prohibited grant: {forbidden}')

milestone_schema_path = ROOT / 'supabase/migrations/20260724100700_1104_project_milestones.sql'
milestone_functions_path = ROOT / 'supabase/migrations/20260724100800_1105_project_milestone_functions.sql'
milestone_grants_path = ROOT / 'supabase/migrations/20260724100900_1106_project_milestone_grants.sql'
if milestone_schema_path.exists():
    milestone_schema_sql = milestone_schema_path.read_text(encoding='utf-8').lower()
    require('create table app.project_milestones' in milestone_schema_sql, '1104 creates milestone table')
    require('enable row level security' in milestone_schema_sql, '1104 enables milestone RLS')
    require('force row level security' in milestone_schema_sql, '1104 forces milestone RLS')
    require('before delete on app.project_milestones' in milestone_schema_sql, '1104 prevents milestone hard deletion')
    require('project_milestones_validate_relationships' in milestone_schema_sql, '1104 validates same-Project phase and due dates')
    require('project_milestones_trusted_update_guard' in milestone_schema_sql, '1104 adds trusted milestone update guard')
    for column in (
        'id',
        'project_id',
        'phase_id',
        'name',
        'description',
        'due_date',
        'completed_at',
        'client_visible',
        'is_active',
        'created_at',
        'created_by',
        'updated_at',
        'updated_by',
        'version_number',
    ):
        require(re.search(rf'\b{column}\b', milestone_schema_sql) is not None,
                f'1104 milestone schema contains exact field: {column}')
    for required in (
        'name varchar(160) not null',
        'description text',
        'due_date date',
        'completed_at timestamptz',
        'client_visible boolean not null default true',
        'is_active boolean not null default true',
        'version_number integer not null default 1',
        'references app.projects(id) on delete restrict',
        'references app.project_phases(id) on delete restrict',
        'references app.users(id) on delete restrict',
        'length(btrim(description)) <= 4000',
        'version_number >= 1',
        'phase must belong to the same project',
        'requires an active phase',
        'due date must fit inside project dates',
        'due date must fit inside phase dates',
    ):
        require(required in milestone_schema_sql,
                f'1104 milestone schema contains required clause: {required}')
    for forbidden in (
        'create type app.project_milestone_status',
        ' status ',
        'sequence_no',
        'milestone_number',
        'completion_percent',
        'weight_percent',
        'actual_completion_date',
        'completed_by',
        'archived_at',
        'archived_by',
        'cancellation_reason',
        'payment_request_id',
        'amount',
        'currency_code',
        'predecessor_id',
        'template_id',
        'colour',
        'task_count',
        'delete from app.project_milestones',
    ):
        require(forbidden not in milestone_schema_sql,
                f'1104 milestone schema omits forbidden field/pattern: {forbidden}')
if milestone_functions_path.exists():
    milestone_functions_sql = milestone_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.create_project_milestone',
        'create or replace function app.update_project_milestone',
        'create or replace function app.complete_project_milestone',
        'create or replace function app.archive_project_milestone',
        'create or replace function app.owner_project_milestone_list',
        'create or replace function app.owner_project_milestone_detail',
        'create or replace function app.current_client_project_milestones_for_authenticated_user',
        'create or replace function app.current_client_project_milestone_for_authenticated_user',
        'create or replace function public.current_client_project_milestones',
        'create or replace function public.current_client_project_milestone',
        'create or replace function public.server_create_project_milestone',
        'create or replace function public.server_update_project_milestone',
        'create or replace function public.server_complete_project_milestone',
        'create or replace function public.server_archive_project_milestone',
        'create or replace function public.server_owner_project_milestone_list',
        'create or replace function public.server_owner_project_milestone_detail',
        'security definer',
        "set search_path = ''",
        'app.require_active_owner_admin',
        "p_project.status not in ('draft', 'quotation', 'approved', 'active', 'on_hold')",
        "project_row.status not in ('active', 'on_hold')",
        "project_row.status = 'archived'",
        'project milestone version conflict',
        'project milestone cannot be completed',
        'project milestone cannot be archived',
        'app.allow_project_milestone_completion',
        'app.allow_project_milestone_archive',
        'project client cannot be changed after milestone history exists',
        'project phase cannot be archived while active milestones reference it',
        'project cannot be archived while active phases exist',
        'project cannot be archived while active milestones exist',
        'project dates cannot exclude existing milestone history',
        'project phase dates cannot exclude existing milestone history',
        'project_milestone_created',
        'project_milestone_updated',
        'project_milestone_completed',
        'project_milestone_archived',
        "'[masked]'",
    ):
        require(required in milestone_functions_sql,
                f'1105 milestone functions migration contains required clause: {required}')
    safe_milestone_return = re.search(
        r'create or replace function public\.current_client_project_milestones\(.*?returns table \((.*?)\)\s+language',
        milestone_functions_sql,
        re.S,
    )
    require(safe_milestone_return is not None, '1105 public.current_client_project_milestones return shape is inspectable')
    if safe_milestone_return:
        returned = safe_milestone_return.group(1)
        for safe_field in ('id uuid', 'project_id uuid', 'phase_id uuid', 'name text', 'description text', 'due_date date', 'completed_at timestamptz'):
            require(safe_field in returned, f'1105 Client milestone read returns safe field: {safe_field}')
        for forbidden_field in ('is_active', 'client_visible', 'created_by', 'updated_by', 'version_number'):
            require(forbidden_field not in returned, f'1105 Client milestone read omits private field: {forbidden_field}')
    for forbidden in (
        'create or replace function app.reopen_project_milestone',
        'create or replace function public.server_reopen_project_milestone',
        'create or replace function public.current_staff_project_milestone',
        'create or replace function public.current_project_manager_project_milestone',
        'create or replace function public.current_site_supervisor_project_milestone',
        'execute ',
        'format(',
        'raw_app_meta_data',
        'full description',
    ):
        require(forbidden not in milestone_functions_sql,
                f'1105 milestone functions omit prohibited pattern: {forbidden}')
if milestone_grants_path.exists():
    milestone_grants_sql = milestone_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.project_milestones from public, anon, authenticated, service_role',
        'revoke all on function app.create_project_milestone',
        'revoke all on function app.complete_project_milestone',
        'from public, anon, authenticated, service_role',
        'grant execute on function public.current_client_project_milestones',
        'to authenticated',
        'grant execute on function public.server_create_project_milestone',
        'grant execute on function public.server_complete_project_milestone',
        'grant execute on function public.server_owner_project_milestone_list',
        'to service_role',
    ):
        require(required in milestone_grants_sql,
                f'1106 milestone grants migration contains required clause: {required}')
    for forbidden in (
        'grant select on app.project_milestones',
        'grant insert on app.project_milestones',
        'grant update on app.project_milestones',
        'grant delete on app.project_milestones',
        'current_staff_project_milestone',
        'current_project_manager_project_milestone',
        'current_site_supervisor_project_milestone',
    ):
        require(forbidden not in milestone_grants_sql,
                f'1106 milestone grants omit prohibited grant: {forbidden}')
task_schema_path = ROOT / 'supabase/migrations/20260724101000_1107_project_tasks.sql'
task_functions_path = ROOT / 'supabase/migrations/20260724101100_1108_project_task_functions.sql'
task_grants_path = ROOT / 'supabase/migrations/20260724101200_1109_project_task_grants.sql'
if task_schema_path.exists():
    task_schema_sql = task_schema_path.read_text(encoding='utf-8').lower()
    require('create type app.project_task_status as enum' in task_schema_sql, '1107 creates task status enum')
    for status in ("'todo'", "'in_progress'", "'blocked'", "'completed'", "'cancelled'"):
        require(status in task_schema_sql, f'1107 task status value exists: {status}')
    require('create table app.project_task_number_counters' in task_schema_sql, '1107 creates internal Project task-number counter')
    require('create table app.tasks' in task_schema_sql, '1107 creates tasks table')
    require('force row level security' in task_schema_sql, '1107 forces task RLS')
    require('before delete on app.tasks' in task_schema_sql, '1107 prevents task hard deletion')
    require('before update on app.tasks' in task_schema_sql, '1107 adds trusted task update guard')
    require('tasks_validate_relationships' in task_schema_sql, '1107 validates Project/phase/milestone relationships')
    require('generate_project_task_number' in task_schema_sql and 'on conflict (project_id)' in task_schema_sql and 'max(' not in task_schema_sql, '1107 uses concurrency-safe Project-local task numbering without MAX')
    for column in (
        'id',
        'project_id',
        'phase_id',
        'milestone_id',
        'task_number',
        'title',
        'description',
        'client_summary',
        'status',
        'completion_percent',
        'weight_percent',
        'counts_toward_completion',
        'start_date',
        'due_date',
        'completed_at',
        'client_visible',
        'is_active',
        'created_at',
        'created_by',
        'updated_at',
        'updated_by',
        'version_number',
    ):
        require(re.search(rf'\b{re.escape(column)}\b', task_schema_sql),
                f'1107 task schema contains exact field: {column}')
    for required in (
        'tsk-',
        'project_id, task_number',
        'counts_toward_completion',
        'weight_percent is null',
        'completion_percent = 0',
        "status = 'todo'",
        'completed_at is null',
        'project task phase must belong to the same project',
        'project task milestone must belong to the same project',
        'project task phase must match the milestone phase',
        'project task dates must fit inside project dates',
        'project task dates must fit inside project phase dates',
    ):
        require(required in task_schema_sql,
                f'1107 task schema contains required clause: {required}')
    for forbidden in (
        'assigned_user_id',
        'operational_notes',
        'cancellation_reason',
        'completed_by',
        'cancelled_by',
        'archived_at',
        'archived_by',
        'estimated_cost',
        'actual_cost',
        'task_assignments',
        'task_updates',
    ):
        require(forbidden not in task_schema_sql,
                f'1107 task schema omits forbidden field/object: {forbidden}')
if task_functions_path.exists():
    task_functions_sql = task_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.create_project_task',
        'create or replace function app.update_project_task',
        'create or replace function app.archive_project_task',
        'create or replace function app.owner_project_task_list',
        'create or replace function app.owner_project_task_detail',
        'create or replace function app.current_client_project_tasks_for_authenticated_user',
        'create or replace function public.current_client_project_tasks',
        'create or replace function public.current_client_project_task',
        'create or replace function public.server_create_project_task',
        'create or replace function public.server_update_project_task',
        'create or replace function public.server_archive_project_task',
        'require_active_owner_admin',
        'project client cannot be changed after task history exists',
        'project phase cannot be archived while active tasks reference it',
        'project milestone cannot be archived while active tasks reference it',
        'project cannot be archived while active tasks exist',
        'project dates cannot exclude existing task history',
        'project phase dates cannot exclude existing task history',
        'project milestone phase cannot change while task history would become inconsistent',
    ):
        require(required in task_functions_sql,
                f'1108 task functions contain required clause: {required}')
    client_task_match = re.search(
        r'create\s+or\s+replace\s+function\s+public\.current_client_project_tasks[\s\S]+?returns\s+table\s*\(([\s\S]+?)\)\s+language',
        task_functions_sql,
    )
    require(client_task_match is not None, '1108 Client task read signature is detectable')
    if client_task_match:
        returned = client_task_match.group(1)
        for safe_field in ('id', 'project_id', 'phase_id', 'milestone_id', 'task_number', 'title', 'client_summary', 'status', 'completion_percent', 'start_date', 'due_date', 'completed_at'):
            require(safe_field in returned, f'1108 Client task read returns safe field: {safe_field}')
        for forbidden_field in ('description', 'weight_percent', 'counts_toward_completion', 'client_visible', 'is_active', 'created_by', 'updated_by', 'version_number'):
            require(forbidden_field not in returned, f'1108 Client task read omits private field: {forbidden_field}')
    for forbidden in (
        'create or replace function public.server_complete_project_task',
        'create or replace function public.server_change_project_task_status',
        'create or replace function public.server_update_project_task_progress',
        'create or replace function public.current_staff_project_task',
        'create or replace function public.current_project_manager_project_task',
        'create or replace function public.current_site_supervisor_project_task',
        'execute ',
        'format(',
        'raw_app_meta_data',
        'task_assignments',
        'task_updates',
    ):
        require(forbidden not in task_functions_sql,
                f'1108 task functions omit prohibited pattern: {forbidden}')
if task_grants_path.exists():
    task_grants_sql = task_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.tasks from public, anon, authenticated, service_role',
        'revoke all on app.project_task_number_counters from public, anon, authenticated, service_role',
        'revoke all on function app.create_project_task',
        'revoke all on function app.update_project_task',
        'revoke all on function app.archive_project_task',
        'from public, anon, authenticated, service_role',
        'grant execute on function public.current_client_project_tasks',
        'to authenticated',
        'grant execute on function public.server_create_project_task',
        'grant execute on function public.server_update_project_task',
        'grant execute on function public.server_archive_project_task',
        'grant execute on function public.server_owner_project_task_list',
        'to service_role',
    ):
        require(required in task_grants_sql,
                f'1109 task grants migration contains required clause: {required}')
    for forbidden in (
        'grant select on app.tasks',
        'grant insert on app.tasks',
        'grant update on app.tasks',
        'grant delete on app.tasks',
        'current_staff_project_task',
        'current_project_manager_project_task',
        'current_site_supervisor_project_task',
    ):
        require(forbidden not in task_grants_sql,
                f'1109 task grants omit prohibited grant: {forbidden}')

task_assignment_schema_path = ROOT / 'supabase/migrations/20260724101300_1110_task_assignments.sql'
task_assignment_functions_path = ROOT / 'supabase/migrations/20260724101400_1111_task_assignment_functions.sql'
task_assignment_grants_path = ROOT / 'supabase/migrations/20260724101500_1112_task_assignment_grants.sql'
if task_assignment_schema_path.exists():
    task_assignment_schema_sql = task_assignment_schema_path.read_text(encoding='utf-8').lower()
    require('create table app.task_assignments' in task_assignment_schema_sql, '1110 creates task assignments table')
    require('force row level security' in task_assignment_schema_sql, '1110 forces task assignment RLS')
    require('before delete on app.task_assignments' in task_assignment_schema_sql, '1110 prevents task assignment hard deletion')
    require('before update on app.task_assignments' in task_assignment_schema_sql, '1110 adds trusted task assignment update guard')
    require('create unique index task_assignments_one_active_pair_idx' in task_assignment_schema_sql and 'where is_active' in task_assignment_schema_sql, '1110 uses partial active-pair uniqueness')
    require('unique (task_id' not in task_assignment_schema_sql, '1110 does not use permanent pair uniqueness')
    require('unique (task_id)' not in task_assignment_schema_sql, '1110 allows multiple active assignees per task')
    for column in ('id', 'task_id', 'project_staff_assignment_id', 'assigned_at', 'assigned_by', 'removed_at', 'is_active'):
        require(re.search(rf'\b{re.escape(column)}\b', task_assignment_schema_sql),
                f'1110 task assignment schema contains exact field: {column}')
    for required in (
        'references app.tasks(id) on delete restrict',
        'references app.project_staff_assignments(id) on delete restrict',
        'references app.users(id) on delete restrict',
        'is_active and removed_at is null',
        'not is_active',
        'inactive project task assignments are immutable',
        'cannot be reactivated',
        'project task assignments cannot be deleted',
    ):
        require(required in task_assignment_schema_sql,
                f'1110 task assignment schema contains required clause: {required}')
    for forbidden in (
        'user_id',
        'project_id',
        'role_code',
        'assigned_role',
        'task_status',
        'completion_percent',
        'notes',
        'removal_reason',
        'removed_by',
        'updated_at',
        'updated_by',
        'version_number',
        'client_visible',
    ):
        require(not re.search(rf'^\s*{re.escape(forbidden)}\s+', task_assignment_schema_sql, re.MULTILINE),
                f'1110 task assignment schema omits forbidden field: {forbidden}')
    require('notification' not in task_assignment_schema_sql,
            '1110 task assignment schema omits notification pattern')
if task_assignment_functions_path.exists():
    task_assignment_functions_sql = task_assignment_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.assign_project_task',
        'create or replace function app.remove_project_task_assignment',
        'create or replace function app.owner_project_task_assignment_list',
        'create or replace function app.owner_project_task_assignment_detail',
        'create or replace function public.server_assign_project_task',
        'create or replace function public.server_remove_project_task_assignment',
        'create or replace function public.server_owner_project_task_assignment_list',
        'create or replace function public.server_owner_project_task_assignment_detail',
        'require_active_owner_admin',
        "task_row.status <> 'todo'",
        "project_row.status not in ('draft', 'quotation', 'approved', 'active', 'on_hold')",
        "staff_assignment_row.assignment_role_code not in ('project_manager', 'site_supervisor')",
        'assert_project_staff_assignment_target',
        'project task assignment already exists',
        'project task cannot be archived while active assignments exist',
        'project_access_removed',
        'affected_active_assignment_count',
        'project cannot be archived while active task assignments exist',
        'project_task_assigned',
        'project_task_assignment_removed',
    ):
        require(required in task_assignment_functions_sql,
                f'1111 task assignment functions contain required clause: {required}')
    for forbidden in (
        'create or replace function public.current_staff_task_assignments',
        'create or replace function public.current_assigned_tasks',
        'create or replace function public.server_reassign_project_task',
        'project_task_reassigned',
        'project_task_status_changed',
        'project_task_completed',
        'insert into app.user_roles',
        'public.current_account',
        'task_updates',
        'progress_updates',
        'notifications',
        'format(',
        'raw_app_meta_data',
    ):
        require(forbidden not in task_assignment_functions_sql,
                f'1111 task assignment functions omit prohibited pattern: {forbidden}')
if task_assignment_grants_path.exists():
    task_assignment_grants_sql = task_assignment_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.task_assignments from public, anon, authenticated, service_role',
        'revoke all on function app.assign_project_task',
        'revoke all on function app.remove_project_task_assignment',
        'from public, anon, authenticated, service_role',
        'grant execute on function public.server_assign_project_task',
        'grant execute on function public.server_remove_project_task_assignment',
        'grant execute on function public.server_owner_project_task_assignment_list',
        'grant execute on function public.server_owner_project_task_assignment_detail',
        'to service_role',
    ):
        require(required in task_assignment_grants_sql,
                f'1112 task assignment grants contain required clause: {required}')
    for forbidden in (
        'grant select on app.task_assignments',
        'grant insert on app.task_assignments',
        'grant update on app.task_assignments',
        'grant delete on app.task_assignments',
        'current_staff_task_assignments',
        'current_assigned_tasks',
    ):
        require(forbidden not in task_assignment_grants_sql,
                f'1112 task assignment grants omit prohibited grant: {forbidden}')
    require(not re.search(r'grant\s+execute\s+on\s+function\s+public\.[a-z_]*task_assignment[a-z_]*[\s\S]+?\s+to\s+authenticated', task_assignment_grants_sql),
            '1112 task assignment grants omit authenticated public assignment execution')

task_update_schema_path = ROOT / 'supabase/migrations/20260724101600_1113_task_updates.sql'
task_update_functions_path = ROOT / 'supabase/migrations/20260724101700_1114_task_update_functions.sql'
task_update_grants_path = ROOT / 'supabase/migrations/20260724101800_1115_task_update_grants.sql'
if task_update_schema_path.exists():
    task_update_schema_sql = task_update_schema_path.read_text(encoding='utf-8').lower()
    require('create table app.task_updates' in task_update_schema_sql, '1113 creates task update history table')
    require('force row level security' in task_update_schema_sql, '1113 forces task update RLS')
    require('before update on app.task_updates' in task_update_schema_sql, '1113 prevents task update mutation')
    require('before delete on app.task_updates' in task_update_schema_sql, '1113 prevents task update deletion')
    require('before truncate on app.task_updates' in task_update_schema_sql, '1113 prevents task update truncation')
    require('alter table app.tasks drop constraint tasks_initial_workflow_ck' in task_update_schema_sql, '1113 replaces initial-only task workflow constraint')
    require('add constraint tasks_workflow_state_ck' in task_update_schema_sql, '1113 adds canonical task workflow state constraint')
    require('app.allow_project_task_workflow' in task_update_schema_sql, '1113 trusted task guard uses workflow context')
    for column in ('id', 'task_id', 'previous_status', 'new_status', 'previous_completion_percent', 'new_completion_percent', 'update_note', 'created_at', 'created_by'):
        require(re.search(rf'\b{re.escape(column)}\b', task_update_schema_sql),
                f'1113 task update schema contains exact field: {column}')
    for required in (
        'previous_status app.project_task_status',
        'new_status app.project_task_status',
        'references app.tasks(id) on delete restrict',
        'references app.users(id) on delete restrict',
        'previous_completion_percent >= 0',
        'new_completion_percent >= 0',
        'length(update_note) <= 4000',
        'task_updates_task_history_idx',
        'task_updates_actor_audit_idx',
        "status = 'completed'",
        'completion_percent = 100',
        'completed_at is not null',
        "status <> 'completed'",
        'completion_percent < 100',
        'completed_at is null',
    ):
        require(required in task_update_schema_sql,
                f'1113 task update schema contains required clause: {required}')
    for forbidden in (
        'task_assignment_id',
        'event_type',
        'transition_type',
        'cancellation_reason',
        'reopen_reason',
        'completed_by',
        'cancelled_by',
        'notification',
    ):
        require(forbidden not in task_update_schema_sql,
                f'1113 task update schema omits forbidden pattern: {forbidden}')
if task_update_functions_path.exists():
    task_update_functions_sql = task_update_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.update_project_task_progress',
        'create or replace function app.change_project_task_status',
        'create or replace function app.complete_project_task',
        'create or replace function app.reopen_project_task',
        'create or replace function app.cancel_project_task',
        'create or replace function app.owner_project_task_update_list',
        'create or replace function app.owner_project_task_update_detail',
        'create or replace function public.server_update_project_task_progress',
        'create or replace function public.server_change_project_task_status',
        'create or replace function public.server_complete_project_task',
        'create or replace function public.server_reopen_project_task',
        'create or replace function public.server_cancel_project_task',
        'require_active_owner_admin',
        'for update',
        'insert_project_task_update',
        'project_task_progress_updated',
        'project_task_status_changed',
        'project_task_completed',
        'project_task_reopened',
        'project_task_cancelled',
        "existing_row.status = 'blocked'",
        "existing_row.status not in ('in_progress', 'blocked')",
        "status not in ('completed', 'cancelled')",
        'project task cannot be archived while active assignments exist',
    ):
        require(required in task_update_functions_sql,
                f'1114 task update functions contain required clause: {required}')
    for forbidden in (
        'create or replace function public.current_staff_task_updates',
        'create or replace function public.current_assigned_task_updates',
        'create or replace function public.current_client_task_updates',
        'server_calculate_project_completion',
        'server_create_progress_update',
        'progress_updates',
        'completion_overrides',
        'notifications',
        'format(',
        'raw_app_meta_data',
        'insert into app.task_assignments',
        'update app.task_assignments',
    ):
        require(forbidden not in task_update_functions_sql,
                f'1114 task update functions omit prohibited pattern: {forbidden}')
if task_update_grants_path.exists():
    task_update_grants_sql = task_update_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.task_updates from public, anon, authenticated, service_role',
        'revoke all on function app.update_project_task_progress',
        'revoke all on function app.change_project_task_status',
        'revoke all on function app.complete_project_task',
        'revoke all on function app.reopen_project_task',
        'revoke all on function app.cancel_project_task',
        'from public, anon, authenticated, service_role',
        'grant execute on function public.server_update_project_task_progress',
        'grant execute on function public.server_change_project_task_status',
        'grant execute on function public.server_complete_project_task',
        'grant execute on function public.server_reopen_project_task',
        'grant execute on function public.server_cancel_project_task',
        'grant execute on function public.server_owner_project_task_update_list',
        'grant execute on function public.server_owner_project_task_update_detail',
        'to service_role',
    ):
        require(required in task_update_grants_sql,
                f'1115 task update grants contain required clause: {required}')
    for forbidden in (
        'grant select on app.task_updates',
        'grant insert on app.task_updates',
        'grant update on app.task_updates',
        'grant delete on app.task_updates',
        'to authenticated',
        'current_staff_task_updates',
        'current_assigned_task_updates',
        'current_client_task_updates',
    ):
        require(forbidden not in task_update_grants_sql,
                f'1115 task update grants omit prohibited grant: {forbidden}')

task_update_scope_sql = '\n'.join(
    p.read_text(encoding='utf-8', errors='ignore').lower()
    for p in (task_update_schema_path, task_update_functions_path, task_update_grants_path)
    if p.exists()
)
require('create table app.task_updates' in all_sql, '11.5 adds task update history')
require('create table app.progress_updates' not in task_update_scope_sql and 'create table app.completion_overrides' not in task_update_scope_sql, '11.5 does not add progress or completion override objects')
require('create table app.notifications' not in task_update_scope_sql, '11.5 does not add notifications')
require('create table app.project_documents' not in all_sql, '11.5 does not add legacy project_documents')
require('create table app.financial_transactions' not in all_sql and 'create table app.ledger_entries' not in all_sql, '11.5 does not add finance or ledger objects')

functions_dir = ROOT / 'supabase/functions'
require(functions_dir.exists(), 'shared Edge Function helper directory exists')
if functions_dir.exists():
    allowed_function_paths = {
        Path('deno.json'),
        Path('deno.lock'),
    }
    stage_09_2c3c_functions = {
        'create-client-invitation',
        'resend-client-invitation',
        'revoke-client-invitation',
        'accept-client-invitation',
    }
    stage_09_2c3d_functions = {
        'suspend-client-account',
        'reactivate-client-account',
        'disable-client-account',
    }
    allowed_shared_files = {
        'auth.ts',
        'client_invitation_handler.ts',
        'client_invitation_handler_test.ts',
        'client_lifecycle_handler.ts',
        'client_lifecycle_handler_test.ts',
        'cors.ts',
        'denied_log.ts',
        'env.ts',
        'errors.ts',
        'helpers_test.ts',
        'http.ts',
        'invitation_url.ts',
        'redaction.ts',
        'supabase.ts',
        'token.ts',
        'validation.ts',
    }
    for path in functions_dir.rglob('*'):
        if path.is_file():
            relative = path.relative_to(functions_dir)
            allowed = relative in allowed_function_paths or (
                len(relative.parts) == 2 and relative.parts[0] == '_shared' and relative.name in allowed_shared_files
            ) or (
                len(relative.parts) == 2 and relative.parts[0] in stage_09_2c3c_functions and relative.name in {'index.ts', 'deno.json'}
            ) or (
                len(relative.parts) == 2 and relative.parts[0] in stage_09_2c3d_functions and relative.name in {'index.ts', 'deno.json'}
            )
            require(allowed, f'only approved shared Deno helper files exist: {relative}')
    for name in allowed_shared_files:
        require((functions_dir / '_shared' / name).exists(), f'shared helper file exists: _shared/{name}')
    for function_name in sorted(stage_09_2c3c_functions):
        function_dir = functions_dir / function_name
        require(function_dir.exists(), f'09.2C3C Edge Function directory exists: {function_name}')
        require((function_dir / 'index.ts').exists(), f'09.2C3C Edge Function entrypoint exists: {function_name}/index.ts')
        function_deno_path = function_dir / 'deno.json'
        require(function_deno_path.exists(), f'09.2C3C function-level deno.json exists: {function_name}/deno.json')
        if function_deno_path.exists():
            function_deno = function_deno_path.read_text(encoding='utf-8')
            require('"@supabase/server": "npm:@supabase/server@1.4.1"' in function_deno,
                    f'09.2C3C function pins @supabase/server exactly: {function_name}')
            require('"@supabase/supabase-js": "npm:@supabase/supabase-js@2.110.8"' in function_deno,
                    f'09.2C3C function pins @supabase/supabase-js exactly: {function_name}')
    for function_name in sorted(stage_09_2c3d_functions):
        function_dir = functions_dir / function_name
        require(function_dir.exists(), f'09.2C3D Edge Function directory exists: {function_name}')
        require((function_dir / 'index.ts').exists(), f'09.2C3D Edge Function entrypoint exists: {function_name}/index.ts')
        function_deno_path = function_dir / 'deno.json'
        require(function_deno_path.exists(), f'09.2C3D function-level deno.json exists: {function_name}/deno.json')
        if function_deno_path.exists():
            function_deno = function_deno_path.read_text(encoding='utf-8')
            require('"@supabase/server": "npm:@supabase/server@1.4.1"' in function_deno,
                    f'09.2C3D function pins @supabase/server exactly: {function_name}')
            require('"@supabase/supabase-js": "npm:@supabase/supabase-js@2.110.8"' in function_deno,
                    f'09.2C3D function pins @supabase/supabase-js exactly: {function_name}')

deno_json_path = functions_dir / 'deno.json'
deno_lock_path = functions_dir / 'deno.lock'
if deno_json_path.exists():
    deno_json = deno_json_path.read_text(encoding='utf-8')
    require('"@supabase/server": "npm:@supabase/server@1.4.1"' in deno_json,
            'Deno import pins @supabase/server exactly')
    require('"@supabase/supabase-js": "npm:@supabase/supabase-js@2.110.8"' in deno_json,
            'Deno import pins @supabase/supabase-js exactly')
    require('deno fmt --check .' in deno_json, 'Deno format check task exists')
    require('deno lint .' in deno_json, 'Deno lint task exists')
    require('deno check _shared/*.ts _shared/*_test.ts' in deno_json, 'Deno type-check task exists')
    for function_name in (
        'create-client-invitation',
        'resend-client-invitation',
        'revoke-client-invitation',
        'accept-client-invitation',
        'suspend-client-account',
        'reactivate-client-account',
        'disable-client-account',
    ):
        require(f'{function_name}/index.ts' in deno_json,
                f'Deno tasks include function entrypoint: {function_name}')
    require('deno test' in deno_json, 'Deno unit test task exists')
    require('--frozen --lock=deno.lock' in deno_json, 'Deno frozen lock cache task exists')
require(deno_lock_path.exists(), 'Deno lock file is committed')
if deno_lock_path.exists():
    deno_lock = deno_lock_path.read_text(encoding='utf-8')
    require('@supabase/server@1.4.1' in deno_lock, 'Deno lock contains @supabase/server pin')
    require('@supabase/supabase-js@2.110.8' in deno_lock, 'Deno lock contains @supabase/supabase-js pin')

env_example = (ROOT / '.env.example').read_text(encoding='utf-8')
require('SUPABASE_URL=' in env_example, '.env.example documents SUPABASE_URL')
require('SUPABASE_JWKS_URL=' not in env_example, '.env.example does not require standalone SUPABASE_JWKS_URL')
env_helper_path = functions_dir / '_shared' / 'env.ts'
if env_helper_path.exists():
    env_helper = env_helper_path.read_text(encoding='utf-8')
    env_helper_lower = env_helper.lower()
    require('new URL("/auth/v1/.well-known/jwks.json", supabaseUrl)' in env_helper,
            'JWKS URL is derived from trusted SUPABASE_URL')
    require('requireEnvValue(source, "SUPABASE_JWKS_URL")' not in env_helper,
            'JWKS URL is not a mandatory standalone environment variable')
    require('validateSupabaseUrl(requireEnvValue(source, "SUPABASE_URL"))' in env_helper,
            'SUPABASE_URL is validated before JWKS derivation')
    for local_host in ('localhost', '127.0.0.1', 'host.docker.internal', 'kong'):
        require(f'url.hostname === "{local_host}"' in env_helper,
                f'local HTTP URL exception includes only approved local host: {local_host}')
    require('url.hostname === "host.docker.internal"' in env_helper,
            'local HTTP URL exception supports Supabase Edge runtime Docker host bridge')
    require('url.hostname === "kong"' in env_helper,
            'local HTTP URL exception supports Supabase Edge runtime internal Kong host')
    require('http://example.com' not in env_helper_lower and 'request-controlled' not in env_helper_lower,
            'env helper does not hard-code untrusted JWKS hosts')

shared_code = '\n'.join(
    p.read_text(encoding='utf-8', errors='ignore').lower()
    for p in (functions_dir / '_shared').glob('*.ts')
) if (functions_dir / '_shared').exists() else ''
shared_prod_code = '\n'.join(
    p.read_text(encoding='utf-8', errors='ignore').lower()
    for p in (functions_dir / '_shared').glob('*.ts')
    if not p.name.endswith('_test.ts')
) if (functions_dir / '_shared').exists() else ''
lifecycle_prod_code = (functions_dir / '_shared' / 'client_lifecycle_handler.ts').read_text(
    encoding='utf-8',
    errors='ignore',
).lower() if (functions_dir / '_shared' / 'client_lifecycle_handler.ts').exists() else ''
require('access-control-allow-origin", "*"' not in shared_code and "access-control-allow-origin': '*'" not in shared_code,
        'shared CORS code does not use wildcard origin')
require('withsupabase' in shared_code and 'auth: "user"' in shared_code,
        'shared handler authentication uses auth: "user"')
require('createserviceclient(env)' in shared_code and shared_code.find('authenticate') < shared_code.find('createserviceclient(env)'),
        'service client creation remains behind authentication helper')
require('/accept-invitation?token=' not in shared_prod_code,
        'shared function code does not log or embed complete invitation URLs')
for prohibited_body_field in ('actor_id', 'actor_auth_subject', 'role_code', 'user_type', 'account_status'):
    require(not re.search(rf'rejectunknownfields\([^)]*"{re.escape(prohibited_body_field)}"', shared_prod_code, re.S),
            f'shared function code does not accept prohibited body field: {prohibited_body_field}')
require('deleteuser' not in lifecycle_prod_code, 'lifecycle handlers do not delete Auth users')
require('inviteuserbyemail' not in lifecycle_prod_code, 'lifecycle handlers do not send invitations')
require('generatelink' not in lifecycle_prod_code, 'lifecycle handlers do not generate invitation links')
require('updateuserbyid' in lifecycle_prod_code, 'lifecycle handlers use Auth Admin updateUserById')
require('const long_ban_duration = "876000h"' in lifecycle_prod_code, 'lifecycle handlers use documented long Auth ban')
require('ban_duration: "none"' in lifecycle_prod_code, 'reactivation removes Auth ban')
require(
    lifecycle_prod_code.find('"server_suspend_client_account"') < lifecycle_prod_code.find('ban_duration: operation.banduration'),
    'suspend database call is before Auth ban update',
)
require(
    lifecycle_prod_code.find('"server_disable_client_account"') < lifecycle_prod_code.find('ban_duration: operation.banduration'),
    'disable database call is before Auth ban update',
)
require(
    lifecycle_prod_code.find('ban_duration: "none"') < lifecycle_prod_code.find('"server_reactivate_client_account"'),
    'reactivation removes Auth ban before database reactivation',
)
require('auth_update: compensation.error ? "compensation_failed" : "compensated"' in lifecycle_prod_code,
        'reactivation includes re-ban compensation handling')

function_config = config.get('functions', {})
for function_name in (
    'create-client-invitation',
    'resend-client-invitation',
    'revoke-client-invitation',
    'accept-client-invitation',
    'suspend-client-account',
    'reactivate-client-account',
    'disable-client-account',
):
    require(function_config.get(function_name, {}).get('verify_jwt') is False,
            f'Edge Function verify_jwt disabled for handler-owned auth: {function_name}')

bootstrap_script_path = ROOT / 'scripts/bootstrap_production_owner.mjs'
bootstrap_test_path = ROOT / 'scripts/bootstrap_production_owner_test.mjs'
require(bootstrap_script_path.exists(), 'guarded first-Owner bootstrap script exists')
require(bootstrap_test_path.exists(), 'guarded first-Owner bootstrap Deno tests exist')
if bootstrap_script_path.exists():
    bootstrap_script = bootstrap_script_path.read_text(encoding='utf-8')
    bootstrap_lower = bootstrap_script.lower()
    for required in (
        'create first contractor owner',
        'if (import.meta.main)',
        'createclient',
        'generatelink',
        'server_bootstrap_first_owner',
        'server_first_owner_delivery_context',
        'inviteuserbyemail',
        '/owner/activate',
        'generateTokenBytes',
        'sha-256',
        'exit = object.freeze',
        'validation: 1',
        'authpreparation: 2',
        'recoverynotproven: 3',
        'deliveryunconfirmed: 4',
        'expiredinvitation: 5',
        'internal: 6',
    ):
        require(required.lower() in bootstrap_lower,
                f'bootstrap script contains required safety/flow marker: {required}')
    require(bootstrap_lower.count('inviteuserbyemail') == 1,
            'bootstrap script performs one invitation delivery attempt per execution')
    require('deleteuser' not in bootstrap_lower, 'bootstrap script does not delete Auth users')
    require('process.env' not in bootstrap_lower and 'require(' not in bootstrap_lower,
            'bootstrap script does not require Node/npm runtime')
    require('console.log(config.' not in bootstrap_lower and 'console.log(env.' not in bootstrap_lower,
            'bootstrap script does not print raw environment values')
    for forbidden in ('token=', 'token_hash=', 'action_link', 'hashed_token', 'service_role_key='):
        require(forbidden not in bootstrap_lower,
                f'bootstrap script avoids unsafe output marker: {forbidden}')
    require(not re.search(r'(?<![a-z])otp(?![a-z])', bootstrap_lower),
            'bootstrap script avoids unsafe output marker: otp')

for node_manifest in ('package.json', 'package-lock.json', 'npm-shrinkwrap.json'):
    require(not (ROOT / node_manifest).exists(), f'no Node/npm manifest introduced: {node_manifest}')

e2e_script_path = ROOT / 'scripts/package_09_2_e2e_local.mjs'
e2e_test_path = ROOT / 'scripts/package_09_2_e2e_local_test.mjs'
require(e2e_script_path.exists(), 'Package 09.2 local E2E harness exists')
require(e2e_test_path.exists(), 'Package 09.2 local E2E mocked Deno tests exist')
if e2e_script_path.exists():
    e2e_script = e2e_script_path.read_text(encoding='utf-8')
    e2e_lower = e2e_script.lower()
    for required in (
        'if (import.meta.main)',
        'assertlocalsupabaseurl',
        'args: ["functions", "serve", "--env-file", envFile]',
        'const app_base_url = "http://localhost:3000"',
        'verifyotp',
        'token_hash',
        'type: "invite"',
        'mailpit_url',
        'waitformail',
        'clearMailpit',
        'cleanupAll',
        'finally',
        'create-client-invitation',
        'resend-client-invitation',
        'revoke-client-invitation',
        'accept-client-invitation',
        'suspend-client-account',
        'reactivate-client-account',
        'disable-client-account',
        'delete',
        'current_account',
        'activate_current_invited_owner',
        'denied_privileged_operation',
        'package_09_2_e2e',
    ):
        require(required.lower() in e2e_lower,
                f'Package 09.2 local E2E harness contains required marker: {required}')
    require('signups' not in e2e_lower and 'password:' not in e2e_lower and 'signInWithPassword' not in e2e_script,
            'local E2E harness does not use temporary passwords')
    require('createUser(' not in e2e_script and 'admin.createUser' not in e2e_script,
            'local E2E harness does not create administrator-generated sessions')
    require('console.log(' not in e2e_script or 'safeLine' in e2e_script,
            'local E2E harness uses safe output helpers')
    for forbidden in ('safeLine("access_token"', 'safeLine("refresh_token"', 'safeLine("token"', 'safeLine("token_hash"', 'action_link', 'service_role_key='):
        require(forbidden not in e2e_lower,
                f'local E2E harness avoids unsafe output marker: {forbidden}')
if e2e_test_path.exists():
    e2e_test = e2e_test_path.read_text(encoding='utf-8')
    for required in (
        'local-only URL enforcement',
        'supabase status parsing',
        'Mailpit polling',
        'recursive redaction',
        'no-BOM env-file generation',
        'process startup/readiness',
        'cleanup executes after failure',
    ):
        require(required in e2e_test,
                f'Package 09.2 local E2E mocked test covers: {required}')

require(not (ROOT / 'supabase/functions/bootstrap-production-owner').exists(), 'no first-Owner Edge Function directory added')
require(not (ROOT / 'supabase/functions/bootstrap-first-owner').exists(), 'no first-Owner Edge Function directory added')

flutter_invitation_ui_mentions = [
    p for p in (ROOT / 'app/lib').glob('**/*.dart')
    if p.is_file() and re.search(r'invitation|invite[-_ ]?client|user_invitations', p.read_text(encoding='utf-8', errors='ignore'), re.I)
]
require(not flutter_invitation_ui_mentions, 'no Flutter invitation UI added')
flutter_activation_ui_mentions = [
    p for p in (ROOT / 'app/lib').glob('**/*.dart')
    if p.is_file() and re.search(r'owner/activate|activate_current_invited_owner|bootstrap[-_ ]?owner', p.read_text(encoding='utf-8', errors='ignore'), re.I)
]
require(not flutter_activation_ui_mentions, 'no Flutter Owner activation UI added')

with (ROOT / '.github/workflows/package-09-1-database.yml').open('r', encoding='utf-8') as fh:
    yaml.safe_load(fh)
passes.append('CI YAML parsed')

frontend_candidates = list(ROOT.glob('lib/**/*.dart')) + list(ROOT.glob('web/**/*'))
require(not frontend_candidates, 'no frontend implementation added in Package 09.1')

completion_schema_path = ROOT / 'supabase/migrations/20260724101900_1116_completion_calculation_foundation.sql'
completion_functions_path = ROOT / 'supabase/migrations/20260724102000_1117_completion_calculation_functions.sql'
completion_grants_path = ROOT / 'supabase/migrations/20260724102100_1118_completion_calculation_grants.sql'
completion_test_paths = [
    ROOT / 'supabase/tests/36_package_11_6_completion_schema.test.sql',
    ROOT / 'supabase/tests/37_package_11_6_completion_security.test.sql',
    ROOT / 'supabase/tests/38_package_11_6_completion_calculations.test.sql',
]
for path in (completion_schema_path, completion_functions_path, completion_grants_path, *completion_test_paths):
    require(path.exists(), f'Package 11.6 artifact exists: {path.relative_to(ROOT)}')

if completion_schema_path.exists():
    completion_schema_sql = completion_schema_path.read_text(encoding='utf-8').lower()
    for required in (
        'where t.counts_toward_completion = true',
        'and t.weight_percent is null',
        'counted project tasks require explicit completion weights before package 11.6',
        'drop constraint tasks_weight_ck',
        'constraint tasks_completion_weight_integrity_ck',
        'counts_toward_completion = true',
        'weight_percent is not null',
        'weight_percent > 0',
        'weight_percent <= 100',
        'counts_toward_completion = false',
        'weight_percent is null',
        'not valid',
        'validate constraint tasks_completion_weight_integrity_ck',
        'create or replace function app.normalize_project_task_weight',
        'project task weight is required when completion counting is enabled',
    ):
        require(required in completion_schema_sql,
                f'1116 completion foundation contains required marker: {required}')
    for forbidden in (
        'update app.tasks set weight_percent',
        'avg(',
        'equal weight',
        'completion_percent column',
        'create table app.project_completion_overrides',
        'create table app.progress_updates',
    ):
        require(forbidden not in completion_schema_sql,
                f'1116 completion foundation omits forbidden marker: {forbidden}')

if completion_functions_path.exists():
    completion_functions_sql = completion_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.calculate_project_phase_completion',
        'create or replace function app.calculate_project_completion',
        'create or replace function app.owner_project_phase_completion',
        'create or replace function app.owner_project_completion',
        'create or replace function app.current_client_project_phase_completion_for_authenticated_user',
        'create or replace function app.current_client_project_completion_for_authenticated_user',
        'create or replace function public.current_client_project_phase_completion',
        'create or replace function public.current_client_project_completion',
        'create or replace function public.server_owner_project_phase_completion',
        'create or replace function public.server_owner_project_completion',
        'round(',
        'sum(t.weight_percent * t.completion_percent)',
        'nullif(sum(t.weight_percent), 0)',
        '0.00',
        '::numeric(5,2)',
        "t.status <> 'cancelled'",
        't.is_active = true',
        't.counts_toward_completion = true',
        't.weight_percent is not null',
        't.phase_id = p_phase_id',
        't.project_id = p_project_id',
        'app.require_active_owner_admin',
        'u.auth_subject = auth.uid()',
        "u.user_type = 'client'",
        "ur.role_code = 'client'",
        'r.is_staff_role',
    ):
        require(required in completion_functions_sql,
                f'1117 completion functions contain required marker: {required}')
    for forbidden in (
        'insert into app.activity_logs',
        'app.write_activity_log',
        'update app.tasks',
        'update app.projects',
        'update app.project_phases',
        'create materialized view',
        'project_completion_cache',
        'phase_completion_cache',
        'current_project_manager_completion',
        'current_site_supervisor_completion',
        'current_accountant_completion',
        'current_assigned_project_completion',
    ):
        require(forbidden not in completion_functions_sql,
                f'1117 completion functions omit forbidden marker: {forbidden}')
    client_project_return = re.search(
        r'create or replace function public\.current_client_project_completion\(.*?returns table \((.*?)\)\s+language',
        completion_functions_sql,
        re.S,
    )
    require(client_project_return is not None, '1117 Client Project completion return shape is inspectable')
    if client_project_return:
        returned = client_project_return.group(1)
        for safe_field in ('project_id uuid', 'calculated_completion_percent numeric(5,2)'):
            require(safe_field in returned,
                    f'1117 Client Project completion returns safe field: {safe_field}')
        for forbidden_field in ('counted_task_count', 'total_weight', 'task_id', 'weight_percent'):
            require(forbidden_field not in returned,
                    f'1117 Client Project completion omits private field: {forbidden_field}')
    client_phase_return = re.search(
        r'create or replace function public\.current_client_project_phase_completion\(.*?returns table \((.*?)\)\s+language',
        completion_functions_sql,
        re.S,
    )
    require(client_phase_return is not None, '1117 Client phase completion return shape is inspectable')
    if client_phase_return:
        returned = client_phase_return.group(1)
        for safe_field in ('project_id uuid', 'phase_id uuid', 'calculated_completion_percent numeric(5,2)'):
            require(safe_field in returned,
                    f'1117 Client phase completion returns safe field: {safe_field}')
        for forbidden_field in ('counted_task_count', 'total_weight', 'task_id', 'weight_percent'):
            require(forbidden_field not in returned,
                    f'1117 Client phase completion omits private field: {forbidden_field}')

if completion_grants_path.exists():
    completion_grants_sql = completion_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.tasks from public, anon, authenticated, service_role',
        'revoke all on function app.calculate_project_phase_completion',
        'revoke all on function app.calculate_project_completion',
        'revoke all on function app.owner_project_phase_completion',
        'revoke all on function app.owner_project_completion',
        'revoke all on function app.current_client_project_phase_completion_for_authenticated_user',
        'revoke all on function app.current_client_project_completion_for_authenticated_user',
        'grant execute on function public.current_client_project_phase_completion(uuid) to authenticated',
        'grant execute on function public.current_client_project_completion(uuid) to authenticated',
        'grant execute on function public.server_owner_project_phase_completion(uuid, uuid) to service_role',
        'grant execute on function public.server_owner_project_completion(uuid, uuid) to service_role',
    ):
        require(required in completion_grants_sql,
                f'1118 completion grants contain required marker: {required}')
    for forbidden in (
        'grant select on app.tasks',
        'grant execute on function public.server_owner_project_completion(uuid, uuid) to authenticated',
        'grant execute on function public.current_project_manager_completion',
    ):
        require(forbidden not in completion_grants_sql,
                f'1118 completion grants omit forbidden marker: {forbidden}')

completion_scope_sql = '\n'.join(
    p.read_text(encoding='utf-8', errors='ignore').lower()
    for p in (completion_schema_path, completion_functions_path, completion_grants_path)
    if p.exists()
)
for forbidden in (
    'create table app.project_completion_overrides',
    'create table app.progress_updates',
    'create table app.project_completion_cache',
    'create table app.phase_completion_cache',
    'completion_percent numeric',
    'current_project_manager_completion',
    'current_site_supervisor_completion',
    'current_accountant_completion',
):
    if forbidden == 'completion_percent numeric':
        continue
    require(forbidden not in completion_scope_sql,
            f'Package 11.6 scope excludes forbidden object/function: {forbidden}')

flutter_completion_mentions = [
    p for p in (ROOT / 'app/lib').glob('**/*.dart')
    if p.is_file() and re.search(r'completion|progress|overdue|upcoming', p.read_text(encoding='utf-8', errors='ignore'), re.I)
]
require(not flutter_completion_mentions, 'no Flutter completion/progress UI added')
require(not any((ROOT / 'supabase/functions').glob('*completion*')), 'no completion Edge Function added')

override_schema_path = ROOT / 'supabase/migrations/20260724102200_1119_project_completion_overrides.sql'
override_functions_path = ROOT / 'supabase/migrations/20260724102300_1120_project_completion_override_functions.sql'
override_grants_path = ROOT / 'supabase/migrations/20260724102400_1121_project_completion_override_grants.sql'
override_test_paths = [
    ROOT / 'supabase/tests/39_package_11_7_completion_overrides_schema.test.sql',
    ROOT / 'supabase/tests/40_package_11_7_completion_overrides_security.test.sql',
    ROOT / 'supabase/tests/41_package_11_7_completion_overrides_operations.test.sql',
]
for path in (override_schema_path, override_functions_path, override_grants_path, *override_test_paths):
    require(path.exists(), f'Package 11.7 artifact exists: {path.relative_to(ROOT)}')

if override_schema_path.exists():
    override_schema_sql = override_schema_path.read_text(encoding='utf-8').lower()
    for required in (
        'create table app.project_completion_overrides',
        'id uuid primary key default gen_random_uuid()',
        'project_id uuid not null references app.projects(id) on delete restrict',
        'override_percent numeric(5,2) not null',
        'reason text not null',
        'effective_at timestamptz not null default transaction_timestamp()',
        'approved_at timestamptz',
        'approved_by uuid references app.users(id) on delete restrict',
        'revoked_at timestamptz',
        'revoked_by uuid references app.users(id) on delete restrict',
        'created_at timestamptz not null default transaction_timestamp()',
        'created_by uuid not null references app.users(id) on delete restrict',
        'project_completion_overrides_state_ck',
        'project_completion_overrides_approver_differs_ck',
        'project_completion_overrides_one_active_uk',
        'where approved_at is not null',
        'and revoked_at is null',
        'project_completion_overrides_project_history_idx',
        'before update on app.project_completion_overrides',
        'before delete on app.project_completion_overrides',
        'before truncate on app.project_completion_overrides',
        'alter table app.project_completion_overrides enable row level security',
        'alter table app.project_completion_overrides force row level security',
    ):
        require(required in override_schema_sql,
                f'1119 completion override schema contains required marker: {required}')
    for forbidden in (
        ' status ',
        'calculated_percent',
        'requested_percent',
        'client_id',
        'role_code',
        'updated_at',
        'updated_by',
        'version_number',
        'cancelled_at',
        'rejected_at',
        'archived_at',
        'deleted_at',
        'approved_at is null',
        'now()',
        'current_timestamp',
    ):
        if forbidden == 'now()':
            require('default now()' not in override_schema_sql and ' <= now()' not in override_schema_sql,
                    '1119 completion override schema omits time-relative now() table rules/defaults')
        elif forbidden == 'current_timestamp':
            require('current_timestamp' not in override_schema_sql,
                    '1119 completion override schema omits current_timestamp table rule')
        elif forbidden == 'approved_at is null':
            require(not re.search(r'create\s+unique\s+index[^;]*approved_at\s+is\s+null', override_schema_sql),
                    '1119 completion override schema omits pending unique index')
        else:
            require(forbidden not in override_schema_sql,
                    f'1119 completion override schema omits forbidden marker: {forbidden.strip()}')

if override_functions_path.exists():
    override_functions_sql = override_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.current_project_official_completion',
        'app.calculate_project_completion',
        'coalesce(active_override.override_percent, calculated.value)',
        'create or replace function app.owner_request_project_completion_override',
        'p_effective_at > workflow_at',
        'future project completion overrides are not supported',
        'project_completion_override_requested',
        'calculated_completion_percent',
        'official_completion_before_request',
        'proposed_override_percent',
        'create or replace function app.owner_approve_project_completion_override',
        'for update',
        'project completion override requires different owner approval',
        'app.allow_project_completion_override_approval',
        'app.allow_project_completion_override_revocation',
        'project_completion_override_approved',
        'project_completion_override_superseded',
        'create or replace function app.owner_revoke_project_completion_override',
        'project_completion_override_revoked',
        'create or replace function app.owner_official_project_completion',
        'create or replace function app.owner_project_completion_override_list',
        'create or replace function app.owner_project_completion_override_detail',
        'create or replace function app.current_client_project_completion_for_authenticated_user',
        'official_completion_percent',
        'is_overridden',
        'create or replace function public.current_client_project_completion',
        'create or replace function public.server_owner_request_project_completion_override',
        'create or replace function public.server_owner_approve_project_completion_override',
        'create or replace function public.server_owner_revoke_project_completion_override',
        'create or replace function public.server_owner_official_project_completion',
        'create or replace function public.server_owner_project_completion_override_list',
        'create or replace function public.server_owner_project_completion_override_detail',
        'app.require_active_owner_admin',
        'u.auth_subject = auth.uid()',
    ):
        require(required in override_functions_sql,
                f'1120 completion override functions contain required marker: {required}')
    client_return = re.search(
        r'create or replace function public\.current_client_project_completion\(.*?returns table \((.*?)\)\s+language',
        override_functions_sql,
        re.S,
    )
    require(client_return is not None, '1120 Client official completion return shape is inspectable')
    if client_return:
        returned = client_return.group(1)
        for safe_field in (
            'project_id uuid',
            'calculated_completion_percent numeric(5,2)',
            'official_completion_percent numeric(5,2)',
            'is_overridden boolean',
        ):
            require(safe_field in returned,
                    f'1120 Client official completion returns safe field: {safe_field}')
        for forbidden_field in (
            'active_override_id',
            'override_reason',
            'reason',
            'created_by',
            'approved_by',
            'revoked_by',
            'counted_task_count',
            'total_weight',
        ):
            require(forbidden_field not in returned,
                    f'1120 Client official completion omits private field: {forbidden_field}')
    for forbidden in (
        'current_project_manager_completion',
        'current_site_supervisor_completion',
        'current_accountant_completion',
        'current_assigned_project_completion',
        'create table app.progress_updates',
        'insert into app.notifications',
        'update app.projects set status',
        'update app.tasks set status',
    ):
        require(forbidden not in override_functions_sql,
                f'1120 completion override functions omit forbidden marker: {forbidden}')

if override_grants_path.exists():
    override_grants_sql = override_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.project_completion_overrides from public, anon, authenticated, service_role',
        'revoke all on function app.current_project_official_completion(uuid) from public, anon, authenticated, service_role',
        'revoke all on function app.owner_request_project_completion_override',
        'revoke all on function app.owner_approve_project_completion_override',
        'revoke all on function app.owner_revoke_project_completion_override',
        'grant execute on function public.server_owner_request_project_completion_override',
        'grant execute on function public.server_owner_approve_project_completion_override',
        'grant execute on function public.server_owner_revoke_project_completion_override',
        'grant execute on function public.server_owner_official_project_completion',
        'grant execute on function public.server_owner_project_completion_override_list',
        'grant execute on function public.server_owner_project_completion_override_detail',
        'grant execute on function public.current_client_project_completion(uuid) to authenticated',
    ):
        require(required in override_grants_sql,
                f'1121 completion override grants contain required marker: {required}')
    for forbidden in (
        'grant select on app.project_completion_overrides',
        'grant execute on function public.server_owner_request_project_completion_override(uuid, uuid, numeric, text, timestamptz, text, text, text, inet) to authenticated',
        'grant execute on function public.current_project_manager_completion',
    ):
        require(forbidden not in override_grants_sql,
                f'1121 completion override grants omit forbidden marker: {forbidden}')

override_all_sql = '\n'.join(
    p.read_text(encoding='utf-8', errors='ignore').lower()
    for p in (override_schema_path, override_functions_path, override_grants_path)
    if p.exists()
)
for forbidden in (
    'create table app.notifications',
    'create table app.progress_updates',
    'create table app.documents',
    'create table app.financial_transactions',
    'project_manager%access_allowed%true',
):
    require(forbidden not in override_all_sql,
            f'Package 11.7 scope excludes forbidden marker: {forbidden}')

progress_schema_path = ROOT / 'supabase/migrations/20260724102500_1122_progress_updates.sql'
progress_functions_path = ROOT / 'supabase/migrations/20260724102600_1123_progress_update_functions.sql'
progress_grants_path = ROOT / 'supabase/migrations/20260724102700_1124_progress_update_grants.sql'
progress_test_paths = [
    ROOT / 'supabase/tests/42_package_11_8_progress_updates_schema.test.sql',
    ROOT / 'supabase/tests/43_package_11_8_progress_updates_security.test.sql',
    ROOT / 'supabase/tests/44_package_11_8_progress_updates_operations.test.sql',
]
for path in (progress_schema_path, progress_functions_path, progress_grants_path, *progress_test_paths):
    require(path.exists(), f'Package 11.8 artifact exists: {path.relative_to(ROOT)}')

if progress_schema_path.exists():
    progress_schema_sql = progress_schema_path.read_text(encoding='utf-8').lower()
    for required in (
        'create type app.progress_update_status as enum',
        "'draft'",
        "'submitted'",
        "'approved'",
        "'rejected'",
        'create table app.progress_updates',
        'id uuid primary key default gen_random_uuid()',
        'project_id uuid not null references app.projects(id) on delete restrict',
        'milestone_id uuid references app.project_milestones(id) on delete restrict',
        'title varchar(200) not null',
        'summary text not null',
        'reported_completion_percent numeric(5,2)',
        'status app.progress_update_status not null default',
        'client_visible boolean not null default false',
        'archived_by uuid references app.users(id) on delete restrict',
        'version_number integer not null default 1',
        'progress_updates_state_ck',
        'progress_updates_publication_visibility_ck',
        'progress_updates_approver_differs_ck',
        'progress_updates_client_feed_idx',
        'before update on app.progress_updates',
        'before delete on app.progress_updates',
        'before truncate on app.progress_updates',
        'app.allow_progress_update_mutation',
        'alter table app.progress_updates enable row level security',
        'alter table app.progress_updates force row level security',
    ):
        require(required in progress_schema_sql,
                f'1122 progress schema contains required marker: {required}')
    for forbidden in (
        'task_id',
        'phase_id',
        'private_summary',
        'client_summary',
        'delay_reason',
        'next_planned_work',
        'create table app.notifications',
        'create table app.documents',
        'financial_transactions',
        "'published'",
        "'archived'",
    ):
        require(forbidden not in progress_schema_sql,
                f'1122 progress schema omits forbidden marker: {forbidden}')

if progress_functions_path.exists():
    progress_functions_sql = progress_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.owner_create_progress_update',
        'create or replace function app.owner_update_progress_update_draft',
        'create or replace function app.owner_submit_progress_update',
        'create or replace function app.owner_approve_progress_update',
        'create or replace function app.owner_reject_progress_update',
        'create or replace function app.owner_set_progress_update_client_visibility',
        'create or replace function app.owner_publish_progress_update',
        'create or replace function app.owner_archive_progress_update',
        'create or replace function app.owner_progress_update_list',
        'create or replace function app.owner_progress_update_detail',
        'create or replace function app.current_client_progress_update_list_for_authenticated_user',
        'create or replace function app.current_client_progress_update_detail_for_authenticated_user',
        'create or replace function public.current_client_progress_update_list',
        'create or replace function public.current_client_progress_update_detail',
        'create or replace function public.server_owner_create_progress_update',
        'create or replace function public.server_owner_set_progress_update_client_visibility',
        'create or replace function public.server_owner_publish_progress_update',
        'app.require_active_owner_admin',
        'progress_update_created',
        'progress_update_updated',
        'progress_update_submitted',
        'progress_update_approved',
        'progress_update_rejected',
        'progress_update_client_visibility_changed',
        'progress_update_published',
        'progress_update_archived',
        'progress update cannot be edited',
        'progress update requires different owner approval',
        'progress update visibility cannot be changed',
        'progress update cannot be published for this project client',
        'phase_row.is_active and phase_row.client_visible',
    ):
        require(required in progress_functions_sql,
                f'1123 progress functions contain required marker: {required}')
    for forbidden in (
        'current_project_manager_progress',
        'current_site_supervisor_progress',
        'current_accountant_progress',
        'current_assigned_progress',
        'insert into app.notifications',
        'update app.tasks',
        'insert into app.task_updates',
        'update app.projects set status',
        'create table app.notifications',
        'format(',
        'raw_app_meta_data',
    ):
        require(forbidden not in progress_functions_sql,
                f'1123 progress functions omit forbidden marker: {forbidden}')
    client_return = re.search(
        r'create or replace function public\.current_client_progress_update_list\(.*?returns table \((.*?)\)\s+language',
        progress_functions_sql,
        re.S,
    )
    require(client_return is not None, '1123 Client progress list return shape is inspectable')
    if client_return:
        returned = client_return.group(1)
        for safe_field in (
            'id uuid',
            'project_id uuid',
            'milestone_id uuid',
            'title text',
            'summary text',
            'reported_completion_percent numeric(5,2)',
            'published_at timestamptz',
        ):
            require(safe_field in returned,
                    f'1123 Client progress list returns safe field: {safe_field}')
        for private_field in (
            'status',
            'created_by',
            'updated_by',
            'submitted_by',
            'approved_by',
            'rejected_by',
            'rejection_reason',
            'version_number',
        ):
            require(private_field not in returned,
                    f'1123 Client progress list omits private field: {private_field}')

if progress_grants_path.exists():
    progress_grants_sql = progress_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.progress_updates from public, anon, authenticated, service_role',
        'revoke all on function app.owner_create_progress_update',
        'revoke all on function app.owner_publish_progress_update',
        'revoke all on function app.current_client_progress_update_list_for_authenticated_user',
        'grant execute on function public.server_owner_create_progress_update',
        'grant execute on function public.server_owner_publish_progress_update',
        'grant execute on function public.server_owner_set_progress_update_client_visibility',
        'grant execute on function public.current_client_progress_update_list(uuid, integer, integer) to authenticated',
        'grant execute on function public.current_client_progress_update_detail(uuid) to authenticated',
        'to service_role',
    ):
        require(required in progress_grants_sql,
                f'1124 progress grants contain required marker: {required}')
    for forbidden in (
        'grant select on app.progress_updates',
        'grant insert on app.progress_updates',
        'grant update on app.progress_updates',
        'grant delete on app.progress_updates',
        'current_project_manager_progress',
        'current_site_supervisor_progress',
        'current_assigned_progress',
    ):
        require(forbidden not in progress_grants_sql,
                f'1124 progress grants omit forbidden marker: {forbidden}')

progress_all_sql = '\n'.join(
    p.read_text(encoding='utf-8', errors='ignore').lower()
    for p in (progress_schema_path, progress_functions_path, progress_grants_path)
    if p.exists()
)
for forbidden in (
    'create table app.notifications',
    'create table app.documents',
    'create table app.financial_transactions',
    'create table app.ledger_entries',
    'task_id',
    'delay_reason',
    'next_planned_work',
    'project_manager%access_allowed%true',
):
    require(forbidden not in progress_all_sql,
            f'Package 11.8 scope excludes forbidden marker: {forbidden}')

notification_schema_path = ROOT / 'supabase/migrations/20260724102800_1125_notifications.sql'
notification_functions_path = ROOT / 'supabase/migrations/20260724102900_1126_notification_functions.sql'
notification_grants_path = ROOT / 'supabase/migrations/20260724103000_1127_notification_grants.sql'
notification_test_paths = [
    ROOT / 'supabase/tests/45_package_11_9_notifications_schema.test.sql',
    ROOT / 'supabase/tests/46_package_11_9_notifications_security.test.sql',
    ROOT / 'supabase/tests/47_package_11_9_notifications_operations.test.sql',
]
for path in (notification_schema_path, notification_functions_path, notification_grants_path, *notification_test_paths):
    require(path.exists(), f'Package 11.9 artifact exists: {path.relative_to(ROOT)}')

if notification_schema_path.exists():
    notification_schema_sql = notification_schema_path.read_text(encoding='utf-8').lower()
    for required in (
        'create type app.notification_status as enum',
        "'unread'",
        "'read'",
        "'archived'",
        'create table app.notifications',
        'id uuid primary key default gen_random_uuid()',
        'recipient_user_id uuid not null references app.users(id) on delete restrict',
        'project_id uuid references app.projects(id) on delete restrict',
        'notification_type varchar(60) not null',
        'title varchar(200) not null',
        'body text not null',
        "status app.notification_status not null default 'unread'",
        'related_entity_type varchar(60)',
        'related_entity_id uuid',
        'created_at timestamptz not null default transaction_timestamp()',
        'read_at timestamptz',
        'archived_at timestamptz',
        'notifications_related_pair_ck',
        'notifications_state_ck',
        'notifications_timestamp_order_ck',
        'notifications_recipient_inbox_idx',
        'notifications_recipient_unread_idx',
        'notifications_project_context_idx',
        'notifications_related_unique_idx',
        'where related_entity_type is not null',
        'app.notification_creation_context',
        'app.notification_state_context',
        'before insert on app.notifications',
        'before update on app.notifications',
        'before delete on app.notifications',
        'before truncate on app.notifications',
        'alter table app.notifications enable row level security',
        'alter table app.notifications force row level security',
    ):
        require(required in notification_schema_sql,
                f'1125 notification schema contains required marker: {required}')
    for forbidden in (
        'delivery_status',
        'delivery_channel',
        'email_address',
        'phone_number',
        'sent_at',
        'delivered_at',
        'retry_count',
        'next_retry_at',
        'link_url',
        'deep_link',
        'payload',
        'metadata jsonb',
        'created_by',
        'updated_at',
        'version_number',
        'deleted_at',
        "'pending'",
        "'sent'",
        "'failed'",
        "'dismissed'",
    ):
        require(forbidden not in notification_schema_sql,
                f'1125 notification schema omits forbidden marker: {forbidden}')

if notification_functions_path.exists():
    notification_functions_sql = notification_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.current_notification_recipient_context',
        'create or replace function app.create_progress_update_published_notification',
        "current_setting('app.notification_creation_context'",
        'progress_update_publication',
        'progress update notification recipient is not available',
        'progress_update_published',
        'progress_update',
        'progress_update_published',
        'new project progress update',
        'a new progress update is available for your project.',
        'on conflict (recipient_user_id, notification_type, related_entity_type, related_entity_id)',
        'create or replace function app.owner_publish_progress_update',
        'notification_id',
        'notification_created',
        'create or replace function app.current_notification_list_for_authenticated_user',
        'p_status = \'archived\'',
        'p_include_archived',
        'order by n.created_at desc, n.id desc',
        'create or replace function app.current_notification_detail_for_authenticated_user',
        'create or replace function app.current_mark_notification_read_for_authenticated_user',
        'coalesce(n.read_at, workflow_at)',
        'notification_marked_read',
        'create or replace function app.current_mark_notification_unread_for_authenticated_user',
        'notification_marked_unread',
        'create or replace function app.current_archive_notification_for_authenticated_user',
        'notification_archived',
        'archived notification cannot be changed',
        'create or replace function public.current_notification_list',
        'create or replace function public.current_notification_detail',
        'create or replace function public.current_mark_notification_read',
        'create or replace function public.current_mark_notification_unread',
        'create or replace function public.current_archive_notification',
    ):
        require(required in notification_functions_sql,
                f'1126 notification functions contain required marker: {required}')
    for forbidden in (
        'create or replace function public.server_create_notification',
        'current_project_manager_notifications',
        'current_site_supervisor_notifications',
        'current_accountant_notifications',
        'current_assigned_notifications',
        'current_notification_unread_count',
        'insert into app.notification_delivery',
        'insert into app.notification_preferences',
        'insert into app.task_updates',
        'update app.tasks',
        'format(',
        'raw_app_meta_data',
        'progress_row.title',
        'progress_row.summary',
    ):
        require(forbidden not in notification_functions_sql,
                f'1126 notification functions omit forbidden marker: {forbidden}')
    client_return = re.search(
        r'create or replace function public\.current_notification_list\(.*?returns table \((.*?)\)\s+language',
        notification_functions_sql,
        re.S,
    )
    require(client_return is not None, '1126 current notification list return shape is inspectable')
    if client_return:
        returned = client_return.group(1)
        for safe_field in (
            'id uuid',
            'project_id uuid',
            'notification_type text',
            'title text',
            'body text',
            'status app.notification_status',
            'related_entity_type text',
            'related_entity_id uuid',
            'created_at timestamptz',
            'read_at timestamptz',
            'archived_at timestamptz',
        ):
            require(safe_field in returned,
                    f'1126 notification list returns safe field: {safe_field}')
        require('recipient_user_id' not in returned,
                '1126 notification list omits recipient_user_id')

if notification_grants_path.exists():
    notification_grants_sql = notification_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.notifications from public, anon, authenticated, service_role',
        'revoke all on function app.create_progress_update_published_notification(uuid) from public, anon, authenticated, service_role',
        'revoke all on function app.current_notification_list_for_authenticated_user',
        'grant execute on function public.current_notification_list(app.notification_status, boolean, integer, integer) to authenticated',
        'grant execute on function public.current_notification_detail(uuid) to authenticated',
        'grant execute on function public.current_mark_notification_read(uuid) to authenticated',
        'grant execute on function public.current_mark_notification_unread(uuid) to authenticated',
        'grant execute on function public.current_archive_notification(uuid) to authenticated',
        'grant execute on function public.server_owner_publish_progress_update',
        'to service_role',
    ):
        require(required in notification_grants_sql,
                f'1127 notification grants contain required marker: {required}')
    for forbidden in (
        'grant select on app.notifications',
        'grant insert on app.notifications',
        'grant update on app.notifications',
        'grant delete on app.notifications',
        'grant execute on function app.create_progress_update_published_notification(uuid) to service_role',
        'current_project_manager_notifications',
        'current_assigned_notifications',
    ):
        require(forbidden not in notification_grants_sql,
                f'1127 notification grants omit forbidden marker: {forbidden}')

notification_all_sql = '\n'.join(
    p.read_text(encoding='utf-8', errors='ignore').lower()
    for p in (notification_schema_path, notification_functions_path, notification_grants_path)
    if p.exists()
)
for forbidden in (
    'create table app.notification_delivery_attempts',
    'create table app.notification_preferences',
    'create table app.notification_retry_queue',
    'create table app.documents',
    'create table app.financial_transactions',
    'create table app.ledger_entries',
    'upcoming',
    'overdue',
    'payment_request',
    'expense',
    'document_notification',
    'project_manager%access_allowed%true',
):
    require(forbidden not in notification_all_sql,
            f'Package 11.9 scope excludes forbidden marker: {forbidden}')

document_schema_path = ROOT / 'supabase/migrations/20260724103100_1128_documents.sql'
document_functions_path = ROOT / 'supabase/migrations/20260724103200_1129_document_functions.sql'
document_grants_path = ROOT / 'supabase/migrations/20260724103300_1130_document_grants.sql'
document_test_paths = [
    ROOT / 'supabase/tests/48_package_12_1_documents_schema.test.sql',
    ROOT / 'supabase/tests/49_package_12_1_documents_security.test.sql',
    ROOT / 'supabase/tests/50_package_12_1_documents_operations.test.sql',
]
for path in (document_schema_path, document_functions_path, document_grants_path, *document_test_paths):
    require(path.exists(), f'Package 12.1 artifact exists: {path.relative_to(ROOT)}')

if document_schema_path.exists():
    document_schema_sql = document_schema_path.read_text(encoding='utf-8').lower()
    for required in (
        'create sequence app.document_number_seq',
        "('doc-' || lpad(nextval('app.document_number_seq')::text, 6, '0'))",
        'create type app.document_status as enum',
        "'active'",
        "'archived'",
        'create table app.document_types',
        'code varchar(50) primary key',
        'name varchar(120) not null',
        'default_client_visible boolean not null default false',
        'is_active boolean not null default true',
        'create table app.documents',
        'document_number varchar(60) not null',
        'storage_bucket varchar(100) not null',
        'storage_object_key text not null',
        'original_file_name varchar(255) not null',
        'mime_type varchar(150) not null',
        'file_size_bytes bigint not null',
        'sha256_hash bytea not null',
        'document_type_code varchar(50) not null',
        "status app.document_status not null default 'active'",
        'client_visible boolean not null default false',
        'uploaded_at timestamptz not null default transaction_timestamp()',
        'uploaded_by uuid not null',
        'archived_at timestamptz',
        'archived_by uuid',
        'documents_document_number_uk unique',
        'documents_storage_object_key_uk unique',
        'documents_uploaded_by_fk',
        'documents_archived_by_fk',
        'octet_length(sha256_hash) = 32',
        'file_size_bytes > 0',
        'documents_archive_pair_ck',
        'documents_status_archive_ck',
        'create table app.document_links',
        'client_payment_id uuid',
        'payment_request_id uuid',
        'project_expense_id uuid',
        'currency_exchange_id uuid',
        'document_links_exactly_one_target_ck',
        'document_links_finance_targets_disabled_ck',
        'document_links_client_fk',
        'document_links_project_fk',
        'document_links_task_fk',
        'document_links_progress_update_fk',
        'alter table app.documents enable row level security',
        'alter table app.document_links force row level security',
    ):
        require(required in document_schema_sql,
                f'1128 document schema contains required marker: {required}')
    for forbidden in (
        'create table app.client_payments',
        'create table app.payment_requests',
        'create table app.project_expenses',
        'create table app.currency_exchanges',
        'references app.client_payments',
        'references app.payment_requests',
        'references app.project_expenses',
        'references app.currency_exchanges',
        'mime_type in',
        'max_file_size',
        'retention',
        'quarantine',
        'scanner',
        'thumbnail',
        'signed_url',
        'bucket create',
    ):
        require(forbidden not in document_schema_sql,
                f'1128 document schema omits forbidden marker: {forbidden}')

if document_functions_path.exists():
    document_functions_sql = document_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.owner_create_document_metadata',
        'create or replace function app.owner_archive_document_metadata',
        'create or replace function app.owner_link_document',
        'create or replace function app.current_client_document_list_for_authenticated_user',
        'create or replace function public.current_client_document_list',
        'create or replace function public.server_owner_create_document_metadata',
        'create or replace function public.server_owner_archive_document_metadata',
        'create or replace function public.server_owner_link_document',
        'finance document link targets are not enabled',
        'document type code must be uppercase and stable',
        'd.status = \'active\'',
        'd.client_visible',
    ):
        require(required in document_functions_sql,
                f'1129 document functions contain required marker: {required}')
    for forbidden in (
        'create or replace function public.current_project_manager_document',
        'create or replace function public.current_accountant_document',
        'create or replace function public.current_site_supervisor_document',
        'upload_document',
        'document_upload',
        'download',
        'signed',
        'scanner',
        'thumbnail',
        'storage.objects',
        'create table app.client_payments',
        'create table app.payment_requests',
        'create table app.project_expenses',
        'create table app.currency_exchanges',
        'raw_app_meta_data',
    ):
        require(forbidden not in document_functions_sql,
                f'1129 document functions omit forbidden marker: {forbidden}')

if document_grants_path.exists():
    document_grants_sql = document_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.document_types from public, anon, authenticated, service_role',
        'revoke all on app.documents from public, anon, authenticated, service_role',
        'revoke all on app.document_links from public, anon, authenticated, service_role',
        'grant execute on function public.current_client_document_list(integer, integer) to authenticated',
        'grant execute on function public.server_owner_create_document_metadata',
        'grant execute on function public.server_owner_archive_document_metadata',
        'grant execute on function public.server_owner_link_document',
        'to service_role',
    ):
        require(required in document_grants_sql,
                f'1130 document grants contain required marker: {required}')
    for forbidden in (
        'grant select on app.documents',
        'grant insert on app.documents',
        'grant update on app.documents',
        'grant delete on app.documents',
        'current_project_manager_document',
        'current_accountant_document',
        'current_site_supervisor_document',
    ):
        require(forbidden not in document_grants_sql,
                f'1130 document grants omit forbidden marker: {forbidden}')

document_all_sql = '\n'.join(
    p.read_text(encoding='utf-8', errors='ignore').lower()
    for p in (document_schema_path, document_functions_path, document_grants_path)
    if p.exists()
)
for forbidden in (
    'create table app.client_payments',
    'create table app.payment_requests',
    'create table app.project_expenses',
    'create table app.currency_exchanges',
    'create table app.document_scans',
    'create table app.document_thumbnails',
    'storage.objects',
    'signed_url',
    'edge function',
    'project_manager%access_allowed%true',
):
    require(forbidden not in document_all_sql,
            f'Package 12.1 scope excludes forbidden marker: {forbidden}')

commands_path = ROOT / 'docs/COMMANDS.md'
require(commands_path.exists(), 'docs/COMMANDS.md exists')
if commands_path.exists():
    commands_sql = commands_path.read_text(encoding='utf-8').lower()
    for required in (
        'stage 12 package 12.1: document metadata foundation',
        'package 12.1 adds document metadata only',
        'doc-000001',
        'doc-000002',
        'app.document_status',
        'app.document_types',
        'app.documents',
        'app.document_links',
        'finance target columns remain nullable but constrained to `null`',
        'no placeholder finance tables are created',
        'owner/admin may manage metadata',
        'client may read only client-visible metadata linked to their own readable records',
        'project manager, accountant, and site supervisor remain unusable/default-denied',
    ):
        require(required in commands_sql,
                f'docs/COMMANDS.md documents Package 12.1 boundary marker: {required}')

package_12_1_global_exclusion_markers = (
    'storage.objects',
    'storage.buckets',
    'create bucket',
    'create storage bucket',
    'upload_document',
    'document_upload',
    'download_document',
    'document_download',
    'signed_url',
    'signed url',
    'create signed',
    'scanner',
    'thumbnail',
    'create table app.document_scans',
    'create table app.document_thumbnails',
    'create table app.client_payments',
    'create table app.payment_requests',
    'create table app.project_expenses',
    'create table app.currency_exchanges',
    'references app.client_payments',
    'references app.payment_requests',
    'references app.project_expenses',
    'references app.currency_exchanges',
    'current_project_manager_document',
    'current_accountant_document',
    'current_site_supervisor_document',
    'project_manager%access_allowed%true',
    'accountant%access_allowed%true',
    'site_supervisor%access_allowed%true',
    'mime_type in (',
    'max_file_size',
    'retention_period',
    'quarantine_period',
    'scanner_policy',
)
package_12_1_scope_files = [
    *migrations,
    *sorted((ROOT / 'supabase/functions').rglob('*')),
    *sorted((ROOT / 'app/lib').rglob('*')),
]
for path in package_12_1_scope_files:
    if path.exists() and path.is_file():
        text = path.read_text(encoding='utf-8', errors='ignore').lower()
        for forbidden in package_12_1_global_exclusion_markers:
            require(forbidden not in text,
                    f'Package 12.1 global exclusion marker absent from {path.relative_to(ROOT)}: {forbidden}')

financial_account_schema_path = ROOT / 'supabase/migrations/20260724103400_1131_financial_account_schema.sql'
financial_account_functions_path = ROOT / 'supabase/migrations/20260724103500_1132_financial_account_functions.sql'
financial_account_grants_path = ROOT / 'supabase/migrations/20260724103600_1133_financial_account_grants.sql'
financial_account_test_paths = [
    ROOT / 'supabase/tests/51_package_13_1_financial_accounts_schema.test.sql',
    ROOT / 'supabase/tests/52_package_13_1_financial_accounts_security.test.sql',
    ROOT / 'supabase/tests/53_package_13_1_financial_accounts_operations.test.sql',
]
for path in (financial_account_schema_path, financial_account_functions_path, financial_account_grants_path, *financial_account_test_paths):
    require(path.exists(), f'Package 13.1 artifact exists: {path.relative_to(ROOT)}')

if financial_account_schema_path.exists():
    financial_account_schema_sql = financial_account_schema_path.read_text(encoding='utf-8').lower()
    for required in (
        'create sequence app.financial_account_number_seq',
        "default ('fa-' || lpad(nextval('app.financial_account_number_seq')::text, 6, '0'))",
        "create type app.financial_account_type as enum ('cash', 'bank')",
        'create table app.financial_accounts',
        'id uuid primary key default gen_random_uuid()',
        'account_number varchar(50) not null',
        'name varchar(160) not null',
        'account_type app.financial_account_type not null',
        'currency_code char(3) not null',
        'bank_name varchar(160)',
        'masked_account_identifier varchar(80)',
        'encrypted_account_details bytea',
        'is_active boolean not null default true',
        'notes text',
        'archived_at timestamptz',
        'archived_by uuid',
        'created_at timestamptz not null default now()',
        'created_by uuid not null',
        'updated_at timestamptz not null default now()',
        'updated_by uuid not null',
        'version_number integer not null default 1',
        "account_number ~ '^fa-[0-9]{6}$'",
        'financial_accounts_cash_bank_metadata_ck',
        'alter table app.financial_accounts enable row level security',
        'alter table app.financial_accounts force row level security',
        'revoke all on app.financial_accounts from public, anon, authenticated, service_role',
    ):
        require(required in financial_account_schema_sql,
                f'1131 financial account schema contains required marker: {required}')
    approved_columns = [
        'id', 'account_number', 'name', 'account_type', 'currency_code', 'bank_name',
        'masked_account_identifier', 'encrypted_account_details', 'is_active', 'notes',
        'archived_at', 'archived_by', 'created_at', 'created_by', 'updated_at',
        'updated_by', 'version_number',
    ]
    for column in approved_columns:
        require(re.search(rf'(?m)^\s*{column}\s+', financial_account_schema_sql) is not None,
                f'1131 app.financial_accounts approved column exists: {column}')
    for forbidden in (
        'create type app.financial_account_status',
        ' status ',
        'display_name',
        'current_balance',
        'opening_balance',
        'ledger_account_id',
        'bank_account_holder_name',
        'bank_account_last_four',
        'bank_branch',
        'bank_swift_code',
        'bank_iban_last_four',
        'internal_notes',
        'activated_at',
        'activated_by',
        'deactivated_at',
        'deactivated_by',
        'create table app.ledger_accounts',
        'create table app.ledger_entries',
        'create table app.financial_transactions',
    ):
        require(forbidden not in financial_account_schema_sql,
                f'1131 financial account schema omits forbidden marker: {forbidden}')

if financial_account_functions_path.exists():
    financial_account_functions_sql = financial_account_functions_path.read_text(encoding='utf-8').lower()
    for required in (
        'create or replace function app.owner_create_financial_account',
        'create or replace function app.owner_update_financial_account',
        'create or replace function app.owner_activate_financial_account',
        'create or replace function app.owner_deactivate_financial_account',
        'create or replace function app.owner_archive_financial_account',
        'create or replace function app.owner_financial_account_list',
        'create or replace function app.owner_financial_account_detail',
        'create or replace function public.server_owner_create_financial_account',
        'create or replace function public.server_owner_update_financial_account',
        'create or replace function public.server_owner_activate_financial_account',
        'create or replace function public.server_owner_deactivate_financial_account',
        'create or replace function public.server_owner_archive_financial_account',
        'create or replace function public.server_owner_financial_account_list',
        'create or replace function public.server_owner_financial_account_detail',
        'app.require_active_owner_admin',
        'financial_account_created',
        'financial_account_updated',
        'financial_account_activated',
        'financial_account_deactivated',
        'financial_account_archived',
        'financial account version conflict',
    ):
        require(required in financial_account_functions_sql,
                f'1132 financial account functions contain required marker: {required}')
    list_return = re.search(
        r'create or replace function public\.server_owner_financial_account_list\(.*?returns table \((.*?)\)\s+language',
        financial_account_functions_sql,
        re.S,
    )
    detail_return = re.search(
        r'create or replace function public\.server_owner_financial_account_detail\(.*?returns table \((.*?)\)\s+language',
        financial_account_functions_sql,
        re.S,
    )
    require(list_return is not None, '1132 Owner financial account list return shape is inspectable')
    require(detail_return is not None, '1132 Owner financial account detail return shape is inspectable')
    for label, match in (('list', list_return), ('detail', detail_return)):
        if match:
            returned = match.group(1)
            require('encrypted_account_details' not in returned,
                    f'1132 Owner financial account {label} omits encrypted details')
    for forbidden in (
        'current_financial_account',
        'current_client_financial',
        'current_accountant_financial',
        'current_project_manager_financial',
        'current_site_supervisor_financial',
        'insert into app.ledger',
        'insert into app.financial_transactions',
        'current_balance',
        'opening_balance',
        'create table app.notifications',
        'format(',
        'raw_app_meta_data',
    ):
        require(forbidden not in financial_account_functions_sql,
                f'1132 financial account functions omit forbidden marker: {forbidden}')

if financial_account_grants_path.exists():
    financial_account_grants_sql = financial_account_grants_path.read_text(encoding='utf-8').lower()
    for required in (
        'revoke all on app.financial_accounts from public, anon, authenticated, service_role',
        'revoke all on sequence app.financial_account_number_seq from public, anon, authenticated, service_role',
        'revoke all on function app.owner_create_financial_account',
        'revoke all on function app.owner_financial_account_list',
        'grant execute on function public.server_owner_create_financial_account',
        'grant execute on function public.server_owner_update_financial_account',
        'grant execute on function public.server_owner_activate_financial_account',
        'grant execute on function public.server_owner_deactivate_financial_account',
        'grant execute on function public.server_owner_archive_financial_account',
        'grant execute on function public.server_owner_financial_account_list',
        'grant execute on function public.server_owner_financial_account_detail',
        'to service_role',
    ):
        require(required in financial_account_grants_sql,
                f'1133 financial account grants contain required marker: {required}')
    for forbidden in (
        'grant select on app.financial_accounts',
        'grant insert on app.financial_accounts',
        'grant update on app.financial_accounts',
        'grant delete on app.financial_accounts',
        'to authenticated',
        'current_accountant_financial',
        'current_project_manager_financial',
        'current_site_supervisor_financial',
    ):
        require(forbidden not in financial_account_grants_sql,
                f'1133 financial account grants omit forbidden marker: {forbidden}')

financial_account_all_sql = '\n'.join(
    p.read_text(encoding='utf-8', errors='ignore').lower()
    for p in (financial_account_schema_path, financial_account_functions_path, financial_account_grants_path)
    if p.exists()
)
for forbidden in (
    'create table app.ledger_accounts',
    'create table app.ledger_entries',
    'create table app.financial_transactions',
    'create table app.exchange_rates',
    'create table app.payments',
    'create table app.expenses',
    'create table app.transfers',
    'current_balance',
    'opening_balance',
    'public.current_account()',
    'accountant%access_allowed%true',
):
    require(forbidden not in financial_account_all_sql,
            f'Package 13.1 scope excludes forbidden marker: {forbidden}')

for path in ROOT.rglob('*'):
    if path.is_file() and '.git' not in path.parts and path.name != '.env.example':
        text = path.read_text(encoding='utf-8', errors='ignore')
        require(not re.search(
            r'(?m)^\s*(?:export\s+)?SUPABASE_SERVICE_ROLE_KEY\s*=\s*'
            r'(?!replace-in-secret-store\s*$)(?!\$\{)[A-Za-z0-9_-]{20,}\s*$',
            text,
        ), f'no real service-role assignment in {path.relative_to(ROOT)}')

print(f'PASSED: {len(passes)}')
for item in passes:
    print(f'  PASS {item}')
print(f'FAILED: {len(errors)}')
for item in errors:
    print(f'  FAIL {item}')

sys.exit(1 if errors else 0)
