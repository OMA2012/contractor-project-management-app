BEGIN;

CREATE OR REPLACE FUNCTION app.touch_versioned_row()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  NEW.updated_at := now();
  NEW.version_number := OLD.version_number + 1;
  RETURN NEW;
END
$function$;

CREATE TRIGGER contractor_profiles_touch_version
BEFORE UPDATE ON app.contractor_profiles
FOR EACH ROW EXECUTE FUNCTION app.touch_versioned_row();

CREATE TRIGGER users_touch_version
BEFORE UPDATE ON app.users
FOR EACH ROW EXECUTE FUNCTION app.touch_versioned_row();

CREATE TRIGGER user_profiles_touch_version
BEFORE UPDATE ON app.user_profiles
FOR EACH ROW EXECUTE FUNCTION app.touch_versioned_row();

CREATE OR REPLACE FUNCTION app.is_active_owner(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM app.users AS u
    JOIN app.user_roles AS ur ON ur.user_id = u.id
    WHERE u.id = p_user_id
      AND u.status = 'ACTIVE'
      AND u.is_active
      AND ur.role_code = 'owner_admin'
      AND ur.is_active
  );
$function$;

REVOKE ALL ON FUNCTION app.is_active_owner(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION app.is_active_owner(uuid) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION app.validate_user_role_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  target_type app.user_type;
  active_owner_count integer;
  actor_id uuid;
  is_bootstrap boolean;
BEGIN
  SELECT u.user_type
  INTO target_type
  FROM app.users AS u
  WHERE u.id = NEW.user_id;

  IF target_type IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'Role target user does not exist.';
  END IF;

  IF target_type = 'CLIENT' AND NEW.role_code <> 'client' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Client identities may receive only the client role.';
  END IF;

  IF target_type = 'STAFF' AND NEW.role_code = 'client' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Staff identities cannot receive the client role.';
  END IF;

  IF TG_OP = 'INSERT' THEN
    actor_id := NEW.assigned_by;
    is_bootstrap := NEW.role_code = 'owner_admin'
      AND NEW.user_id = NEW.assigned_by
      AND current_setting('app.allow_owner_bootstrap', true) = 'on';

    SELECT count(DISTINCT ur.user_id)
    INTO active_owner_count
    FROM app.user_roles AS ur
    JOIN app.users AS u ON u.id = ur.user_id
    WHERE ur.role_code = 'owner_admin'
      AND ur.is_active
      AND u.status = 'ACTIVE'
      AND u.is_active;

    IF active_owner_count = 0 AND is_bootstrap THEN
      RETURN NEW;
    END IF;

    IF NOT app.is_active_owner(actor_id) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only an active Owner/Administrator may assign roles.';
    END IF;

    IF NEW.user_id = actor_id THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Users may not assign roles to themselves.';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.role_code IS DISTINCT FROM OLD.role_code
       OR NEW.assigned_at IS DISTINCT FROM OLD.assigned_at
       OR NEW.assigned_by IS DISTINCT FROM OLD.assigned_by THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Role assignment identity and assignment history are immutable.';
    END IF;

    IF NOT OLD.is_active THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Revoked role history cannot be edited or reactivated.';
    END IF;

    IF NEW.is_active THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Active role assignments may only transition to revoked.';
    END IF;

    IF NOT app.is_active_owner(NEW.revoked_by) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only an active Owner/Administrator may revoke roles.';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION app.validate_user_role_change() FROM PUBLIC;
REVOKE ALL ON FUNCTION app.validate_user_role_change() FROM anon, authenticated;

CREATE TRIGGER user_roles_validate_change
BEFORE INSERT OR UPDATE ON app.user_roles
FOR EACH ROW EXECUTE FUNCTION app.validate_user_role_change();

CREATE OR REPLACE FUNCTION app.protect_last_active_owner_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  remaining_owner_count integer;
  removes_active_owner boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    removes_active_owner := OLD.role_code = 'owner_admin' AND OLD.is_active;
  ELSE
    removes_active_owner := OLD.role_code = 'owner_admin'
      AND OLD.is_active
      AND NOT NEW.is_active;
  END IF;

  IF NOT removes_active_owner THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM app.users AS u
    WHERE u.id = OLD.user_id
      AND u.status = 'ACTIVE'
      AND u.is_active
  ) THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('app.last_active_owner', 0));

  SELECT count(DISTINCT ur.user_id)
  INTO remaining_owner_count
  FROM app.user_roles AS ur
  JOIN app.users AS u ON u.id = ur.user_id
  WHERE ur.role_code = 'owner_admin'
    AND ur.is_active
    AND u.status = 'ACTIVE'
    AND u.is_active
    AND ur.id <> OLD.id;

  IF remaining_owner_count = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'At least one active Owner/Administrator must remain.';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION app.protect_last_active_owner_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION app.protect_last_active_owner_role() FROM anon, authenticated;

