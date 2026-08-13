class PaymentFailure implements Exception {
  const PaymentFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class PaymentParseFailure extends PaymentFailure {
  const PaymentParseFailure(super.message);
}

class ExactMoney {
  const ExactMoney._(this.text);

  factory ExactMoney.parsePositiveBackend(
    Object? value, {
    String field = 'amount',
  }) {
    return ExactMoney._parseBackendValue(value, field: field, allowZero: false);
  }

  factory ExactMoney.parseNonNegativeBackend(
    Object? value, {
    String field = 'amount',
  }) {
    return ExactMoney._parseBackendValue(value, field: field, allowZero: true);
  }

  factory ExactMoney.fromInput(String value) {
    return ExactMoney._fromDecimalText(value, allowZero: false);
  }

  factory ExactMoney._parseBackendValue(
    Object? value, {
    required String field,
    required bool allowZero,
  }) {
    if (value is String) {
      return ExactMoney._fromDecimalText(value, allowZero: allowZero);
    }
    throw PaymentParseFailure('Required payment field is missing: $field.');
  }

  factory ExactMoney._fromDecimalText(String value, {required bool allowZero}) {
    final normalized = value.trim();
    if (!_decimalPattern.hasMatch(normalized)) {
      throw const PaymentParseFailure('Amount is not valid.');
    }
    final parts = normalized.split('.');
    final whole = parts.first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final cents = parts.length == 2 ? '.${parts.last}' : '';
    final text = whole + cents;
    if (!allowZero && !_isPositive(text)) {
      throw const PaymentParseFailure('Amount must be greater than zero.');
    }
    return ExactMoney._(text);
  }

  static final _decimalPattern = RegExp(r'^(0|[1-9]\d*)(\.\d{1,6})?$');

  final String text;

  String display(String currencyCode) => '$text $currencyCode';

  @override
  String toString() => text;

  static bool _isPositive(String text) {
    final parts = text.split('.');
    if (int.parse(parts.first) > 0) {
      return true;
    }
    return parts.length == 2 && RegExp(r'[1-9]').hasMatch(parts.last);
  }
}

class ClientApprovedPayment {
  const ClientApprovedPayment({
    required this.clientPaymentId,
    required this.projectId,
    required this.projectNumber,
    required this.amount,
    required this.currencyCode,
    required this.receivedDate,
    required this.eventStatus,
    required this.transactionStatus,
    this.paymentReference,
    this.approvedAt,
  });

  factory ClientApprovedPayment.fromJson(Map<String, dynamic> json) {
    return ClientApprovedPayment(
      clientPaymentId: _requiredString(json, 'client_payment_id'),
      projectId: _requiredString(json, 'project_id'),
      projectNumber: _requiredString(json, 'project_number'),
      amount: ExactMoney.parsePositiveBackend(json['amount'], field: 'amount'),
      currencyCode: _requiredString(json, 'currency_code'),
      receivedDate: _requiredDate(json, 'received_date'),
      paymentReference: _string(json, 'payment_reference'),
      approvedAt: _date(json, 'approved_at'),
      eventStatus: _requiredString(json, 'event_status'),
      transactionStatus: _requiredString(json, 'transaction_status'),
    );
  }

  final String clientPaymentId;
  final String projectId;
  final String projectNumber;
  final ExactMoney amount;
  final String currencyCode;
  final DateTime receivedDate;
  final String? paymentReference;
  final DateTime? approvedAt;
  final String eventStatus;
  final String transactionStatus;

  bool get isReceived =>
      eventStatus == 'APPROVED' && transactionStatus == 'POSTED';
}

class ClientPaymentRequest {
  const ClientPaymentRequest({
    required this.paymentRequestId,
    required this.requestNumber,
    required this.projectId,
    required this.projectNumber,
    required this.requestedAmount,
    required this.currencyCode,
    required this.status,
    required this.effectiveStatus,
    required this.paidAmount,
    required this.remainingAmount,
    this.requestDate,
    this.dueDate,
    this.description,
    this.sentAt,
    this.viewedAt,
  });

  factory ClientPaymentRequest.fromJson(Map<String, dynamic> json) {
    final amountValue = json.containsKey('amount')
        ? json['amount']
        : json['requested_amount'];
    return ClientPaymentRequest(
      paymentRequestId: _requiredString(json, 'payment_request_id'),
      requestNumber: _requiredString(json, 'request_number'),
      projectId: _requiredString(json, 'project_id'),
      projectNumber: _requiredString(json, 'project_number'),
      requestedAmount: ExactMoney.parsePositiveBackend(
        amountValue,
        field: 'amount',
      ),
      currencyCode: _requiredString(json, 'currency_code'),
      requestDate: _date(json, 'request_date'),
      dueDate: _date(json, 'due_date'),
      description: _string(json, 'description'),
      sentAt: _date(json, 'sent_at'),
      viewedAt: _date(json, 'viewed_at'),
      status: _requiredRequestStatus(json, 'status'),
      effectiveStatus: _requiredRequestStatus(json, 'effective_status'),
      paidAmount: ExactMoney.parseNonNegativeBackend(
        json['paid_amount'] ?? '0',
        field: 'paid_amount',
      ),
      remainingAmount: ExactMoney.parseNonNegativeBackend(
        json['remaining_amount'] ?? '0',
        field: 'remaining_amount',
      ),
    );
  }

  final String paymentRequestId;
  final String requestNumber;
  final String projectId;
  final String projectNumber;
  final ExactMoney requestedAmount;
  final String currencyCode;
  final DateTime? requestDate;
  final DateTime? dueDate;
  final String? description;
  final DateTime? sentAt;
  final DateTime? viewedAt;
  final String status;
  final String effectiveStatus;
  final ExactMoney paidAmount;
  final ExactMoney remainingAmount;
}

class ClientPaymentSubmissionResult {
  const ClientPaymentSubmissionResult({required this.clientPaymentId});

  factory ClientPaymentSubmissionResult.fromJson(Map<String, dynamic> json) {
    return ClientPaymentSubmissionResult(
      clientPaymentId: _requiredString(json, 'client_payment_id'),
    );
  }

  final String clientPaymentId;
}

class ClientPaymentPage {
  const ClientPaymentPage({required this.rawCount, required this.payments});

  final int rawCount;
  final List<ClientApprovedPayment> payments;
}

class ClientPaymentRequestPage {
  const ClientPaymentRequestPage({
    required this.rawCount,
    required this.requests,
  });

  final int rawCount;
  final List<ClientPaymentRequest> requests;
}

class ClientPaymentListState {
  const ClientPaymentListState({
    this.payments = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<ClientApprovedPayment> payments;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  ClientPaymentListState copyWith({
    bool? isLoadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return ClientPaymentListState(
      payments: payments,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class ClientPaymentRequestListState {
  const ClientPaymentRequestListState({
    this.requests = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<ClientPaymentRequest> requests;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  ClientPaymentRequestListState copyWith({
    bool? isLoadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return ClientPaymentRequestListState(
      requests: requests,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class ClientPaymentDetailState {
  const ClientPaymentDetailState._({
    required this.isLoading,
    this.payment,
    this.error,
    this.unavailable = false,
  });
  const ClientPaymentDetailState.loading() : this._(isLoading: true);
  const ClientPaymentDetailState.loaded(ClientApprovedPayment payment)
    : this._(isLoading: false, payment: payment);
  const ClientPaymentDetailState.unavailable()
    : this._(isLoading: false, unavailable: true);
  const ClientPaymentDetailState.failure(Object error)
    : this._(isLoading: false, error: error);

  final bool isLoading;
  final ClientApprovedPayment? payment;
  final Object? error;
  final bool unavailable;
}

class ClientPaymentRequestDetailState {
  const ClientPaymentRequestDetailState._({
    required this.isLoading,
    this.request,
    this.error,
    this.unavailable = false,
  });
  const ClientPaymentRequestDetailState.loading() : this._(isLoading: true);
  const ClientPaymentRequestDetailState.loaded(ClientPaymentRequest request)
    : this._(isLoading: false, request: request);
  const ClientPaymentRequestDetailState.unavailable()
    : this._(isLoading: false, unavailable: true);
  const ClientPaymentRequestDetailState.failure(Object error)
    : this._(isLoading: false, error: error);

  final bool isLoading;
  final ClientPaymentRequest? request;
  final Object? error;
  final bool unavailable;
}

class ClientPaymentSubmitState {
  const ClientPaymentSubmitState({
    this.isSubmitting = false,
    this.result,
    this.error,
  });

  final bool isSubmitting;
  final ClientPaymentSubmissionResult? result;
  final Object? error;
}

String? _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  if (value == null) {
    throw PaymentParseFailure('Required payment field is missing: $key.');
  }
  return value;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _date(json, key);
  if (value == null) {
    throw PaymentParseFailure('Required payment date is missing: $key.');
  }
  return value;
}

DateTime? _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is DateTime) return value;
  return value is String ? DateTime.tryParse(value) : null;
}

String _requiredRequestStatus(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  if (!{
    'SENT',
    'VIEWED',
    'DRAFT',
    'OVERDUE',
    'CANCELLED',
    'PARTIALLY_PAID',
    'PAID',
  }.contains(value)) {
    throw const PaymentParseFailure(
      'Payment request status is not recognized.',
    );
  }
  return value;
}
