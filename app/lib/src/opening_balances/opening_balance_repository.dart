import 'package:supabase_flutter/supabase_flutter.dart';

import 'opening_balance_models.dart';

typedef OpeningBalanceFunctionInvoke =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);

abstract class OpeningBalanceRepository {
  Future<List<OpeningBalance>> list();
  Future<OpeningBalance> detail(String financialEventId);
  Future<OpeningBalanceMutationResult> create(OpeningBalanceDraft draft);
  Future<OpeningBalanceMutationResult> update({
    required String financialEventId,
    required int expectedVersionNumber,
    required OpeningBalanceDraft draft,
  });
  Future<OpeningBalanceMutationResult> submit(String id, int version);
  Future<OpeningBalanceMutationResult> approve(String id, int version);
  Future<OpeningBalanceMutationResult> reject(
    String id,
    int version,
    String reason,
  );
  Future<List<FinancialApprovalQueueItem>> queue(String section);
}

class SupabaseOpeningBalanceRepository implements OpeningBalanceRepository {
  SupabaseOpeningBalanceRepository({this.invokeFunction});

  final OpeningBalanceFunctionInvoke? invokeFunction;
  SupabaseClient get client => Supabase.instance.client;

  @override
  Future<List<OpeningBalance>> list() async {
    final data = await _action({'action': 'list'});
    return (data['opening_balances'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(OpeningBalance.fromJson)
        .toList(growable: false);
  }

  @override
  Future<OpeningBalance> detail(String financialEventId) async {
    final data = await _action({
      'action': 'detail',
      'financial_event_id': financialEventId,
    });
    return OpeningBalance.fromJson(data['opening_balance']);
  }

  @override
  Future<OpeningBalanceMutationResult> create(OpeningBalanceDraft draft) async {
    final data = await _action({'action': 'create', ...draft.toJson()});
    return OpeningBalanceMutationResult.fromJson(data['opening_balance']);
  }

  @override
  Future<OpeningBalanceMutationResult> update({
    required String financialEventId,
    required int expectedVersionNumber,
    required OpeningBalanceDraft draft,
  }) async {
    final data = await _action({
      'action': 'update',
      'financial_event_id': financialEventId,
      'expected_version_number': expectedVersionNumber,
      ...draft.toJson()..remove('duplicate_fingerprint'),
    });
    return OpeningBalanceMutationResult.fromJson(data['opening_balance']);
  }

  @override
  Future<OpeningBalanceMutationResult> submit(String id, int version) =>
      _transition('submit', id, version);

  @override
  Future<OpeningBalanceMutationResult> approve(String id, int version) =>
      _transition('approve', id, version);

  @override
  Future<OpeningBalanceMutationResult> reject(
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
    return OpeningBalanceMutationResult.fromJson(data['opening_balance']);
  }

  @override
  Future<List<FinancialApprovalQueueItem>> queue(String section) async {
    final data = await _action({'action': 'queue', 'section': section});
    return (data['items'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(FinancialApprovalQueueItem.fromJson)
        .toList(growable: false);
  }

  Future<OpeningBalanceMutationResult> _transition(
    String action,
    String id,
    int version,
  ) async {
    final data = await _action({
      'action': action,
      'financial_event_id': id,
      'expected_version_number': version,
    });
    return OpeningBalanceMutationResult.fromJson(data['opening_balance']);
  }

  Future<Map<String, dynamic>> _action(Map<String, dynamic> body) async {
    final response = invokeFunction != null
        ? await invokeFunction!('opening-balances', body)
        : await client.functions.invoke('opening-balances', body: body);
    final envelope = response is FunctionResponse ? response.data : response;
    if (envelope is! Map<String, dynamic>) {
      throw const OpeningBalanceFailure('Opening balance response failed.');
    }
    if (envelope['error'] != null) {
      throw OpeningBalanceFailure(envelope['error'].toString());
    }
    final data = envelope['data'];
    if (data is Map<String, dynamic>) return data;
    return envelope;
  }
}

class OpeningBalanceFailure implements Exception {
  const OpeningBalanceFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
