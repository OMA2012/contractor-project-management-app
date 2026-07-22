BEGIN;

-- Application identity mapped one-to-one to Supabase Auth.
-- Passwords, password hashes, refresh tokens and verification secrets remain in auth.users.
CREATE TABLE app.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_subject uuid NOT NULL,
  email citext NOT NULL,
  user_type app.user_type NOT NULL,
  status app.user_status NOT NULL DEFAULT 'INVITED',
  is_active boolean NOT NULL DEFAULT false,
  last_login_at timestamptz,
  deactivated_at timestamptz,
  deactivated_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT users_auth_subject_uk UNIQUE (auth_subject),
  CONSTRAINT users_email_uk UNIQUE (email),
  CONSTRAINT users_auth_subject_fk
    FOREIGN KEY (auth_subject) REFERENCES auth.users(id) ON DELETE RESTRICT,
  CONSTRAINT users_deactivated_by_fk
    FOREIGN KEY (deactivated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT users_created_by_fk
    FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT users_updated_by_fk
    FOREIGN KEY (updated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT users_email_ck CHECK (
    email::text = lower(btrim(email::text))
    AND position('@' in email::text) > 1
  ),
  CONSTRAINT users_version_ck CHECK (version_number >= 1),
  CONSTRAINT users_lifecycle_ck CHECK (
    (status = 'INVITED' AND NOT is_active
      AND deactivated_at IS NULL AND deactivated_by IS NULL)
    OR
    (status = 'ACTIVE' AND is_active
      AND deactivated_at IS NULL AND deactivated_by IS NULL)
    OR
    (status = 'SUSPENDED' AND NOT is_active
      AND deactivated_at IS NULL AND deactivated_by IS NULL)
    OR
    (status = 'DISABLED' AND NOT is_active
      AND deactivated_at IS NOT NULL AND deactivated_by IS NOT NULL)
  )
);

CREATE INDEX users_active_status_idx
  ON app.users(status, user_type)
  WHERE is_active;

CREATE TABLE app.user_profiles (
  user_id uuid PRIMARY KEY,
  full_name varchar(160) NOT NULL,
  phone varchar(40),
  job_title varchar(120),
  avatar_object_key text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NOT NULL,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT user_profiles_user_fk
    FOREIGN KEY (user_id) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT user_profiles_created_by_fk
    FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT user_profiles_updated_by_fk
    FOREIGN KEY (updated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT user_profiles_full_name_ck CHECK (btrim(full_name) <> ''),
  CONSTRAINT user_profiles_phone_ck CHECK (
    phone IS NULL OR btrim(phone) ~ '^\\+?[0-9][0-9 ()-]{5,38}$'
  ),
  CONSTRAINT user_profiles_version_ck CHECK (version_number >= 1)
);

CREATE INDEX user_profiles_full_name_idx
  ON app.user_profiles (lower(full_name));

ALTER TABLE app.contractor_profiles
  ADD CONSTRAINT contractor_profiles_created_by_fk
    FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  ADD CONSTRAINT contractor_profiles_updated_by_fk
    FOREIGN KEY (updated_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  ALTER COLUMN created_by SET NOT NULL,
  ALTER COLUMN updated_by SET NOT NULL;

COMMIT;
