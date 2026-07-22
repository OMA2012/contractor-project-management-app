BEGIN;

CREATE TABLE app.contractor_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  singleton_key smallint NOT NULL DEFAULT 1,
  legal_name varchar(200) NOT NULL,
  display_name varchar(150) NOT NULL,
  registration_number varchar(100),
  default_reporting_currency_code char(3) NOT NULL,
  time_zone varchar(64) NOT NULL DEFAULT 'Asia/Kuching',
  date_format varchar(20) NOT NULL DEFAULT 'YYYY-MM-DD',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  version_number integer NOT NULL DEFAULT 1,
  CONSTRAINT contractor_profiles_singleton_key_uk UNIQUE (singleton_key),
  CONSTRAINT contractor_profiles_singleton_key_ck CHECK (singleton_key = 1),
  CONSTRAINT contractor_profiles_legal_name_ck CHECK (btrim(legal_name) <> ''),
  CONSTRAINT contractor_profiles_display_name_ck CHECK (btrim(display_name) <> ''),
  CONSTRAINT contractor_profiles_time_zone_ck CHECK (btrim(time_zone) <> ''),
  CONSTRAINT contractor_profiles_date_format_ck CHECK (btrim(date_format) <> ''),
  CONSTRAINT contractor_profiles_version_ck CHECK (version_number >= 1),
  CONSTRAINT contractor_profiles_currency_fk
    FOREIGN KEY (default_reporting_currency_code)
    REFERENCES app.currencies(code)
    ON DELETE RESTRICT
);

COMMIT;
