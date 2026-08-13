import 'package:supabase_flutter/supabase_flutter.dart';

import 'payment_models.dart';

typedef PaymentRpc =
    Future<dynamic> Function(
      String functionName, {
      Map<String, dynamic>? params,
    });

abstract class PaymentRepository {
  Future<ClientPaymentPage> listApprovedPayments({
    int limit = 50,
    int offset = 0,
  });
  Future<ClientApprovedPayment?> getApprovedPaymentDetail(
    String clientPaymentId,
  );
  Future<ClientPaymentSubmissionResult> submitPayment({
    required String projectId,
    required ExactMoney amount,
    required String currencyCode,
    required DateTime receivedDate,
    String? paymentReference,
    String? payerName,
  });
  Future<ClientPaymentRequestPage> listPaymentRequests({
    int limit = 50,
    int offset = 0,
  });
  Future<ClientPaymentRequest?> viewPaymentRequestDetail(
    String paymentRequestId,
  );
}

class SupabasePaymentRepository implements PaymentRepository {
  const SupabasePaymentRepository({this.supabaseClient, this.rpc});

  final SupabaseClient? supabaseClient;
  final PaymentRpc? rpc;

  SupabaseClient get client => supabaseClient ?? Supabase.instance.client;

  @override
  Future<ClientPaymentPage> listApprovedPayments({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _rpc('current_client_approved_payment_list', {
      'p_limit': limit,
      'p_offset': offset,
    });
    final rows = _rows(response);
    return ClientPaymentPage(
      rawCount: rows.length,
      payments: rows
          .map(ClientApprovedPayment.fromJson)
          .toList(growable: false),
    );
  }

  @override
  Future<ClientApprovedPayment?> getApprovedPaymentDetail(
    String clientPaymentId,
  ) async {
    final response = await _rpc('current_client_approved_payment_detail', {
      'p_client_payment_id': clientPaymentId,
    });
    final rows = _rows(response);
    if (rows.isEmpty) return null;
    return ClientApprovedPayment.fromJson(rows.single);
  }

  @override
  Future<ClientPaymentSubmissionResult> submitPayment({
    required String projectId,
    required ExactMoney amount,
    required String currencyCode,
    required DateTime receivedDate,
    String? paymentReference,
    String? payerName,
  }) async {
    final response = await _rpc('current_client_submit_payment', {
      'p_project_id': projectId,
      'p_amount': amount.text,
      'p_currency_code': currencyCode,
      'p_received_date': _dateParam(receivedDate),
      'p_payment_reference': _normalized(paymentReference),
      'p_payer_name': _normalized(payerName),
      'p_request_identifier': null,
      'p_correlation_identifier': null,
    });
    final rows = _rows(response);
    if (rows.isEmpty) throw const PaymentFailure('Payment submission failed.');
    return ClientPaymentSubmissionResult.fromJson(rows.single);
  }

  @override
  Future<ClientPaymentRequestPage> listPaymentRequests({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _rpc('current_client_payment_request_list', {
      'p_limit': limit,
      'p_offset': offset,
    });
    final rows = _rows(response);
    return ClientPaymentRequestPage(
      rawCount: rows.length,
      requests: rows.map(ClientPaymentRequest.fromJson).toList(growable: false),
    );
  }

  @override
  Future<ClientPaymentRequest?> viewPaymentRequestDetail(
    String paymentRequestId,
  ) async {
    final response = await _rpc('current_client_view_payment_request_detail', {
      'p_payment_request_id': paymentRequestId,
      'p_request_identifier': null,
      'p_correlation_identifier': null,
    });
    final rows = _rows(response);
    if (rows.isEmpty) return null;
    return ClientPaymentRequest.fromJson(rows.single);
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

String _dateParam(DateTime date) {
  final local = DateTime(date.year, date.month, date.day);
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String? _normalized(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
