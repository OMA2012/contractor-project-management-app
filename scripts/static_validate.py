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
    r'hasnt_column|col_type_is|has_function|function_lang_is|volatility_is|isnt|is|ok|lives_ok|'
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
    'create table app.clients',
    'create table app.projects',
    'create table app.project_staff_assignments',
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
