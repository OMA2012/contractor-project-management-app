class CorrectionSource {
  const CorrectionSource({
    required this.financialEventId,
    required this.eventNumber,
    required this.eventType,
    required this.financialTransactionId,
    required this.transactionNumber,
    required this.amount,
    required this.currencyCode,
    required this.eventDate,
    required this.label,
    required this.canReverse,
    required this.canAdjust,
    required this.reversalRecorded,
    required this.adjustmentRecorded,
  });

  factory CorrectionSource.fromJson(Map<String, dynamic> json) =>
      CorrectionSource(
        financialEventId: _string(json['financial_event_id']),
        eventNumber: _string(json['event_number']),
        eventType: _string(json['event_type']),
        financialTransactionId: _string(json['financial_transaction_id']),
        transactionNumber: _string(json['transaction_number']),
        amount: _string(json['amount']),
        currencyCode: _string(json['currency_code']),
        eventDate: _string(json['event_date']),
        label: _string(json['label']),
        canReverse: json['can_reverse'] as bool? ?? false,
        canAdjust: json['can_adjust'] as bool? ?? false,
        reversalRecorded: json['reversal_recorded'] as bool? ?? false,
        adjustmentRecorded: json['adjustment_recorded'] as bool? ?? false,
      );

  final String financialEventId;
  final String eventNumber;
  final String eventType;
  final String financialTransactionId;
  final String transactionNumber;
  final String amount;
  final String currencyCode;
  final String eventDate;
  final String label;
  final bool canReverse;
  final bool canAdjust;
  final bool reversalRecorded;
  final bool adjustmentRecorded;
  String get moneyDisplay => '$currencyCode $amount';
}

class FinancialReversal {
  const FinancialReversal({
    required this.financialEventId,
    required this.eventNumber,
    required this.financialTransactionId,
    required this.transactionNumber,
    required this.originalTransactionId,
    required this.reversalDate,
    required this.eventStatus,
    required this.transactionStatus,
    required this.versionNumber,
    this.reason,
    this.description,
    this.submittedAt,
    this.approvedAt,
    this.rejectedAt,
    this.rejectionReason,
  });

  factory FinancialReversal.fromJson(Map<String, dynamic> json) =>
      FinancialReversal(
        financialEventId: _string(json['financial_event_id']),
        eventNumber: _string(json['event_number']),
        financialTransactionId: _string(json['financial_transaction_id']),
        transactionNumber: _string(json['transaction_number']),
        originalTransactionId: _string(json['original_transaction_id']),
        reversalDate: _string(json['reversal_date']),
        eventStatus: _string(json['event_status']),
        transactionStatus: _string(json['transaction_status']),
        versionNumber: json['version_number'] as int? ?? 1,
        reason: json['reason'] as String?,
        description: json['description'] as String?,
        submittedAt: json['submitted_at'] as String?,
        approvedAt: json['approved_at'] as String?,
        rejectedAt: json['rejected_at'] as String?,
        rejectionReason: json['rejection_reason'] as String?,
      );

  final String financialEventId;
  final String eventNumber;
  final String financialTransactionId;
  final String transactionNumber;
  final String originalTransactionId;
  final String reversalDate;
  final String eventStatus;
  final String transactionStatus;
  final int versionNumber;
  final String? reason;
  final String? description;
  final String? submittedAt;
  final String? approvedAt;
  final String? rejectedAt;
  final String? rejectionReason;
  bool get isDraft => eventStatus == 'DRAFT';
  bool get isSubmitted => eventStatus == 'SUBMITTED';
  bool get isPosted =>
      eventStatus == 'APPROVED' || transactionStatus == 'POSTED';
}

class FinancialAdjustment {
  const FinancialAdjustment({
    required this.financialEventId,
    required this.eventNumber,
    required this.financialTransactionId,
    required this.transactionNumber,
    required this.financialAccountId,
    required this.direction,
    required this.amount,
    required this.currencyCode,
    required this.adjustmentDate,
    required this.eventStatus,
    required this.transactionStatus,
    required this.versionNumber,
    this.adjustedTransactionId,
    this.reason,
    this.reportingCurrencyCode,
    this.description,
    this.submittedAt,
    this.approvedAt,
    this.rejectedAt,
    this.rejectionReason,
  });

