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
require([p.name for p in migrations] == sorted(p.name for p in migrations), 'migration names are ordered')

for path in migrations:
    try:
        parse_sql(path.read_text(encoding='utf-8'))
        passes.append(f'PostgreSQL syntax parsed: {path.name}')
    except Exception as exc:
        errors.append(f'PostgreSQL parse failed: {path.name}: {exc}')

assertion_pattern = re.compile(
    r'(?im)^\s*SELECT\s+'
    r'(?:has_schema|has_type|has_table|hasnt_table|has_column|has_index|'
    r'hasnt_column|col_type_is|has_function|function_lang_is|volatility_is|isnt|is|is_empty|ok|lives_ok|'
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
    'create table app.financial_accounts',
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
require('create table app.project_milestones' not in all_sql, '10.3 does not add milestones')
require('create table app.project_tasks' not in all_sql, '10.3 does not add tasks')
require('create table app.task_assignments' not in all_sql, '10.3 does not add task assignments')
require('create table app.documents' not in all_sql and 'create table app.project_documents' not in all_sql, '10.3 does not add documents')
require('create table app.financial_transactions' not in all_sql and 'create table app.ledger_entries' not in all_sql, '10.3 does not add finance or ledger objects')

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
