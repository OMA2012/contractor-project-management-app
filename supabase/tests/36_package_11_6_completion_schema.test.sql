BEGIN;
SELECT plan(30);

SELECT has_function('app', 'calculate_project_phase_completion', ARRAY['uuid']::name[], 'private phase calculation exists');
SELECT has_function('app', 'calculate_project_completion', ARRAY['uuid']::name[], 'private Project calculation exists');
SELECT has_function('app', 'owner_project_phase_completion', ARRAY['uuid','uuid']::name[], 'Owner phase completion exists');
SELECT has_function('app', 'owner_project_completion', ARRAY['uuid','uuid']::name[], 'Owner Project completion exists');
SELECT has_function('public', 'current_client_project_phase_completion', ARRAY['uuid']::name[], 'Client phase completion gateway exists');
SELECT has_function('public', 'current_client_project_completion', ARRAY['uuid']::name[], 'Client Project completion gateway exists');
SELECT ok(pg_get_function_result('app.calculate_project_phase_completion(uuid)'::regprocedure) = 'numeric', 'phase calculator returns numeric');
SELECT ok(pg_get_function_result('app.calculate_project_completion(uuid)'::regprocedure) = 'numeric', 'Project calculator returns numeric');
SELECT volatility_is('app', 'calculate_project_phase_completion', ARRAY['uuid']::name[], 'stable', 'phase calculator is stable');
SELECT volatility_is('app', 'calculate_project_completion', ARRAY['uuid']::name[], 'stable', 'Project calculator is stable');

SELECT ok((SELECT convalidated FROM pg_constraint WHERE conrelid = 'app.tasks'::regclass AND conname = 'tasks_completion_weight_integrity_ck'), 'strict task weight constraint is validated');
SELECT is_empty($$ SELECT 1 FROM pg_constraint WHERE conrelid = 'app.tasks'::regclass AND conname = 'tasks_weight_ck' $$, 'superseded task weight constraint removed');
SELECT throws_ok($$ INSERT INTO app.tasks (project_id, task_number, title, weight_percent, counts_toward_completion, created_by, updated_by) VALUES ('00000000-0000-0000-0000-000000000000', 'TSK-9999', 'Invalid Counted', NULL, true, '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000') $$, '23514', NULL, 'counted task requires non-null weight');
SELECT throws_ok($$ INSERT INTO app.tasks (project_id, task_number, title, weight_percent, counts_toward_completion, created_by, updated_by) VALUES ('00000000-0000-0000-0000-000000000000', 'TSK-9998', 'Invalid Noncounted', 10, false, '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000') $$, '23514', NULL, 'non-counting task requires null weight');
SELECT throws_ok($$ SELECT app.normalize_project_task_weight(true, NULL) $$, '23514', 'Project task weight is required when completion counting is enabled.', 'normalizer rejects counted null weight');
SELECT throws_ok($$ SELECT app.normalize_project_task_weight(false, 10) $$, '23514', 'Project task weight is not allowed when completion counting is disabled.', 'normalizer rejects non-counting weight');
SELECT throws_ok($$ SELECT app.normalize_project_task_weight(true, 0) $$, '23514', 'Invalid Project task weight.', 'zero weight rejected');
SELECT throws_ok($$ SELECT app.normalize_project_task_weight(true, 100.0001) $$, '23514', 'Invalid Project task weight.', 'weight above 100 rejected');
SELECT results_eq($$ SELECT app.normalize_project_task_weight(true, 100)::numeric $$, $$ VALUES (100::numeric) $$, 'weight 100 accepted');
SELECT results_eq($$ SELECT app.normalize_project_task_weight(false, NULL)::numeric $$, $$ VALUES (NULL::numeric) $$, 'non-counting null weight accepted');

SELECT hasnt_column('app', 'projects', 'completion_percent', 'no completion column on Projects');
SELECT hasnt_column('app', 'project_phases', 'completion_percent', 'no completion column on phases');
SELECT hasnt_column('app', 'project_milestones', 'completion_percent', 'no completion column on milestones');
SELECT hasnt_table('app', 'project_completion_overrides', 'no completion override table');
SELECT hasnt_table('app', 'project_completion_cache', 'no Project completion cache');
SELECT hasnt_table('app', 'phase_completion_cache', 'no phase completion cache');
SELECT hasnt_table('app', 'progress_updates', 'no progress update table');
SELECT ok((SELECT pg_get_functiondef('app.calculate_project_completion(uuid)'::regprocedure) ILIKE '%round(%' AND pg_get_functiondef('app.calculate_project_completion(uuid)'::regprocedure) ILIKE '%nullif(sum(t.weight_percent), 0)%' AND pg_get_functiondef('app.calculate_project_completion(uuid)'::regprocedure) ILIKE '%0.00%'), 'Project calculator uses rounded null-safe weighted formula');
SELECT ok((SELECT pg_get_functiondef('app.calculate_project_phase_completion(uuid)'::regprocedure) ILIKE '%t.phase_id = p_phase_id%'), 'phase calculator is scoped by phase_id');
SELECT ok((SELECT pg_get_functiondef('app.calculate_project_completion(uuid)'::regprocedure) ILIKE '%t.project_id = p_project_id%'), 'Project calculator is scoped by project_id');

SELECT * FROM finish();
ROLLBACK;
