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
