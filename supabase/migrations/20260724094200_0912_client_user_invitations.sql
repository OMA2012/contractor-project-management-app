BEGIN;

CREATE TABLE app.user_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invited_user_id uuid NOT NULL,
  token_hash bytea NOT NULL,
  status varchar(20) NOT NULL,
  expires_at timestamptz NOT NULL,
  accepted_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid,
  revoke_reason text,
  invited_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  resent_from_invitation_id uuid,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT user_invitations_invited_user_fk
    FOREIGN KEY (invited_user_id) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT user_invitations_revoked_by_fk
    FOREIGN KEY (revoked_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT user_invitations_invited_by_fk
    FOREIGN KEY (invited_by) REFERENCES app.users(id) ON DELETE RESTRICT,
  CONSTRAINT user_invitations_resent_from_fk
    FOREIGN KEY (resent_from_invitation_id) REFERENCES app.user_invitations(id) ON DELETE RESTRICT,
  CONSTRAINT user_invitations_status_ck CHECK (
    status IN ('PENDING', 'ACCEPTED', 'REVOKED', 'EXPIRED')
  ),
  CONSTRAINT user_invitations_token_hash_length_ck CHECK (
    octet_length(token_hash) = 32
  ),
  CONSTRAINT user_invitations_expiry_ck CHECK (
    expires_at = created_at + interval '7 days'
  ),
  CONSTRAINT user_invitations_version_ck CHECK (version_number >= 1),
  CONSTRAINT user_invitations_lifecycle_ck CHECK (
    (status = 'PENDING'
      AND accepted_at IS NULL
      AND revoked_at IS NULL
      AND revoked_by IS NULL
      AND revoke_reason IS NULL)
    OR
    (status = 'ACCEPTED'
      AND accepted_at IS NOT NULL
      AND revoked_at IS NULL
      AND revoked_by IS NULL
      AND revoke_reason IS NULL)
    OR
    (status = 'REVOKED'
      AND accepted_at IS NULL
      AND revoked_at IS NOT NULL
      AND revoked_by IS NOT NULL
      AND btrim(coalesce(revoke_reason, '')) <> '')
    OR
    (status = 'EXPIRED'
      AND accepted_at IS NULL
      AND revoked_at IS NULL
      AND revoked_by IS NULL
      AND revoke_reason IS NULL)
  )
);

CREATE UNIQUE INDEX user_invitations_token_hash_uk
  ON app.user_invitations(token_hash);

CREATE UNIQUE INDEX user_invitations_one_pending_user_idx
  ON app.user_invitations(invited_user_id)
  WHERE status = 'PENDING';

CREATE INDEX user_invitations_invited_user_idx
  ON app.user_invitations(invited_user_id, created_at);

ALTER TABLE app.user_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.user_invitations FORCE ROW LEVEL SECURITY;

REVOKE ALL ON app.user_invitations FROM PUBLIC, anon, authenticated;

COMMIT;
