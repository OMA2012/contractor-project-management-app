class OpeningBalance {
  const OpeningBalance({
    required this.financialEventId,
    required this.eventNumber,
    required this.financialTransactionId,
    required this.transactionNumber,
    required this.financialAccountId,
    required this.amount,
    required this.currencyCode,
    required this.openingDate,
    required this.eventStatus,
    required this.transactionStatus,
    required this.versionNumber,
    this.reportingCurrencyCode,
    this.description,
    this.notes,
    this.submittedAt,
    this.approvedAt,
    this.rejectedAt,
    this.rejectionReason,
  });

  factory OpeningBalance.fromJson(Map<String, dynamic> json) => OpeningBalance(
    financialEventId: _string(json['financial_event_id']),
    eventNumber: _string(json['event_number']),
    financialTransactionId: _string(json['financial_transaction_id']),
    transactionNumber: _string(json['transaction_number']),
    financialAccountId: _string(json['financial_account_id']),
    amount: _string(json['amount']),
    currencyCode: _string(json['currency_code']),
    openingDate: _string(json['opening_date'] ?? json['event_date']),
    eventStatus: _string(json['event_status']),
    transactionStatus: _string(json['transaction_status']),
    versionNumber: json['version_number'] as int? ?? 1,
    reportingCurrencyCode: json['reporting_currency_code'] as String?,
    description: json['description'] as String?,
    notes: json['notes'] as String?,
    submittedAt: json['submitted_at'] as String?,
    approvedAt: json['approved_at'] as String?,
    rejectedAt: json['rejected_at'] as String?,
    rejectionReason: json['rejection_reason'] as String?,
  );

  final String financialEventId;
  final String eventNumber;
  final String financialTransactionId;
  final String transactionNumber;
  final String financialAccountId;
  final String amount;
  final String currencyCode;
  final String openingDate;
  final String eventStatus;
  final String transactionStatus;
  final int versionNumber;
  final String? reportingCurrencyCode;
  final String? description;
  final String? notes;
  final String? submittedAt;
  final String? approvedAt;
  final String? rejectedAt;
  final String? rejectionReason;

  bool get isDraft => eventStatus == 'DRAFT';
  bool get isSubmitted => eventStatus == 'SUBMITTED';
  bool get isPosted =>
      eventStatus == 'APPROVED' || transactionStatus == 'POSTED';
  bool get isRejected => eventStatus == 'REJECTED';
  String get moneyDisplay => '$currencyCode $amount';
}

class OpeningBalanceDraft {
  const OpeningBalanceDraft({
    required this.financialAccountId,
    required this.amount,
    required this.openingDate,
    required this.reportingCurrencyCode,
    this.description,
    this.notes,
  });

  final String financialAccountId;
  final String amount;
  final String openingDate;
  final String reportingCurrencyCode;
  final String? description;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'financial_account_id': financialAccountId,
    'amount': amount,
    'opening_date': openingDate,
    'reporting_currency_code': reportingCurrencyCode,
    'description': description,
    'notes': notes,
    'duplicate_fingerprint':
        '$financialAccountId|$amount|$openingDate|$reportingCurrencyCode',
  };
}

class OpeningBalanceMutationResult {
  const OpeningBalanceMutationResult({
    required this.financialEventId,
    required this.versionNumber,
  });
  factory OpeningBalanceMutationResult.fromJson(Map<String, dynamic> json) =>
      OpeningBalanceMutationResult(
        financialEventId: _string(json['financial_event_id']),
        versionNumber: json['version_number'] as int? ?? 1,
      );
  final String financialEventId;
  final int versionNumber;
}

class FinancialApprovalQueueItem {
  const FinancialApprovalQueueItem({
    required this.financialEventId,
    required this.eventNumber,
    required this.eventType,
    required this.relatedLabel,
    required this.amount,
    required this.currencyCode,
    required this.eventDate,
    required this.eventStatus,
    required this.transactionStatus,
    required this.createdByMe,
    required this.eligibleForMyApproval,
    required this.versionNumber,
    this.submittedAt,
    this.approvedAt,
    this.rejectedAt,
    this.rejectionReason,
  });

  factory FinancialApprovalQueueItem.fromJson(Map<String, dynamic> json) =>
      FinancialApprovalQueueItem(
        financialEventId: _string(json['financial_event_id']),
        eventNumber: _string(json['event_number']),
        eventType: _string(json['event_type']),
        relatedLabel: _string(json['related_label']),
        amount: _string(json['amount']),
        currencyCode: _string(json['currency_code']),
        eventDate: _string(json['event_date']),
        eventStatus: _string(json['event_status']),
        transactionStatus: _string(json['transaction_status']),
        createdByMe: json['created_by_me'] as bool? ?? false,
        eligibleForMyApproval:
            json['eligible_for_my_approval'] as bool? ?? false,
        versionNumber: json['version_number'] as int? ?? 1,
        submittedAt: json['submitted_at'] as String?,
        approvedAt: json['approved_at'] as String?,
        rejectedAt: json['rejected_at'] as String?,
        rejectionReason: json['rejection_reason'] as String?,
      );

  final String financialEventId;
  final String eventNumber;
  final String eventType;
  final String relatedLabel;
  final String amount;
  final String currencyCode;
  final String eventDate;
  final String eventStatus;
  final String transactionStatus;
  final bool createdByMe;
  final bool eligibleForMyApproval;
  final int versionNumber;
  final String? submittedAt;
  final String? approvedAt;
  final String? rejectedAt;
  final String? rejectionReason;
  String get moneyDisplay => '$currencyCode $amount';
}

String _string(Object? value) =>
    value is String ? value : value?.toString() ?? '';
