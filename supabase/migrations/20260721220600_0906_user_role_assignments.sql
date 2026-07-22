BEGIN;

-- Historical rows are retained. A partial unique index permits a role to be
-- re-assigned after revocation without overwriting the earlier assignment row.
CREATE TABLE app.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  role_code varchar(40) NOT NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  assigned_by uuid NOT NULL,
  revoked_at timestamptz,
  revoked_by uuid,
  revoke_reason text,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT user_roles_user_fk
    FOREIGN KEY (user_id) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT user_roles_role_fk
    FOREIGN KEY (role_code) REFERENCES app.roles(code) ON DELETE RESTRICT,
  CONSTRAINT user_roles_assigned_by_fk
    FOREIGN KEY (assigned_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT user_roles_revoked_by_fk
    FOREIGN KEY (revoked_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT user_roles_lifecycle_ck CHECK (
    (is_active AND revoked_at IS NULL AND revoked_by IS NULL AND revoke_reason IS NULL)
    OR
    (NOT is_active AND revoked_at IS NOT NULL AND revoked_by IS NOT NULL
      AND btrim(coalesce(revoke_reason, '')) <> '')
  )
);

CREATE UNIQUE INDEX user_roles_one_active_assignment_idx
  ON app.user_roles(user_id, role_code)
  WHERE is_active;

CREATE INDEX user_roles_user_active_idx
  ON app.user_roles(user_id, role_code)
  WHERE is_active;

CREATE INDEX user_roles_role_active_idx
  ON app.user_roles(role_code, user_id)
  WHERE is_active;

COMMIT;
