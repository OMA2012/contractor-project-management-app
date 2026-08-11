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
