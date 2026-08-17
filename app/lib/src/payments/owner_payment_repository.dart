import 'package:supabase_flutter/supabase_flutter.dart';

import 'owner_payment_models.dart';

typedef OwnerPaymentFunctionInvoke =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);

abstract class OwnerPaymentRepository {
  Future<List<OwnerClientPayment>> listPayments();
  Future<OwnerClientPayment> paymentDetail(String financialEventId);
  Future<List<OwnerPaymentProjectOption>> projectLookups();
  Future<OwnerPaymentMutationResult> createPayment(
    OwnerClientPaymentDraft draft,
  );
  Future<OwnerPaymentMutationResult> updatePayment({
    required String financialEventId,
    required int expectedVersionNumber,
    required OwnerClientPaymentDraft draft,
  });
  Future<OwnerPaymentMutationResult> verifyClientSubmitted({
    required String financialEventId,
    required int expectedVersionNumber,
    required String receivedAccountId,
    String? notes,
  });
  Future<OwnerPaymentMutationResult> submitPayment(String id, int version);
  Future<OwnerPaymentMutationResult> approvePayment(String id, int version);
  Future<OwnerPaymentMutationResult> rejectPayment(
    String id,
    int version,
    String reason,
  );
  Future<List<OwnerPaymentRequest>> listRequests();
  Future<OwnerPaymentRequest> requestDetail(String paymentRequestId);
  Future<OwnerPaymentMutationResult> createRequest(
    OwnerPaymentRequestDraft draft,
  );
  Future<OwnerPaymentMutationResult> updateRequest({
    required String paymentRequestId,
    required int expectedVersionNumber,
    required OwnerPaymentRequestDraft draft,
  });
  Future<OwnerPaymentMutationResult> sendRequest(String id, int version);
  Future<OwnerPaymentMutationResult> cancelRequest(
    String id,
    int version,
    String reason,
  );
}

class SupabaseOwnerPaymentRepository implements OwnerPaymentRepository {
  SupabaseOwnerPaymentRepository({this.invokeFunction});
  final OwnerPaymentFunctionInvoke? invokeFunction;
  SupabaseClient get client => Supabase.instance.client;

  @override
  Future<List<OwnerClientPayment>> listPayments() async =>
      ((await _action({'action': 'list'}))['payments'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(OwnerClientPayment.fromJson)
          .toList(growable: false);

  @override
  Future<OwnerClientPayment> paymentDetail(String financialEventId) async =>
      OwnerClientPayment.fromJson(
        (await _action({
          'action': 'detail',
          'financial_event_id': financialEventId,
        }))['payment'],
      );

  @override
  Future<List<OwnerPaymentProjectOption>> projectLookups() async =>
      ((await _action({'action': 'lookup'}))['projects'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(OwnerPaymentProjectOption.fromJson)
          .toList(growable: false);

  @override
  Future<OwnerPaymentMutationResult> createPayment(
    OwnerClientPaymentDraft draft,
  ) async => _mutation({'action': 'create', ...draft.toJson()}, 'payment');

  @override
  Future<OwnerPaymentMutationResult> updatePayment({
    required String financialEventId,
    required int expectedVersionNumber,
    required OwnerClientPaymentDraft draft,
  }) async => _mutation({
    'action': 'update',
    'financial_event_id': financialEventId,
    'expected_version_number': expectedVersionNumber,
    ...draft.toJson(),
  }, 'payment');

  @override
  Future<OwnerPaymentMutationResult> verifyClientSubmitted({
    required String financialEventId,
    required int expectedVersionNumber,
    required String receivedAccountId,
    String? notes,
  }) async => _mutation({
    'action': 'verify_client_submitted',
    'financial_event_id': financialEventId,
    'expected_version_number': expectedVersionNumber,
    'received_account_id': receivedAccountId,
    'notes': notes,
  }, 'payment');

  @override
  Future<OwnerPaymentMutationResult> submitPayment(String id, int version) =>
      _paymentTransition('submit', id, version);
  @override
  Future<OwnerPaymentMutationResult> approvePayment(String id, int version) =>
      _paymentTransition('approve', id, version);
  @override
  Future<OwnerPaymentMutationResult> rejectPayment(
    String id,
    int version,
    String reason,
  ) => _mutation({
    'action': 'reject',
    'financial_event_id': id,
    'expected_version_number': version,
    'rejection_reason': reason,
  }, 'payment');

  @override
  Future<List<OwnerPaymentRequest>> listRequests() async =>
      ((await _action({'action': 'request_list'}))['requests'] as List? ??
              const [])
          .cast<Map<String, dynamic>>()
          .map(OwnerPaymentRequest.fromJson)
          .toList(growable: false);

  @override
  Future<OwnerPaymentRequest> requestDetail(String paymentRequestId) async =>
      OwnerPaymentRequest.fromJson(
        (await _action({
          'action': 'request_detail',
          'payment_request_id': paymentRequestId,
        }))['request'],
      );

  @override
  Future<OwnerPaymentMutationResult> createRequest(
    OwnerPaymentRequestDraft draft,
  ) => _mutation({'action': 'request_create', ...draft.toJson()}, 'request');

  @override
  Future<OwnerPaymentMutationResult> updateRequest({
    required String paymentRequestId,
    required int expectedVersionNumber,
    required OwnerPaymentRequestDraft draft,
  }) => _mutation({
    'action': 'request_update',
    'payment_request_id': paymentRequestId,
    'expected_version_number': expectedVersionNumber,
    ...draft.toJson(),
  }, 'request');

  @override
  Future<OwnerPaymentMutationResult> sendRequest(String id, int version) =>
      _requestTransition('request_send', id, version);
  @override
  Future<OwnerPaymentMutationResult> cancelRequest(
    String id,
    int version,
    String reason,
  ) => _mutation({
    'action': 'request_cancel',
    'payment_request_id': id,
    'expected_version_number': version,
    'cancellation_reason': reason,
  }, 'request');

  Future<OwnerPaymentMutationResult> _paymentTransition(
    String action,
    String id,
    int version,
  ) => _mutation({
    'action': action,
    'financial_event_id': id,
    'expected_version_number': version,
  }, 'payment');
  Future<OwnerPaymentMutationResult> _requestTransition(
    String action,
    String id,
    int version,
  ) => _mutation({
    'action': action,
    'payment_request_id': id,
    'expected_version_number': version,
  }, 'request');
  Future<OwnerPaymentMutationResult> _mutation(
    Map<String, dynamic> body,
    String key,
  ) async => OwnerPaymentMutationResult.fromJson((await _action(body))[key]);

  Future<Map<String, dynamic>> _action(Map<String, dynamic> body) async {
    final response = invokeFunction != null
        ? await invokeFunction!('client-payments', body)
        : await client.functions.invoke('client-payments', body: body);
    final envelope = response is FunctionResponse ? response.data : response;
    if (envelope is! Map<String, dynamic>) {
      throw const OwnerPaymentFailure('Payment response failed.');
    }
    if (envelope['error'] != null) {
      throw OwnerPaymentFailure(envelope['error'].toString());
    }
    final data = envelope['data'];
    return data is Map<String, dynamic> ? data : envelope;
  }
}

class OwnerPaymentFailure implements Exception {
  const OwnerPaymentFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
