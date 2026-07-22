BEGIN;

-- Reference dependency for contractor_profiles.default_reporting_currency_code.
-- This is not a financial account, transaction, balance, exchange, or ledger table.
CREATE TABLE app.currencies (
  code char(3) PRIMARY KEY,
  name varchar(100) NOT NULL UNIQUE,
  symbol varchar(12),
  decimal_digits smallint NOT NULL DEFAULT 2,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT currencies_code_ck CHECK (code ~ '^[A-Z]{3}$'),
  CONSTRAINT currencies_name_ck CHECK (btrim(name) <> ''),
  CONSTRAINT currencies_decimal_digits_ck CHECK (decimal_digits BETWEEN 0 AND 6)
);

INSERT INTO app.currencies (code, name, symbol, decimal_digits)
VALUES
  ('USD', 'United States Dollar', '$', 2),
  ('SAR', 'Saudi Riyal', 'SAR', 2),
  ('YER', 'Yemeni Rial', 'YER', 0)
ON CONFLICT (code) DO UPDATE
SET
  name = EXCLUDED.name,
  symbol = EXCLUDED.symbol,
  decimal_digits = EXCLUDED.decimal_digits,
  is_active = true;

COMMIT;
