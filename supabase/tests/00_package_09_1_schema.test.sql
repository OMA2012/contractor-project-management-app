BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(56);

SELECT has_schema('app', 'app schema exists');
SELECT has_type('app', 'user_status', 'user_status enum exists');
SELECT has_type('app', 'user_type', 'user_type enum exists');

SELECT has_table('app', 'currencies', 'currency reference table exists');
SELECT has_table('app', 'contractor_profiles', 'contractor singleton table exists');
SELECT has_table('app', 'users', 'application users table exists');
SELECT has_table('app', 'user_profiles', 'user profile table exists');
SELECT has_table('app', 'roles', 'predefined roles table exists');
SELECT has_table('app', 'user_roles', 'user-role history table exists');

SELECT hasnt_table('app', 'clients', 'clients are not implemented in Package 09.1');
SELECT hasnt_table('app', 'projects', 'projects are not implemented in Package 09.1');
SELECT hasnt_table('app', 'financial_accounts', 'financial accounts are not implemented');
SELECT hasnt_table('app', 'financial_transactions', 'financial transactions are not implemented');
SELECT hasnt_table('app', 'ledger_entries', 'ledger entries are not implemented');

SELECT has_column('app', 'contractor_profiles', 'id', 'contractor_profiles.id exists');
SELECT has_column('app', 'contractor_profiles', 'singleton_key', 'contractor_profiles.singleton_key exists');
SELECT has_column('app', 'contractor_profiles', 'legal_name', 'contractor_profiles.legal_name exists');
SELECT has_column('app', 'contractor_profiles', 'display_name', 'contractor_profiles.display_name exists');
SELECT has_column('app', 'contractor_profiles', 'default_reporting_currency_code', 'contractor_profiles.default_reporting_currency_code exists');
SELECT has_column('app', 'contractor_profiles', 'time_zone', 'contractor_profiles.time_zone exists');
SELECT has_column('app', 'contractor_profiles', 'version_number', 'contractor_profiles.version_number exists');

SELECT has_column('app', 'users', 'id', 'users.id exists');
SELECT has_column('app', 'users', 'auth_subject', 'users.auth_subject exists');
SELECT has_column('app', 'users', 'email', 'users.email exists');
SELECT has_column('app', 'users', 'user_type', 'users.user_type exists');
SELECT has_column('app', 'users', 'status', 'users.status exists');
SELECT has_column('app', 'users', 'is_active', 'users.is_active exists');
SELECT has_column('app', 'users', 'deactivated_at', 'users.deactivated_at exists');
SELECT has_column('app', 'users', 'deactivated_by', 'users.deactivated_by exists');
SELECT has_column('app', 'users', 'created_at', 'users.created_at exists');
SELECT has_column('app', 'users', 'created_by', 'users.created_by exists');
SELECT has_column('app', 'users', 'updated_at', 'users.updated_at exists');
SELECT has_column('app', 'users', 'updated_by', 'users.updated_by exists');

SELECT has_column('app', 'user_profiles', 'user_id', 'user_profiles.user_id exists');
SELECT has_column('app', 'user_profiles', 'full_name', 'user_profiles.full_name exists');
SELECT has_column('app', 'user_profiles', 'phone', 'user_profiles.phone exists');
SELECT has_column('app', 'user_profiles', 'job_title', 'user_profiles.job_title exists');
SELECT has_column('app', 'user_profiles', 'avatar_object_key', 'user_profiles.avatar_object_key exists');
SELECT has_column('app', 'user_profiles', 'notes', 'user_profiles.notes exists');

SELECT has_column('app', 'roles', 'code', 'roles.code exists');
SELECT has_column('app', 'roles', 'name', 'roles.name exists');
SELECT has_column('app', 'roles', 'is_staff_role', 'roles.is_staff_role exists');
SELECT has_column('app', 'roles', 'description', 'roles.description exists');
SELECT has_column('app', 'roles', 'is_active', 'roles.is_active exists');

SELECT has_column('app', 'user_roles', 'id', 'user_roles.id exists');
SELECT has_column('app', 'user_roles', 'user_id', 'user_roles.user_id exists');
SELECT has_column('app', 'user_roles', 'role_code', 'user_roles.role_code exists');
SELECT has_column('app', 'user_roles', 'assigned_at', 'user_roles.assigned_at exists');
SELECT has_column('app', 'user_roles', 'assigned_by', 'user_roles.assigned_by exists');
SELECT has_column('app', 'user_roles', 'revoked_at', 'user_roles.revoked_at exists');
SELECT has_column('app', 'user_roles', 'revoked_by', 'user_roles.revoked_by exists');
SELECT has_column('app', 'user_roles', 'revoke_reason', 'user_roles.revoke_reason exists');
SELECT has_column('app', 'user_roles', 'is_active', 'user_roles.is_active exists');

SELECT has_index('app', 'users', 'users_auth_subject_uk', 'users.auth_subject unique index exists');
SELECT has_index('app', 'users', 'users_email_uk', 'users.email unique index exists');
SELECT has_index('app', 'user_roles', 'user_roles_one_active_assignment_idx', 'user_roles one active assignment index exists');

SELECT * FROM finish();
ROLLBACK;
