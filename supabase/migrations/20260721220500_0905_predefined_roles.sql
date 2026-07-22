BEGIN;

CREATE TABLE app.roles (
  code varchar(40) PRIMARY KEY,
  name varchar(100) NOT NULL UNIQUE,
  is_staff_role boolean NOT NULL,
  description text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT roles_code_format_ck CHECK (code ~ '^[a-z_]+$'),
  CONSTRAINT roles_code_allowlist_ck CHECK (
    code IN (
      'owner_admin',
      'project_manager',
      'accountant',
      'site_supervisor',
      'client'
    )
  ),
  CONSTRAINT roles_name_ck CHECK (btrim(name) <> ''),
  CONSTRAINT roles_description_ck CHECK (btrim(description) <> ''),
  CONSTRAINT roles_staff_classification_ck CHECK (
    (code = 'client' AND NOT is_staff_role)
    OR
    (code <> 'client' AND is_staff_role)
  )
);

INSERT INTO app.roles (code, name, is_staff_role, description)
VALUES
  (
    'owner_admin',
    'Owner/Administrator',
    true,
    'Full authorised administration for the single contractor business.'
  ),
  (
    'project_manager',
    'Project Manager',
    true,
    'Manages only authorised and assigned project operations.'
  ),
  (
    'accountant',
    'Accountant',
    true,
    'Performs approved accounting preparation and financial review duties.'
  ),
  (
    'site_supervisor',
    'Site Supervisor',
    true,
    'Performs approved site and assigned-project operational duties.'
  ),
  (
    'client',
    'Client/Project Owner',
    false,
    'Accesses only the client records and projects authorised for that identity.'
  )
ON CONFLICT (code) DO UPDATE
SET
  name = EXCLUDED.name,
  is_staff_role = EXCLUDED.is_staff_role,
  description = EXCLUDED.description,
  is_active = true;

COMMIT;