  factory FinancialAdjustment.fromJson(Map<String, dynamic> json) =>
      FinancialAdjustment(
        financialEventId: _string(json['financial_event_id']),
        eventNumber: _string(json['event_number']),
        financialTransactionId: _string(json['financial_transaction_id']),
        transactionNumber: _string(json['transaction_number']),
        financialAccountId: _string(json['financial_account_id']),
        direction: _string(json['direction']),
        amount: _string(json['amount']),
        currencyCode: _string(json['currency_code']),
        adjustmentDate: _string(json['adjustment_date']),
        eventStatus: _string(json['event_status']),
        transactionStatus: _string(json['transaction_status']),
        versionNumber: json['version_number'] as int? ?? 1,
        adjustedTransactionId: json['adjusted_transaction_id'] as String?,
        reason: json['reason'] as String?,
        reportingCurrencyCode: json['reporting_currency_code'] as String?,
        description: json['description'] as String?,
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
  final String direction;
  final String amount;
  final String currencyCode;
  final String adjustmentDate;
  final String eventStatus;
  final String transactionStatus;
  final int versionNumber;
  final String? adjustedTransactionId;
  final String? reason;
  final String? reportingCurrencyCode;
  final String? description;
  final String? submittedAt;
  final String? approvedAt;
  final String? rejectedAt;
  final String? rejectionReason;
  bool get isDraft => eventStatus == 'DRAFT';
  bool get isSubmitted => eventStatus == 'SUBMITTED';
  bool get isPosted =>
      eventStatus == 'APPROVED' || transactionStatus == 'POSTED';
  String get moneyDisplay => '$currencyCode $amount';
}

class ReversalDraft {
  const ReversalDraft({
    required this.originalTransactionId,
    required this.reversalDate,
    required this.reason,
    this.description,
  });
  final String originalTransactionId;
  final String reversalDate;
  final String reason;
  final String? description;
  Map<String, dynamic> toJson() => {
    'original_transaction_id': originalTransactionId,
    'reversal_date': reversalDate,
    'reason': reason,
    'description': description,
    'duplicate_fingerprint': '$originalTransactionId|$reversalDate|$reason',
  };
}

class AdjustmentDraft {
  const AdjustmentDraft({
    required this.financialAccountId,
    required this.direction,
    required this.amount,
    required this.adjustmentDate,
    required this.reportingCurrencyCode,
    required this.reason,
    this.adjustedTransactionId,
    this.description,
  });
  final String financialAccountId;
  final String direction;
  final String amount;
  final String adjustmentDate;
  final String reportingCurrencyCode;
  final String reason;
  final String? adjustedTransactionId;
  final String? description;
  Map<String, dynamic> toJson() => {
    'financial_account_id': financialAccountId,
    'direction': direction,
    'amount': amount,
    'adjustment_date': adjustmentDate,
    'reporting_currency_code': reportingCurrencyCode,
    'reason': reason,
    'adjusted_transaction_id': adjustedTransactionId,
    'description': description,
    'duplicate_fingerprint':
        '$financialAccountId|$direction|$amount|$adjustmentDate|${adjustedTransactionId ?? ''}',
  };
}

class CorrectionMutationResult {
  const CorrectionMutationResult({
    required this.financialEventId,
    required this.versionNumber,
  });
  factory CorrectionMutationResult.fromJson(Map<String, dynamic> json) =>
      CorrectionMutationResult(
        financialEventId: _string(json['financial_event_id']),
        versionNumber: json['version_number'] as int? ?? 1,
      );
  final String financialEventId;
  final int versionNumber;
}

String _string(Object? value) =>
    value is String ? value : value?.toString() ?? '';
