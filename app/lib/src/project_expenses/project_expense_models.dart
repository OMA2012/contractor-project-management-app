class ProjectExpense {
  const ProjectExpense({
    required this.projectExpenseId,
    required this.financialEventId,
    required this.eventNumber,
    required this.expenseNumber,
    required this.projectId,
    required this.expenseCategoryId,
    required this.amount,
    required this.currencyCode,
    required this.paidFromAccountId,
    required this.expenseDate,
    required this.eventStatus,
    required this.transactionStatus,
    required this.versionNumber,
    this.vendorName,
    this.vendorReference,
    this.description,
    this.privateNotes,
    this.reportingCurrencyCode,
    this.submittedAt,
    this.approvedAt,
    this.rejectedAt,
    this.rejectionReason,
  });

  factory ProjectExpense.fromJson(Map<String, dynamic> json) => ProjectExpense(
    projectExpenseId: _string(json['project_expense_id']),
    financialEventId: _string(json['financial_event_id']),
    eventNumber: _string(json['event_number']),
    expenseNumber: _string(json['expense_number']),
    projectId: _string(json['project_id']),
    expenseCategoryId: _string(json['expense_category_id']),
    amount: _string(json['amount']),
    currencyCode: _string(json['currency_code']),
    paidFromAccountId: _string(json['paid_from_account_id']),
    expenseDate: _string(json['expense_date']),
    eventStatus: _string(json['event_status']),
    transactionStatus: _string(json['transaction_status']),
    versionNumber: json['version_number'] as int? ?? 1,
    vendorName: json['vendor_name'] as String?,
    vendorReference: json['vendor_reference'] as String?,
    description: json['description'] as String?,
    privateNotes: json['private_notes'] as String?,
    reportingCurrencyCode: json['reporting_currency_code'] as String?,
    submittedAt: json['submitted_at'] as String?,
    approvedAt: json['approved_at'] as String?,
    rejectedAt: json['rejected_at'] as String?,
    rejectionReason: json['rejection_reason'] as String?,
  );

  final String projectExpenseId;
  final String financialEventId;
  final String eventNumber;
  final String expenseNumber;
  final String projectId;
  final String expenseCategoryId;
  final String amount;
  final String currencyCode;
  final String paidFromAccountId;
  final String expenseDate;
  final String eventStatus;
  final String transactionStatus;
  final int versionNumber;
  final String? vendorName;
  final String? vendorReference;
  final String? description;
  final String? privateNotes;
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

class ProjectExpenseDraft {
  const ProjectExpenseDraft({
    required this.projectId,
    required this.expenseCategoryId,
    required this.amount,
    required this.currencyCode,
    required this.paidFromAccountId,
    required this.expenseDate,
    required this.description,
    this.vendorName,
    this.vendorReference,
    this.privateNotes,
  });

  final String projectId;
  final String expenseCategoryId;
  final String amount;
  final String currencyCode;
  final String paidFromAccountId;
  final String expenseDate;
  final String description;
  final String? vendorName;
  final String? vendorReference;
  final String? privateNotes;

  Map<String, dynamic> toJson() => {
    'project_id': projectId,
    'expense_category_id': expenseCategoryId,
    'amount': amount,
    'currency_code': currencyCode,
    'paid_from_account_id': paidFromAccountId,
    'expense_date': expenseDate,
    'description': description,
    'vendor_name': vendorName,
    'vendor_reference': vendorReference,
    'private_notes': privateNotes,
  };
}

class ProjectExpenseMutationResult {
  const ProjectExpenseMutationResult({
    required this.financialEventId,
    required this.versionNumber,
  });
  factory ProjectExpenseMutationResult.fromJson(Map<String, dynamic> json) =>
      ProjectExpenseMutationResult(
        financialEventId: _string(json['financial_event_id']),
        versionNumber: json['version_number'] as int? ?? 1,
      );
  final String financialEventId;
  final int versionNumber;
}

String _string(Object? value) =>
    value is String ? value : value?.toString() ?? '';
