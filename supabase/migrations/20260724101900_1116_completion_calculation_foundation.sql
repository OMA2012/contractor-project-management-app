BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM app.tasks AS t
    WHERE t.counts_toward_completion = true
      AND t.weight_percent IS NULL
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'Counted Project tasks require explicit completion weights before Package 11.6.';
  END IF;
END
$$;

ALTER TABLE app.tasks
  DROP CONSTRAINT tasks_weight_ck;

ALTER TABLE app.tasks
  ADD CONSTRAINT tasks_completion_weight_integrity_ck CHECK (
    (
      counts_toward_completion = true
      AND weight_percent IS NOT NULL
      AND weight_percent > 0
      AND weight_percent <= 100
    )
    OR (
      counts_toward_completion = false
      AND weight_percent IS NULL
    )
  ) NOT VALID;

ALTER TABLE app.tasks
  VALIDATE CONSTRAINT tasks_completion_weight_integrity_ck;

CREATE OR REPLACE FUNCTION app.normalize_project_task_weight(
  p_counts_toward_completion boolean,
  p_weight_percent numeric
)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF p_counts_toward_completion IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task completion-counting setting.';
  END IF;
  IF p_counts_toward_completion AND p_weight_percent IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task weight is required when completion counting is enabled.';
  END IF;
  IF NOT p_counts_toward_completion AND p_weight_percent IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Project task weight is not allowed when completion counting is disabled.';
  END IF;
  IF p_weight_percent IS NOT NULL AND (p_weight_percent <= 0 OR p_weight_percent > 100) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid Project task weight.';
  END IF;
  RETURN p_weight_percent;
END
$function$;

COMMIT;
