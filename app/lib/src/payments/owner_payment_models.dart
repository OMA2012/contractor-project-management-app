class OwnerClientPayment {
  const OwnerClientPayment({
    required this.clientPaymentId,
    required this.financialEventId,
    required this.eventNumber,
    required this.projectId,
    required this.clientId,
    required this.amount,
    required this.currencyCode,
    required this.receivedDate,
    required this.eventStatus,
    required this.transactionStatus,
    required this.isClientSubmitted,
    required this.versionNumber,
    this.projectNumber,
    this.projectName,
    this.clientNumber,
    this.clientName,
    this.financialTransactionId,
    this.transactionNumber,
    this.receivedAccountId,
    this.paymentReference,
    this.payerName,
    this.submittedByClientUserId,
    this.notes,
    this.reportingCurrencyCode,
    this.submittedAt,
    this.approvedAt,
    this.rejectedAt,
    this.rejectionReason,
  });

  factory OwnerClientPayment.fromJson(Map<String, dynamic> json) =>
      OwnerClientPayment(
        clientPaymentId: _string(json['client_payment_id']),
        financialEventId: _string(json['financial_event_id']),
        eventNumber: _string(json['event_number']),
        financialTransactionId: _nullable(json['financial_transaction_id']),
        transactionNumber: _nullable(json['transaction_number']),
        projectId: _string(json['project_id']),
        clientId: _string(json['client_id']),
        projectNumber: _nullable(json['project_number']),
        projectName: _nullable(json['project_name']),
        clientNumber: _nullable(json['client_number']),
        clientName: _nullable(json['client_name']),
        amount: _string(json['amount']),
        currencyCode: _string(json['currency_code']),
        receivedAccountId: _nullable(json['received_account_id']),
        receivedDate: _string(json['received_date']),
        paymentReference: _nullable(json['payment_reference']),
        payerName: _nullable(json['payer_name']),
        isClientSubmitted: json['is_client_submitted'] as bool? ?? false,
        submittedByClientUserId: _nullable(json['submitted_by_client_user_id']),
        notes: _nullable(json['notes']),
        reportingCurrencyCode: _nullable(json['reporting_currency_code']),
        eventStatus: _string(json['event_status']),
        transactionStatus: _string(json['transaction_status']),
        submittedAt: _nullable(json['submitted_at']),
        approvedAt: _nullable(json['approved_at']),
        rejectedAt: _nullable(json['rejected_at']),
        rejectionReason: _nullable(json['rejection_reason']),
        versionNumber: json['version_number'] as int? ?? 1,
      );

  final String clientPaymentId;
  final String financialEventId;
  final String eventNumber;
  final String? financialTransactionId;
  final String? transactionNumber;
  final String projectId;
  final String clientId;
  final String? projectNumber;
  final String? projectName;
  final String? clientNumber;
  final String? clientName;
  final String amount;
  final String currencyCode;
  final String? receivedAccountId;
  final String receivedDate;
  final String? paymentReference;
  final String? payerName;
  final bool isClientSubmitted;
  final String? submittedByClientUserId;
  final String? notes;
  final String? reportingCurrencyCode;
  final String eventStatus;
  final String transactionStatus;
  final String? submittedAt;
  final String? approvedAt;
  final String? rejectedAt;
  final String? rejectionReason;
  final int versionNumber;

  bool get isDraft => eventStatus == 'DRAFT';
  bool get isSubmitted => eventStatus == 'SUBMITTED';
  bool get isPosted =>
      eventStatus == 'APPROVED' && transactionStatus == 'POSTED';
  bool get isRejected => eventStatus == 'REJECTED';
  String get moneyDisplay => '$currencyCode $amount';
  String get projectDisplay =>
      _businessDisplay(projectNumber, projectName) ?? 'Project unavailable';
  String get clientDisplay =>
      _businessDisplay(clientNumber, clientName) ?? 'Client unavailable';
  String get verificationLabel => isClientSubmitted && !isPosted
      ? 'Submitted for verification'
      : eventStatus;
}

class OwnerClientPaymentDraft {
  const OwnerClientPaymentDraft({
    required this.projectId,
    required this.amount,
    required this.currencyCode,
    required this.receivedDate,
    this.receivedAccountId,
    this.paymentReference,
    this.payerName,
    this.notes,
  });
  final String projectId;
  final String amount;
  final String currencyCode;
  final String receivedDate;
  final String? receivedAccountId;
  final String? paymentReference;
  final String? payerName;
  final String? notes;
  Map<String, dynamic> toJson() => {
    'project_id': projectId,
    'amount': amount,
    'currency_code': currencyCode,
    'received_date': receivedDate,
    'received_account_id': receivedAccountId,
    'payment_reference': paymentReference,
    'payer_name': payerName,
    'notes': notes,
  };
}

