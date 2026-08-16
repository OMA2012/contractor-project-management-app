import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_transfer_models.dart';

typedef AccountTransferFunctionInvoke =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);

class AccountTransferRepository {
  AccountTransferRepository({this.invokeFunction});
  final AccountTransferFunctionInvoke? invokeFunction;
  SupabaseClient get client => Supabase.instance.client;

  Future<List<AccountTransfer>> list() async {
    final data = await _action({'action': 'list'});
    return (data['account_transfers'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AccountTransfer.fromJson)
        .toList(growable: false);
  }

  Future<AccountTransfer> detail(String financialEventId) async {
    final data = await _action({
      'action': 'detail',
      'financial_event_id': financialEventId,
    });
    return AccountTransfer.fromJson(data['account_transfer']);
  }

  Future<AccountTransferMutationResult> create(
    AccountTransferDraft draft,
  ) async {
    final data = await _action({'action': 'create', ...draft.toJson()});
    return AccountTransferMutationResult.fromJson(data['account_transfer']);
  }

  Future<AccountTransferMutationResult> update({
    required String financialEventId,
    required int expectedVersionNumber,
    required AccountTransferDraft draft,
  }) async {
    final data = await _action({
      'action': 'update',
      'financial_event_id': financialEventId,
      'expected_version_number': expectedVersionNumber,
      ...draft.toJson(),
    });
    return AccountTransferMutationResult.fromJson(data['account_transfer']);
  }

  Future<AccountTransferMutationResult> submit(String id, int version) =>
      _transition('submit', id, version);
  Future<AccountTransferMutationResult> approve(String id, int version) =>
      _transition('approve', id, version);

  Future<AccountTransferMutationResult> reject(
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
    return AccountTransferMutationResult.fromJson(data['account_transfer']);
  }

  Future<AccountTransferMutationResult> _transition(
    String action,
    String id,
    int version,
  ) async {
    final data = await _action({
      'action': action,
      'financial_event_id': id,
      'expected_version_number': version,
    });
    return AccountTransferMutationResult.fromJson(data['account_transfer']);
  }

  Future<Map<String, dynamic>> _action(Map<String, dynamic> body) async {
    final response = invokeFunction != null
        ? await invokeFunction!('account-transfers', body)
        : await client.functions.invoke('account-transfers', body: body);
    final envelope = response is FunctionResponse ? response.data : response;
    if (envelope is! Map<String, dynamic>) {
      throw const AccountTransferFailure('Account transfer response failed.');
    }
    if (envelope['error'] != null) {
      throw AccountTransferFailure(envelope['error'].toString());
    }
    final data = envelope['data'];
    if (data is Map<String, dynamic>) return data;
    return envelope;
  }
}

class AccountTransferFailure implements Exception {
  const AccountTransferFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
