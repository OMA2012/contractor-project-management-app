class AccountTransfer {
  const AccountTransfer({
    required this.accountTransferId,
    required this.financialEventId,
    required this.eventNumber,
    required this.financialTransactionId,
    required this.transactionNumber,
    required this.sourceAccountId,
    required this.destinationAccountId,
    required this.amount,
    required this.currencyCode,
    required this.transferDate,
    required this.eventStatus,
    required this.transactionStatus,
    required this.versionNumber,
    this.reference,
    this.notes,
    this.reportingCurrencyCode,
    this.submittedAt,
    this.approvedAt,
    this.rejectedAt,
    this.rejectionReason,
  });

  factory AccountTransfer.fromJson(Map<String, dynamic> json) =>
      AccountTransfer(
        accountTransferId: _string(json['account_transfer_id']),
        financialEventId: _string(json['financial_event_id']),
        eventNumber: _string(json['event_number']),
        financialTransactionId: _string(json['financial_transaction_id']),
        transactionNumber: _string(json['transaction_number']),
        sourceAccountId: _string(json['source_account_id']),
        destinationAccountId: _string(json['destination_account_id']),
        amount: _string(json['amount']),
        currencyCode: _string(json['currency_code']),
        transferDate: _string(json['transfer_date']),
        eventStatus: _string(json['event_status']),
        transactionStatus: _string(json['transaction_status']),
        versionNumber: json['version_number'] as int? ?? 1,
        reference: json['reference'] as String?,
        notes: json['notes'] as String?,
        reportingCurrencyCode: json['reporting_currency_code'] as String?,
        submittedAt: json['submitted_at'] as String?,
        approvedAt: json['approved_at'] as String?,
        rejectedAt: json['rejected_at'] as String?,
        rejectionReason: json['rejection_reason'] as String?,
      );

  final String accountTransferId;
  final String financialEventId;
  final String eventNumber;
  final String financialTransactionId;
  final String transactionNumber;
  final String sourceAccountId;
  final String destinationAccountId;
  final String amount;
  final String currencyCode;
  final String transferDate;
  final String eventStatus;
  final String transactionStatus;
  final int versionNumber;
  final String? reference;
  final String? notes;
  final String? reportingCurrencyCode;
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

class AccountTransferDraft {
  const AccountTransferDraft({
    required this.sourceAccountId,
    required this.destinationAccountId,
    required this.amount,
    required this.currencyCode,
    required this.transferDate,
    this.reference,
    this.notes,
  });

  final String sourceAccountId;
  final String destinationAccountId;
  final String amount;
  final String currencyCode;
  final String transferDate;
  final String? reference;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'source_account_id': sourceAccountId,
    'destination_account_id': destinationAccountId,
    'amount': amount,
    'currency_code': currencyCode,
    'transfer_date': transferDate,
    'reference': reference,
    'notes': notes,
  };
}

class AccountTransferMutationResult {
  const AccountTransferMutationResult({
    required this.financialEventId,
    required this.versionNumber,
  });
  factory AccountTransferMutationResult.fromJson(Map<String, dynamic> json) =>
      AccountTransferMutationResult(
        financialEventId: _string(json['financial_event_id']),
        versionNumber: json['version_number'] as int? ?? 1,
      );
  final String financialEventId;
  final int versionNumber;
}

String _string(Object? value) =>
    value is String ? value : value?.toString() ?? '';
