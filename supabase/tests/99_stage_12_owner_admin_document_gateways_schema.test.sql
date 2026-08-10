BEGIN;
SELECT plan(39);

SELECT has_function('public','owner_admin_document_list',ARRAY['uuid','text','boolean','app.document_status','text','integer','integer'],'Owner/Admin document list RPC exists');
SELECT has_function('public','owner_admin_document_detail',ARRAY['uuid'],'Owner/Admin document detail RPC exists');
SELECT has_function('public','owner_admin_archive_document',ARRAY['uuid'],'Owner/Admin archive RPC exists');
SELECT has_function('public','owner_admin_restore_document',ARRAY['uuid','text'],'Owner/Admin restore RPC exists');
SELECT has_function('public','owner_admin_replace_document',ARRAY['uuid','uuid','text'],'Owner/Admin replacement RPC exists');
SELECT has_function('app','owner_admin_document_projection',ARRAY['uuid','uuid','uuid','text','boolean','app.document_status','text','integer','integer'],'private projection helper exists');

SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid='public.owner_admin_document_list(uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure), 'list is SECURITY DEFINER');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid='public.owner_admin_document_detail(uuid)'::regprocedure), 'detail is SECURITY DEFINER');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid='public.owner_admin_archive_document(uuid)'::regprocedure), 'archive is SECURITY DEFINER');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid='public.owner_admin_restore_document(uuid,text)'::regprocedure), 'restore is SECURITY DEFINER');
SELECT ok((SELECT prosecdef FROM pg_proc WHERE oid='public.owner_admin_replace_document(uuid,uuid,text)'::regprocedure), 'replace is SECURITY DEFINER');
SELECT is((SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid='public.owner_admin_document_list(uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure), 'search_path=""', 'list has safe search_path');
SELECT is((SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid='public.owner_admin_document_detail(uuid)'::regprocedure), 'search_path=""', 'detail has safe search_path');
SELECT is((SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid='public.owner_admin_archive_document(uuid)'::regprocedure), 'search_path=""', 'archive has safe search_path');
SELECT is((SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid='public.owner_admin_restore_document(uuid,text)'::regprocedure), 'search_path=""', 'restore has safe search_path');
SELECT is((SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid='public.owner_admin_replace_document(uuid,uuid,text)'::regprocedure), 'search_path=""', 'replace has safe search_path');

SELECT ok(has_function_privilege('authenticated','public.owner_admin_document_list(uuid,text,boolean,app.document_status,text,integer,integer)','EXECUTE'), 'authenticated can execute list');
SELECT ok(has_function_privilege('authenticated','public.owner_admin_document_detail(uuid)','EXECUTE'), 'authenticated can execute detail');
SELECT ok(has_function_privilege('authenticated','public.owner_admin_archive_document(uuid)','EXECUTE'), 'authenticated can execute archive');
SELECT ok(has_function_privilege('authenticated','public.owner_admin_restore_document(uuid,text)','EXECUTE'), 'authenticated can execute restore');
SELECT ok(has_function_privilege('authenticated','public.owner_admin_replace_document(uuid,uuid,text)','EXECUTE'), 'authenticated can execute replace');
SELECT ok(NOT has_function_privilege('anon','public.owner_admin_document_list(uuid,text,boolean,app.document_status,text,integer,integer)','EXECUTE'), 'anon cannot execute list');
SELECT ok(NOT has_function_privilege('anon','public.owner_admin_document_detail(uuid)','EXECUTE'), 'anon cannot execute detail');
SELECT ok(NOT has_function_privilege('anon','public.owner_admin_archive_document(uuid)','EXECUTE'), 'anon cannot execute archive');
SELECT ok(NOT has_function_privilege('anon','public.owner_admin_restore_document(uuid,text)','EXECUTE'), 'anon cannot execute restore');
SELECT ok(NOT has_function_privilege('anon','public.owner_admin_replace_document(uuid,uuid,text)','EXECUTE'), 'anon cannot execute replace');
SELECT ok(NOT has_function_privilege('authenticated','public.server_owner_restore_document_metadata(uuid,uuid,text)','EXECUTE'), 'authenticated still cannot execute service restore');
SELECT ok(NOT has_function_privilege('authenticated','public.server_owner_declare_document_replacement(uuid,uuid,uuid,text)','EXECUTE'), 'authenticated still cannot execute service replacement');
SELECT ok(NOT has_function_privilege('authenticated','public.server_owner_document_lifecycle_history(uuid,uuid)','EXECUTE'), 'authenticated still cannot execute lifecycle history');
SELECT ok(NOT has_function_privilege('authenticated','public.server_owner_archive_document_metadata(uuid,uuid)','EXECUTE'), 'authenticated still cannot execute service archive');

SELECT ok((SELECT pg_get_functiondef('public.owner_admin_document_list(uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure)) ILIKE '%auth.uid()%', 'list derives caller from auth.uid');
SELECT ok((SELECT pg_get_functiondef('public.owner_admin_document_detail(uuid)'::regprocedure)) ILIKE '%auth.uid()%', 'detail derives caller from auth.uid');
SELECT ok((SELECT pg_get_functiondef('public.owner_admin_archive_document(uuid)'::regprocedure)) ILIKE '%auth.uid()%', 'archive derives caller from auth.uid');
SELECT ok((SELECT pg_get_functiondef('public.owner_admin_restore_document(uuid,text)'::regprocedure)) ILIKE '%auth.uid()%', 'restore derives caller from auth.uid');
SELECT ok((SELECT pg_get_functiondef('public.owner_admin_replace_document(uuid,uuid,text)'::regprocedure)) ILIKE '%auth.uid()%', 'replace derives caller from auth.uid');
SELECT ok((SELECT pg_get_functiondef('public.owner_admin_archive_document(uuid)'::regprocedure)) ILIKE '%app.owner_archive_document_metadata%', 'archive delegates to authoritative function');
SELECT ok((SELECT pg_get_functiondef('public.owner_admin_restore_document(uuid,text)'::regprocedure)) ILIKE '%app.owner_restore_document_metadata%', 'restore delegates to authoritative function');
SELECT ok((SELECT pg_get_functiondef('public.owner_admin_replace_document(uuid,uuid,text)'::regprocedure)) ILIKE '%app.owner_declare_document_replacement%', 'replace delegates to authoritative function');
SELECT ok((SELECT pg_get_function_result('public.owner_admin_document_list(uuid,text,boolean,app.document_status,text,integer,integer)'::regprocedure)) NOT ILIKE '%bucket%' AND (SELECT pg_get_function_result('public.owner_admin_document_detail(uuid)'::regprocedure)) NOT ILIKE '%object%key%', 'list/detail return signatures omit Storage internals');

SELECT * FROM finish();
ROLLBACK;
