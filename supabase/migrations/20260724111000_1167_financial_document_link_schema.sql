BEGIN;

INSERT INTO app.document_types (code, name, default_client_visible, is_active)
VALUES
  ('PAYMENT_RECEIPT', 'Payment Receipt', false, true),
  ('BANK_TRANSFER_EVIDENCE', 'Bank Transfer Evidence', false, true),
  ('SUPPLIER_INVOICE', 'Supplier Invoice', false, true),
  ('EXPENSE_RECEIPT', 'Expense Receipt', false, true)
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    default_client_visible = false,
    is_active = true;

ALTER TABLE app.document_links
  DROP CONSTRAINT document_links_finance_targets_disabled_ck,
  ADD CONSTRAINT document_links_client_payment_fk FOREIGN KEY (client_payment_id) REFERENCES app.client_payments(id) ON DELETE RESTRICT,
  ADD CONSTRAINT document_links_payment_request_fk FOREIGN KEY (payment_request_id) REFERENCES app.payment_requests(id) ON DELETE RESTRICT,
  ADD CONSTRAINT document_links_project_expense_fk FOREIGN KEY (project_expense_id) REFERENCES app.project_expenses(id) ON DELETE RESTRICT,
  ADD CONSTRAINT document_links_currency_exchange_fk FOREIGN KEY (currency_exchange_id) REFERENCES app.currency_exchanges(id) ON DELETE RESTRICT;

CREATE INDEX document_links_client_payment_idx
  ON app.document_links(client_payment_id, created_at DESC, id DESC)
  WHERE client_payment_id IS NOT NULL;

CREATE INDEX document_links_payment_request_idx
  ON app.document_links(payment_request_id, created_at DESC, id DESC)
  WHERE payment_request_id IS NOT NULL;

CREATE INDEX document_links_project_expense_idx
  ON app.document_links(project_expense_id, created_at DESC, id DESC)
  WHERE project_expense_id IS NOT NULL;

CREATE INDEX document_links_currency_exchange_idx
  ON app.document_links(currency_exchange_id, created_at DESC, id DESC)
  WHERE currency_exchange_id IS NOT NULL;

ALTER TABLE app.document_uploads
  ADD COLUMN client_payment_id uuid,
  ADD COLUMN payment_request_id uuid,
  ADD COLUMN project_expense_id uuid,
  ADD COLUMN currency_exchange_id uuid,
  ADD CONSTRAINT document_uploads_client_payment_fk FOREIGN KEY (client_payment_id) REFERENCES app.client_payments(id) ON DELETE RESTRICT,
  ADD CONSTRAINT document_uploads_payment_request_fk FOREIGN KEY (payment_request_id) REFERENCES app.payment_requests(id) ON DELETE RESTRICT,
  ADD CONSTRAINT document_uploads_project_expense_fk FOREIGN KEY (project_expense_id) REFERENCES app.project_expenses(id) ON DELETE RESTRICT,
  ADD CONSTRAINT document_uploads_currency_exchange_fk FOREIGN KEY (currency_exchange_id) REFERENCES app.currency_exchanges(id) ON DELETE RESTRICT;

ALTER TABLE app.document_uploads
  DROP CONSTRAINT document_uploads_one_target_ck,
  ADD CONSTRAINT document_uploads_one_target_ck CHECK (
    num_nonnulls(client_id, project_id, task_id, progress_update_id, client_payment_id, payment_request_id, project_expense_id, currency_exchange_id) = 1
  );

CREATE INDEX document_uploads_client_payment_idx
  ON app.document_uploads(client_payment_id, status, id)
  WHERE client_payment_id IS NOT NULL;

CREATE INDEX document_uploads_payment_request_idx
  ON app.document_uploads(payment_request_id, status, id)
  WHERE payment_request_id IS NOT NULL;

CREATE INDEX document_uploads_project_expense_idx
  ON app.document_uploads(project_expense_id, status, id)
  WHERE project_expense_id IS NOT NULL;

CREATE INDEX document_uploads_currency_exchange_idx
  ON app.document_uploads(currency_exchange_id, status, id)
  WHERE currency_exchange_id IS NOT NULL;

COMMIT;
