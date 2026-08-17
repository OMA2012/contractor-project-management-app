import 'package:supabase_flutter/supabase_flutter.dart';

import 'project_expense_models.dart';

typedef ProjectExpenseFunctionInvoke =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);

class ProjectExpenseRepository {
  ProjectExpenseRepository({this.invokeFunction});
  final ProjectExpenseFunctionInvoke? invokeFunction;
  SupabaseClient get client => Supabase.instance.client;

  Future<List<ProjectExpense>> list() async {
    final data = await _action({'action': 'list'});
    return (data['project_expenses'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ProjectExpense.fromJson)
        .toList(growable: false);
  }

  Future<ProjectExpense> detail(String financialEventId) async {
    final data = await _action({
      'action': 'detail',
      'financial_event_id': financialEventId,
    });
    return ProjectExpense.fromJson(data['project_expense']);
  }

  Future<ProjectExpenseLookups> lookups() async {
    final data = await _action({'action': 'lookup'});
    return ProjectExpenseLookups(
      expenseCategories: (data['expense_categories'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ExpenseCategoryOption.fromJson)
          .toList(growable: false),
      projects: (data['projects'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ProjectOption.fromJson)
          .toList(growable: false),
    );
  }

  Future<ProjectExpenseMutationResult> create(ProjectExpenseDraft draft) async {
    final data = await _action({'action': 'create', ...draft.toJson()});
    return ProjectExpenseMutationResult.fromJson(data['project_expense']);
  }

  Future<ProjectExpenseMutationResult> update({
    required String financialEventId,
    required int expectedVersionNumber,
    required ProjectExpenseDraft draft,
  }) async {
    final data = await _action({
      'action': 'update',
      'financial_event_id': financialEventId,
      'expected_version_number': expectedVersionNumber,
      ...draft.toJson(),
    });
    return ProjectExpenseMutationResult.fromJson(data['project_expense']);
  }

  Future<ProjectExpenseMutationResult> submit(String id, int version) =>
      _transition('submit', id, version);
  Future<ProjectExpenseMutationResult> approve(String id, int version) =>
      _transition('approve', id, version);

  Future<ProjectExpenseMutationResult> reject(
    String id,
    int version,
    String reason,
  ) async {
    final data = await _action({
      'action': 'reject',
      'financial_event_id': id,
      'expected_version_number': version,
      'rejection_reason': reason,
    });
    return ProjectExpenseMutationResult.fromJson(data['project_expense']);
  }

  Future<ProjectExpenseMutationResult> _transition(
    String action,
    String id,
    int version,
  ) async {
    final data = await _action({
      'action': action,
      'financial_event_id': id,
      'expected_version_number': version,
    });
    return ProjectExpenseMutationResult.fromJson(data['project_expense']);
  }

  Future<Map<String, dynamic>> _action(Map<String, dynamic> body) async {
    final response = invokeFunction != null
        ? await invokeFunction!('project-expenses', body)
        : await client.functions.invoke('project-expenses', body: body);
    final envelope = response is FunctionResponse ? response.data : response;
    if (envelope is! Map<String, dynamic>) {
      throw const ProjectExpenseFailure('Project expense response failed.');
    }
    if (envelope['error'] != null) {
      throw ProjectExpenseFailure(envelope['error'].toString());
    }
    final data = envelope['data'];
    if (data is Map<String, dynamic>) return data;
    return envelope;
  }
}

class ProjectExpenseFailure implements Exception {
  const ProjectExpenseFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
