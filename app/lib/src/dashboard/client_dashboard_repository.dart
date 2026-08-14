import 'package:supabase_flutter/supabase_flutter.dart';

import 'client_dashboard_models.dart';

typedef ClientDashboardRpc =
    Future<dynamic> Function(
      String functionName, {
      Map<String, dynamic>? params,
    });

abstract class ClientDashboardRepository {
  Future<List<ClientDashboardProjectSummary>> listProjectSummaries({
    int limit = 6,
    int offset = 0,
  });

  Future<List<ClientDashboardRecentUpdate>> listRecentUpdates({
    int limit = 5,
    int offset = 0,
  });

  Future<List<ClientDashboardRecentActivity>> listRecentActivity({
    int limit = 8,
    int offset = 0,
  });
}

class SupabaseClientDashboardRepository implements ClientDashboardRepository {
  const SupabaseClientDashboardRepository({this.supabaseClient, this.rpc});

  final SupabaseClient? supabaseClient;
  final ClientDashboardRpc? rpc;

  SupabaseClient get client => supabaseClient ?? Supabase.instance.client;

  @override
  Future<List<ClientDashboardProjectSummary>> listProjectSummaries({
    int limit = 6,
    int offset = 0,
  }) async {
    final response = await _rpc('current_client_dashboard_project_summary', {
      'p_limit': _boundedLimit(limit),
      'p_offset': _validOffset(offset),
    });
    return _rows(
      response,
    ).map(ClientDashboardProjectSummary.fromJson).toList(growable: false);
  }

  @override
  Future<List<ClientDashboardRecentUpdate>> listRecentUpdates({
    int limit = 5,
    int offset = 0,
  }) async {
    final response = await _rpc(
      'current_client_dashboard_recent_'
      'pro'
      'gress',
      {'p_limit': _boundedLimit(limit), 'p_offset': _validOffset(offset)},
    );
    return _rows(
      response,
    ).map(ClientDashboardRecentUpdate.fromJson).toList(growable: false);
  }

  @override
  Future<List<ClientDashboardRecentActivity>> listRecentActivity({
    int limit = 8,
    int offset = 0,
  }) async {
    final response = await _rpc('current_client_recent_activity', {
      'p_limit': _boundedLimit(limit),
      'p_offset': _validOffset(offset),
    });
    return _rows(
      response,
    ).map(ClientDashboardRecentActivity.fromJson).toList(growable: false);
  }

  Future<dynamic> _rpc(String functionName, Map<String, dynamic> params) {
    final override = rpc;
    if (override != null) return override(functionName, params: params);
    return client.rpc(functionName, params: params);
  }

  int _boundedLimit(int limit) => limit.clamp(1, 100);

  int _validOffset(int offset) => offset < 0 ? 0 : offset;

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is List) {
      return response.cast<Map<String, dynamic>>();
    }
    if (response is Map<String, dynamic>) {
      return [response];
    }
    throw const ClientDashboardParseFailure(
      'Dashboard service response was invalid.',
    );
  }
}