CREATE TRIGGER user_roles_last_owner_guard
BEFORE UPDATE OR DELETE ON app.user_roles
FOR EACH ROW EXECUTE FUNCTION app.protect_last_active_owner_role();

CREATE OR REPLACE FUNCTION app.protect_user_identity_and_last_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  remaining_owner_count integer;
BEGIN
  IF NEW.auth_subject <> OLD.auth_subject THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Authentication identity cannot be changed.';
  END IF;

  IF NEW.user_type <> OLD.user_type
     AND EXISTS (SELECT 1 FROM app.user_roles AS ur WHERE ur.user_id = OLD.id) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'User type cannot change after role history exists.';
  END IF;

  IF OLD.status = 'ACTIVE'
     AND OLD.is_active
     AND (NEW.status <> 'ACTIVE' OR NOT NEW.is_active)
     AND EXISTS (
       SELECT 1
       FROM app.user_roles AS ur
       WHERE ur.user_id = OLD.id
         AND ur.role_code = 'owner_admin'
         AND ur.is_active
     ) THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('app.last_active_owner', 0));

    SELECT count(DISTINCT ur.user_id)
    INTO remaining_owner_count
    FROM app.user_roles AS ur
    JOIN app.users AS u ON u.id = ur.user_id
    WHERE ur.role_code = 'owner_admin'
      AND ur.is_active
      AND u.status = 'ACTIVE'
      AND u.is_active
      AND u.id <> OLD.id;

    IF remaining_owner_count = 0 THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'The last active Owner/Administrator cannot be deactivated.';
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION app.protect_user_identity_and_last_owner() FROM PUBLIC;
REVOKE ALL ON FUNCTION app.protect_user_identity_and_last_owner() FROM anon, authenticated;

CREATE TRIGGER users_identity_and_last_owner_guard
BEFORE UPDATE ON app.users
FOR EACH ROW EXECUTE FUNCTION app.protect_user_identity_and_last_owner();

CREATE OR REPLACE FUNCTION app.protect_system_role_definition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'System role definitions cannot be deleted.';
  END IF;

  IF NEW.code <> OLD.code
     OR NEW.name <> OLD.name
     OR NEW.is_staff_role <> OLD.is_staff_role
     OR NEW.description <> OLD.description THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'System role definition fields are immutable.';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER roles_protect_definition
BEFORE UPDATE OR DELETE ON app.roles
FOR EACH ROW EXECUTE FUNCTION app.protect_system_role_definition();

CREATE OR REPLACE FUNCTION app.prevent_foundation_hard_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = format('%I rows cannot be permanently deleted.', TG_TABLE_NAME);
END
$function$;

CREATE TRIGGER contractor_profiles_no_delete
BEFORE DELETE ON app.contractor_profiles
FOR EACH ROW EXECUTE FUNCTION app.prevent_foundation_hard_delete();

CREATE TRIGGER users_no_delete
BEFORE DELETE ON app.users
FOR EACH ROW EXECUTE FUNCTION app.prevent_foundation_hard_delete();

CREATE TRIGGER user_profiles_no_delete
BEFORE DELETE ON app.user_profiles
FOR EACH ROW EXECUTE FUNCTION app.prevent_foundation_hard_delete();

CREATE TRIGGER user_roles_no_delete
BEFORE DELETE ON app.user_roles
FOR EACH ROW EXECUTE FUNCTION app.prevent_foundation_hard_delete();

COMMIT;
