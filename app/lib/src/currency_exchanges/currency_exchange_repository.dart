import 'package:supabase_flutter/supabase_flutter.dart';

import 'currency_exchange_models.dart';

typedef CurrencyExchangeFunctionInvoke =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);

class CurrencyExchangeRepository {
  CurrencyExchangeRepository({this.invokeFunction});
  final CurrencyExchangeFunctionInvoke? invokeFunction;
  SupabaseClient get client => Supabase.instance.client;

  Future<List<CurrencyExchange>> list() async {
    final data = await _action({'action': 'list'});
    return (data['currency_exchanges'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(CurrencyExchange.fromJson)
        .toList(growable: false);
  }

  Future<CurrencyExchange> detail(String financialEventId) async {
    final data = await _action({
      'action': 'detail',
      'financial_event_id': financialEventId,
    });
    return CurrencyExchange.fromJson(data['currency_exchange']);
  }

  Future<CurrencyExchangeMutationResult> create(
    CurrencyExchangeDraft draft,
  ) async {
    final data = await _action({'action': 'create', ...draft.toJson()});
    return CurrencyExchangeMutationResult.fromJson(data['currency_exchange']);
  }

  Future<CurrencyExchangeMutationResult> update({
    required String financialEventId,
    required int expectedVersionNumber,
    required CurrencyExchangeDraft draft,
  }) async {
    final data = await _action({
      'action': 'update',
      'financial_event_id': financialEventId,
      'expected_version_number': expectedVersionNumber,
      ...draft.toJson(),
    });
    return CurrencyExchangeMutationResult.fromJson(data['currency_exchange']);
  }

  Future<CurrencyExchangeMutationResult> submit(String id, int version) =>
      _transition('submit', id, version);
  Future<CurrencyExchangeMutationResult> approve(String id, int version) =>
      _transition('approve', id, version);

  Future<CurrencyExchangeMutationResult> reject(
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
    return CurrencyExchangeMutationResult.fromJson(data['currency_exchange']);
  }

  Future<CurrencyExchangeMutationResult> _transition(
    String action,
    String id,
    int version,
  ) async {
    final data = await _action({
      'action': action,
      'financial_event_id': id,
      'expected_version_number': version,
    });
    return CurrencyExchangeMutationResult.fromJson(data['currency_exchange']);
  }

  Future<Map<String, dynamic>> _action(Map<String, dynamic> body) async {
    final response = invokeFunction != null
        ? await invokeFunction!('currency-exchanges', body)
        : await client.functions.invoke('currency-exchanges', body: body);
    final envelope = response is FunctionResponse ? response.data : response;
    if (envelope is! Map<String, dynamic>) {
      throw const CurrencyExchangeFailure('Currency exchange response failed.');
    }
    if (envelope['error'] != null) {
      throw CurrencyExchangeFailure(envelope['error'].toString());
    }
    final data = envelope['data'];
    if (data is Map<String, dynamic>) return data;
    return envelope;
  }
}

class CurrencyExchangeFailure implements Exception {
  const CurrencyExchangeFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