class OwnerPaymentRequest {
  const OwnerPaymentRequest({
    required this.paymentRequestId,
    required this.requestNumber,
    required this.projectId,
    required this.clientId,
    required this.requestedAmount,
    required this.currencyCode,
    required this.status,
    required this.effectiveStatus,
    required this.versionNumber,
    this.projectNumber,
    this.projectName,
    this.clientNumber,
    this.clientName,
    this.requestDate,
    this.dueDate,
    this.description,
    this.sentAt,
    this.viewedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.paidAmount,
    this.remainingAmount,
  });
  factory OwnerPaymentRequest.fromJson(Map<String, dynamic> json) =>
      OwnerPaymentRequest(
        paymentRequestId: _string(json['payment_request_id']),
        requestNumber: _string(json['request_number']),
        projectId: _string(json['project_id']),
        clientId: _string(json['client_id']),
        projectNumber: _nullable(json['project_number']),
        projectName: _nullable(json['project_name']),
        clientNumber: _nullable(json['client_number']),
        clientName: _nullable(json['client_name']),
        requestedAmount: _string(json['requested_amount']),
        currencyCode: _string(json['currency_code']),
        requestDate: _nullable(json['request_date']),
        dueDate: _nullable(json['due_date']),
        status: _string(json['status']),
        effectiveStatus: _string(json['effective_status']),
        description: _nullable(json['description']),
        sentAt: _nullable(json['sent_at']),
        viewedAt: _nullable(json['viewed_at']),
        cancelledAt: _nullable(json['cancelled_at']),
        cancellationReason: _nullable(json['cancellation_reason']),
        paidAmount: _nullable(json['paid_amount']),
        remainingAmount: _nullable(json['remaining_amount']),
        versionNumber: json['version_number'] as int? ?? 1,
      );
  final String paymentRequestId;
  final String requestNumber;
  final String projectId;
  final String clientId;
  final String? projectNumber;
  final String? projectName;
  final String? clientNumber;
  final String? clientName;
  final String requestedAmount;
  final String currencyCode;
  final String? requestDate;
  final String? dueDate;
  final String status;
  final String effectiveStatus;
  final String? description;
  final String? sentAt;
  final String? viewedAt;
  final String? cancelledAt;
  final String? cancellationReason;
  final String? paidAmount;
  final String? remainingAmount;
  final int versionNumber;
  bool get isDraft => status == 'DRAFT';
  bool get canSend => status == 'DRAFT';
  String get moneyDisplay => '$currencyCode $requestedAmount';
  String get projectDisplay =>
      _businessDisplay(projectNumber, projectName) ?? 'Project unavailable';
  String get clientDisplay =>
      _businessDisplay(clientNumber, clientName) ?? 'Client unavailable';
}

class OwnerPaymentProjectOption {
  const OwnerPaymentProjectOption({
    required this.projectId,
    required this.projectNumber,
    required this.name,
    this.clientNumber,
    this.clientName,
  });

  factory OwnerPaymentProjectOption.fromJson(Map<String, dynamic> json) =>
      OwnerPaymentProjectOption(
        projectId: _string(json['project_id'] ?? json['id']),
        projectNumber: _string(json['project_number']),
        name: _string(json['name'] ?? json['project_name']),
        clientNumber: _nullable(json['client_number']),
        clientName: _nullable(json['client_name']),
      );

  final String projectId;
  final String projectNumber;
  final String name;
  final String? clientNumber;
  final String? clientName;

  String get display {
    final project = _businessDisplay(projectNumber, name) ?? projectNumber;
    final client = _businessDisplay(clientNumber, clientName);
    return client == null ? project : '$project - $client';
  }
}

class OwnerPaymentRequestDraft {
  const OwnerPaymentRequestDraft({
    required this.projectId,
    required this.requestedAmount,
    required this.currencyCode,
    this.requestDate,
    this.dueDate,
    this.description,
  });
  final String projectId;
  final String requestedAmount;
  final String currencyCode;
  final String? requestDate;
  final String? dueDate;
  final String? description;
  Map<String, dynamic> toJson() => {
    'project_id': projectId,
    'requested_amount': requestedAmount,
    'currency_code': currencyCode,
    'request_date': requestDate,
    'due_date': dueDate,
    'description': description,
  };
}

class OwnerPaymentMutationResult {
  const OwnerPaymentMutationResult({
    this.financialEventId,
    this.paymentRequestId,
  });
  factory OwnerPaymentMutationResult.fromJson(Map<String, dynamic> json) =>
      OwnerPaymentMutationResult(
        financialEventId: _nullable(json['financial_event_id']),
        paymentRequestId: _nullable(json['payment_request_id']),
      );
  final String? financialEventId;
  final String? paymentRequestId;
}

String _string(Object? value) =>
    value is String ? value : value?.toString() ?? '';
String? _nullable(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}

String? _businessDisplay(String? number, String? name) {
  final cleanNumber = number?.trim();
  final cleanName = name?.trim();
  if (cleanNumber == null || cleanNumber.isEmpty) return cleanName;
  if (cleanName == null || cleanName.isEmpty) return cleanNumber;
  return '$cleanNumber - $cleanName';
}
