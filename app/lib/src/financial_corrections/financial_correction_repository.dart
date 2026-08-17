import 'package:supabase_flutter/supabase_flutter.dart';

import 'financial_correction_models.dart';

typedef FinancialCorrectionInvoke =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);

class FinancialCorrectionFailure implements Exception {
  const FinancialCorrectionFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class FinancialCorrectionRepository {
  FinancialCorrectionRepository({this.invokeFunction});
  final FinancialCorrectionInvoke? invokeFunction;
  SupabaseClient get client => Supabase.instance.client;

  Future<List<CorrectionSource>> eligibleSources() async =>
      _list('eligible_sources', 'sources', CorrectionSource.fromJson);
  Future<List<FinancialReversal>> reversals() async =>
      _list('reversal_list', 'reversals', FinancialReversal.fromJson);
  Future<FinancialReversal> reversalDetail(String id) async =>
      FinancialReversal.fromJson(
        await _single('reversal_detail', 'reversal', id),
      );
  Future<CorrectionMutationResult> createReversal(ReversalDraft draft) async =>
      CorrectionMutationResult.fromJson(
        (await _action({
          'action': 'create_reversal',
          ...draft.toJson(),
        }))['reversal'],
      );
  Future<CorrectionMutationResult> submitReversal(String id, int version) =>
      _transition('submit_reversal', 'reversal', id, version);
  Future<CorrectionMutationResult> approveReversal(String id, int version) =>
      _transition('approve_reversal', 'reversal', id, version);
  Future<CorrectionMutationResult> rejectReversal(
    String id,
    int version,
    String reason,
  ) async => CorrectionMutationResult.fromJson(
    (await _action({
      'action': 'reject_reversal',
      'financial_event_id': id,
      'expected_version_number': version,
      'rejection_reason': reason,
    }))['reversal'],
  );

  Future<List<FinancialAdjustment>> adjustments() async =>
      _list('adjustment_list', 'adjustments', FinancialAdjustment.fromJson);
  Future<FinancialAdjustment> adjustmentDetail(String id) async =>
      FinancialAdjustment.fromJson(
        await _single('adjustment_detail', 'adjustment', id),
      );
  Future<CorrectionMutationResult> createAdjustment(
    AdjustmentDraft draft,
  ) async => CorrectionMutationResult.fromJson(
    (await _action({
      'action': 'create_adjustment',
      ...draft.toJson(),
    }))['adjustment'],
  );
  Future<CorrectionMutationResult> updateAdjustment(
    String id,
    int version,
    AdjustmentDraft draft,
  ) async => CorrectionMutationResult.fromJson(
    (await _action({
      'action': 'update_adjustment',
      'financial_event_id': id,
      'expected_version_number': version,
      ...draft.toJson()..remove('duplicate_fingerprint'),
    }))['adjustment'],
  );
  Future<CorrectionMutationResult> submitAdjustment(String id, int version) =>
      _transition('submit_adjustment', 'adjustment', id, version);
  Future<CorrectionMutationResult> approveAdjustment(String id, int version) =>
      _transition('approve_adjustment', 'adjustment', id, version);
  Future<CorrectionMutationResult> rejectAdjustment(
    String id,
    int version,
    String reason,
  ) async => CorrectionMutationResult.fromJson(
    (await _action({
      'action': 'reject_adjustment',
      'financial_event_id': id,
      'expected_version_number': version,
      'rejection_reason': reason,
    }))['adjustment'],
  );

  Future<CorrectionMutationResult> _transition(
    String action,
    String key,
    String id,
    int version,
  ) async => CorrectionMutationResult.fromJson(
    (await _action({
      'action': action,
      'financial_event_id': id,
      'expected_version_number': version,
    }))[key],
  );

  Future<Map<String, dynamic>> _single(
    String action,
    String key,
    String id,
  ) async => (await _action({'action': action, 'financial_event_id': id}))[key];

  Future<List<T>> _list<T>(
    String action,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final data = await _action({'action': action});
    return (data[key] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _action(Map<String, dynamic> body) async {
    final response = invokeFunction != null
        ? await invokeFunction!('financial-corrections', body)
        : await client.functions.invoke('financial-corrections', body: body);
    final envelope = response is FunctionResponse ? response.data : response;
    if (envelope is! Map<String, dynamic>) {
      throw const FinancialCorrectionFailure(
        'Financial correction response failed.',
      );
    }
    if (envelope['error'] != null) {
      throw FinancialCorrectionFailure(envelope['error'].toString());
    }
    final data = envelope['data'];
    return data is Map<String, dynamic> ? data : envelope;
  }
}
