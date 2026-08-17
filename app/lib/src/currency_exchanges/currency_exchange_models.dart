class CurrencyExchange {
  const CurrencyExchange({
    required this.currencyExchangeId,
    required this.financialEventId,
    required this.eventNumber,
    required this.financialTransactionId,
    required this.transactionNumber,
    required this.sourceAccountId,
    required this.destinationAccountId,
    required this.sourceAmount,
    required this.sourceCurrencyCode,
    required this.destinationAmount,
    required this.destinationCurrencyCode,
    required this.feeAmount,
    required this.exchangeDate,
    required this.eventStatus,
    required this.transactionStatus,
    required this.versionNumber,
    this.projectId,
    this.clientId,
    this.exchangeRateId,
    this.rateBaseCurrencyCode,
    this.rateQuoteCurrencyCode,
    this.rateValue,
    this.rateSource,
    this.feeCurrencyCode,
    this.feeAccountId,
    this.roundingResult,
    this.reference,
    this.reportingCurrencyCode,
    this.submittedAt,
    this.approvedAt,
    this.rejectedAt,
    this.rejectionReason,
  });

  factory CurrencyExchange.fromJson(Map<String, dynamic> json) =>
      CurrencyExchange(
        currencyExchangeId: _string(json['currency_exchange_id']),
        financialEventId: _string(json['financial_event_id']),
        eventNumber: _string(json['event_number']),
        financialTransactionId: _string(json['financial_transaction_id']),
        transactionNumber: _string(json['transaction_number']),
        projectId: json['project_id'] as String?,
        clientId: json['client_id'] as String?,
        sourceAccountId: _string(json['source_account_id']),
        destinationAccountId: _string(json['destination_account_id']),
        sourceAmount: _string(json['source_amount']),
        sourceCurrencyCode: _string(json['source_currency_code']),
        destinationAmount: _string(json['destination_amount']),
        destinationCurrencyCode: _string(json['destination_currency_code']),
        exchangeRateId: json['exchange_rate_id'] as String?,
        rateBaseCurrencyCode: json['rate_base_currency_code'] as String?,
        rateQuoteCurrencyCode: json['rate_quote_currency_code'] as String?,
        rateValue: json['rate_value']?.toString(),
        rateSource: json['rate_source'] as String?,
        feeAmount: _string(json['fee_amount']),
        feeCurrencyCode: json['fee_currency_code'] as String?,
        feeAccountId: json['fee_account_id'] as String?,
        exchangeDate: _string(json['exchange_date']),
        roundingResult: json['rounding_result']?.toString(),
        reference: json['reference'] as String?,
        reportingCurrencyCode: json['reporting_currency_code'] as String?,
        eventStatus: _string(json['event_status']),
        transactionStatus: _string(json['transaction_status']),
        submittedAt: json['submitted_at'] as String?,
        approvedAt: json['approved_at'] as String?,
        rejectedAt: json['rejected_at'] as String?,
        rejectionReason: json['rejection_reason'] as String?,
        versionNumber: json['version_number'] as int? ?? 1,
      );

  final String currencyExchangeId;
  final String financialEventId;
  final String eventNumber;
  final String financialTransactionId;
  final String transactionNumber;
  final String? projectId;
  final String? clientId;
  final String sourceAccountId;
  final String destinationAccountId;
  final String sourceAmount;
  final String sourceCurrencyCode;
  final String destinationAmount;
  final String destinationCurrencyCode;
  final String? exchangeRateId;
  final String? rateBaseCurrencyCode;
  final String? rateQuoteCurrencyCode;
  final String? rateValue;
  final String? rateSource;
  final String feeAmount;
  final String? feeCurrencyCode;
  final String? feeAccountId;
  final String exchangeDate;
  final String? roundingResult;
  final String? reference;
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
      eventStatus == 'APPROVED' || transactionStatus == 'POSTED';
  bool get hasFee => feeCurrencyCode != null && feeAmount != '0';
  String get direction =>
      rateBaseCurrencyCode == null ||
          rateQuoteCurrencyCode == null ||
          rateValue == null
      ? '$sourceCurrencyCode to $destinationCurrencyCode'
      : '1 $rateBaseCurrencyCode = $rateValue $rateQuoteCurrencyCode';
}

class CurrencyExchangeDraft {
  const CurrencyExchangeDraft({
    required this.sourceAccountId,
    required this.destinationAccountId,
    required this.sourceAmount,
    required this.exchangeRateId,
    required this.exchangeDate,
    this.feeAmount,
    this.feeAccountId,
    this.projectId,
    this.reference,
  });

  final String sourceAccountId;
  final String destinationAccountId;
  final String sourceAmount;
  final String exchangeRateId;
  final String exchangeDate;
  final String? feeAmount;
  final String? feeAccountId;
  final String? projectId;
  final String? reference;

  Map<String, dynamic> toJson() => {
    'source_account_id': sourceAccountId,
    'destination_account_id': destinationAccountId,
    'source_amount': sourceAmount,
    'exchange_rate_id': exchangeRateId,
    'exchange_date': exchangeDate,
    'fee_amount': feeAmount,
    'fee_account_id': feeAccountId,
    'project_id': projectId,
    'reference': reference,
  };
}

class ExchangeRateOption {
  const ExchangeRateOption({
    required this.exchangeRateId,
    required this.rateDate,
    required this.baseCurrencyCode,
    required this.quoteCurrencyCode,
    required this.rateValue,
    required this.source,
  });

  factory ExchangeRateOption.fromJson(Map<String, dynamic> json) =>
      ExchangeRateOption(
        exchangeRateId: _string(json['exchange_rate_id']),
        rateDate: _string(json['rate_date']),
        baseCurrencyCode: _string(json['base_currency_code']),
        quoteCurrencyCode: _string(json['quote_currency_code']),
        rateValue: _string(json['rate_value']),
        source: _string(json['source']),
      );

  final String exchangeRateId;
  final String rateDate;
  final String baseCurrencyCode;
  final String quoteCurrencyCode;
  final String rateValue;
  final String source;

  String get display =>
      '$rateDate - 1 $baseCurrencyCode = $rateValue $quoteCurrencyCode';
}

class CurrencyExchangeMutationResult {
  const CurrencyExchangeMutationResult({
    required this.financialEventId,
    required this.versionNumber,
  });
  factory CurrencyExchangeMutationResult.fromJson(Map<String, dynamic> json) =>
      CurrencyExchangeMutationResult(
        financialEventId: _string(json['financial_event_id']),
        versionNumber: json['version_number'] as int? ?? 1,
      );
  final String financialEventId;
  final int versionNumber;
}

String _string(Object? value) =>
    value is String ? value : value?.toString() ?? '';
