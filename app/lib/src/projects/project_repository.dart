import 'package:supabase_flutter/supabase_flutter.dart';

import 'project_models.dart';

typedef ProjectRpc =
    Future<dynamic> Function(
      String functionName, {
      Map<String, dynamic>? params,
    });

abstract class ProjectRepository {
  Future<ClientProjectPage> listClientProjects({
    int limit = 50,
    int offset = 0,
  });

  Future<ClientProject?> getClientProject(String projectId);

  Future<ClientProjectCompletion?> getClientProjectCompletion(String projectId);

  Future<List<ClientProjectPhase>> getClientProjectPhases(String projectId);

  Future<ClientProjectPhaseCompletion?> getClientProjectPhaseCompletion(
    String phaseId,
  );

  Future<List<ClientProjectTask>> getClientProjectTasks(String projectId);

  Future<ClientProgressUpdatePage> listClientProgressUpdates(
    String projectId, {
    int limit = 50,
    int offset = 0,
  });
}

class SupabaseProjectRepository implements ProjectRepository {
  const SupabaseProjectRepository({this.supabaseClient, this.rpc});

  final SupabaseClient? supabaseClient;
  final ProjectRpc? rpc;

  SupabaseClient get client => supabaseClient ?? Supabase.instance.client;

  @override
  Future<ClientProjectPage> listClientProjects({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _rpc('current_client_project_records', {
      'p_limit': limit,
      'p_offset': offset,
    });
    final rows = _rows(response);
    return ClientProjectPage(
      rawCount: rows.length,
      projects: rows.map(ClientProject.fromJson).toList(growable: false),
    );
  }

  @override
  Future<ClientProject?> getClientProject(String projectId) async {
    final response = await _rpc('current_client_project_record', {
      'p_project_id': projectId,
    });
    final rows = _rows(response);
    if (rows.isEmpty) return null;
    return ClientProject.fromJson(rows.single);
  }

  @override
  Future<ClientProjectCompletion?> getClientProjectCompletion(
    String projectId,
  ) async {
    final response = await _rpc('current_client_project_completion', {
      'p_project_id': projectId,
    });
    final rows = _rows(response);
    if (rows.isEmpty) return null;
    return ClientProjectCompletion.fromJson(rows.single);
  }

  @override
  Future<List<ClientProjectPhase>> getClientProjectPhases(
    String projectId,
  ) async {
    final response = await _rpc('current_client_project_phases', {
      'p_project_id': projectId,
    });
    final rows = _rows(response);
    return rows.map(ClientProjectPhase.fromJson).toList(growable: false);
  }

  @override
  Future<ClientProjectPhaseCompletion?> getClientProjectPhaseCompletion(
    String phaseId,
  ) async {
    final response = await _rpc('current_client_project_phase_completion', {
      'p_phase_id': phaseId,
    });
    final rows = _rows(response);
    if (rows.isEmpty) return null;
    return ClientProjectPhaseCompletion.fromJson(rows.single);
  }

  @override
  Future<List<ClientProjectTask>> getClientProjectTasks(
    String projectId,
  ) async {
    final response = await _rpc('current_client_project_tasks', {
      'p_project_id': projectId,
    });
    final rows = _rows(response);
    return rows.map(ClientProjectTask.fromJson).toList(growable: false);
  }

  @override
  Future<ClientProgressUpdatePage> listClientProgressUpdates(
    String projectId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _rpc('current_client_progress_update_list', {
      'p_project_id': projectId,
      'p_limit': limit,
      'p_offset': offset,
    });
    final rows = _rows(response);
    return ClientProgressUpdatePage(
      rawCount: rows.length,
      items: rows.map(ClientProgressUpdate.fromJson).toList(growable: false),
    );
  }

  Future<dynamic> _rpc(String functionName, Map<String, dynamic> params) {
    if (rpc != null) return rpc!(functionName, params: params);
    return client.rpc(functionName, params: params);
  }

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is List) return response.cast<Map<String, dynamic>>();
    if (response is Map<String, dynamic>) return [response];
    return const [];
  }
}
