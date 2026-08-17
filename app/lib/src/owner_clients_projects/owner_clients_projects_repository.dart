import 'package:supabase_flutter/supabase_flutter.dart';

import 'owner_clients_projects_models.dart';

typedef OwnerClientProjectInvoke =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);

class OwnerClientProjectFailure implements Exception {
  const OwnerClientProjectFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class OwnerClientsProjectsRepository {
  OwnerClientsProjectsRepository({this.invokeFunction});

  final OwnerClientProjectInvoke? invokeFunction;
  SupabaseClient get client => Supabase.instance.client;

  Future<List<OwnerClientRecord>> listClients() async {
    final data = await _action({'action': 'client_list'});
    return _list(data['clients']).map(OwnerClientRecord.fromJson).toList();
  }

  Future<OwnerClientRecord> clientDetail(String clientId) async {
    final data = await _action({
      'action': 'client_detail',
      'client_id': clientId,
    });
    return OwnerClientRecord.fromJson(data['client']);
  }

  Future<List<OwnerProjectRecord>> clientProjects(String clientId) async {
    final data = await _action({
      'action': 'client_projects',
      'client_id': clientId,
    });
    return _list(data['projects']).map(OwnerProjectRecord.fromJson).toList();
  }

  Future<OwnerClientRecord> saveClient({
    String? clientId,
    int? expectedVersionNumber,
    required String displayName,
    String? legalName,
    String? email,
    String? phone,
    String? address,
  }) async {
    final body = <String, dynamic>{
      'action': clientId == null ? 'client_create' : 'client_update',
      'display_name': displayName,
      'legal_name': legalName,
      'email': email,
      'phone': phone,
      'address': address,
    };
    if (clientId != null) body['client_id'] = clientId;
    if (expectedVersionNumber != null) {
      body['expected_version_number'] = expectedVersionNumber;
    }
    final data = await _action(body);
    return OwnerClientRecord.fromJson(data['client']);
  }

  Future<Map<String, dynamic>> invitationStatus(String clientId) =>
      _action({'action': 'invitation_status', 'client_id': clientId});

  Future<Map<String, dynamic>> sendInvitation(String clientId) =>
      _action({'action': 'invitation_send', 'client_id': clientId});

  Future<Map<String, dynamic>> resendInvitation(String invitedUserId) =>
      _action({
        'action': 'invitation_resend',
        'invited_user_id': invitedUserId,
      });

  Future<List<OwnerProjectRecord>> listProjects() async {
    final data = await _action({'action': 'project_list'});
    return _list(data['projects']).map(OwnerProjectRecord.fromJson).toList();
  }

  Future<OwnerProjectRecord> projectDetail(String projectId) async {
    final data = await _action({
      'action': 'project_detail',
      'project_id': projectId,
    });
    return OwnerProjectRecord.fromJson(data['project']);
  }

  Future<OwnerProjectRecord> saveProject({
    String? projectId,
    int? expectedVersionNumber,
    required String clientId,
    required String name,
    required String reportingCurrencyCode,
    String? projectType,
    String? location,
    String? clientVisibleSummary,
  }) async {
    final body = <String, dynamic>{
      'action': projectId == null ? 'project_create' : 'project_update',
      'client_id': clientId,
      'name': name,
      'reporting_currency_code': reportingCurrencyCode,
      'project_type': projectType,
      'location': location,
      'client_visible_summary': clientVisibleSummary,
    };
    if (projectId != null) body['project_id'] = projectId;
    if (expectedVersionNumber != null) {
      body['expected_version_number'] = expectedVersionNumber;
    }
    final data = await _action(body);
    return OwnerProjectRecord.fromJson(data['project']);
  }

  Future<OwnerProjectRecord> transitionProject({
    required String projectId,
    required int expectedVersionNumber,
    required String newStatus,
    String? cancellationReason,
  }) async {
    final body = <String, dynamic>{
      'action': 'project_transition',
      'project_id': projectId,
      'expected_version_number': expectedVersionNumber,
      'new_status': newStatus,
    };
    if (cancellationReason != null) {
      body['cancellation_reason'] = cancellationReason;
    }
    final data = await _action(body);
    return OwnerProjectRecord.fromJson(data['project']);
  }

  Future<Map<String, dynamic>> _action(Map<String, dynamic> body) async {
    final response = invokeFunction != null
        ? await invokeFunction!('client-projects', body)
        : await client.functions.invoke('client-projects', body: body);
    final envelope = response is FunctionResponse ? response.data : response;
    if (envelope is! Map<String, dynamic>) {
      throw const OwnerClientProjectFailure('Owner request failed.');
    }
    if (envelope['success'] == false || envelope['error'] != null) {
      throw OwnerClientProjectFailure(
        (envelope['message'] ?? envelope['error']).toString(),
      );
    }
    final data = envelope['data'];
    return data is Map<String, dynamic> ? data : envelope;
  }

  List<Map<String, dynamic>> _list(Object? value) =>
      ((value as List?) ?? const []).cast<Map<String, dynamic>>();
}
