BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

SELECT has_function(
  'public',
  'server_owner_exchange_rate_picker_list',
  ARRAY['uuid','character','character','date','integer','integer'],
  'server exchange-rate picker lookup exists'
);

SELECT has_function(
  'public',
  'server_owner_expense_category_picker_list',
  ARRAY['uuid','integer','integer'],
  'server expense-category picker lookup exists'
);

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.server_owner_exchange_rate_picker_list(uuid, character, character, date, integer, integer)',
    'EXECUTE'
  ),
  'anon cannot execute exchange-rate picker lookup'
);

SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'public.server_owner_exchange_rate_picker_list(uuid, character, character, date, integer, integer)',
    'EXECUTE'
  ),
  'authenticated clients cannot execute exchange-rate picker lookup directly'
);

SELECT ok(
  has_function_privilege(
    'service_role',
    'public.server_owner_exchange_rate_picker_list(uuid, character, character, date, integer, integer)',
    'EXECUTE'
  ),
  'service role can execute exchange-rate picker lookup'
);

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.server_owner_expense_category_picker_list(uuid, integer, integer)',
    'EXECUTE'
  ),
  'anon cannot execute expense-category picker lookup'
);

SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'public.server_owner_expense_category_picker_list(uuid, integer, integer)',
    'EXECUTE'
  ),
  'authenticated clients cannot execute expense-category picker lookup directly'
);

SELECT ok(
  has_function_privilege(
    'service_role',
    'public.server_owner_expense_category_picker_list(uuid, integer, integer)',
    'EXECUTE'
  ),
  'service role can execute expense-category picker lookup'
);

SELECT * FROM finish();
ROLLBACK;
