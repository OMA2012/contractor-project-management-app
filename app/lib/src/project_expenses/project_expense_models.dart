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
    this.projectNumber,
    this.projectName,
    this.clientNumber,
    this.clientName,
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
    projectNumber: json['project_number'] as String?,
    projectName: json['project_name'] as String?,
    clientNumber: json['client_number'] as String?,
    clientName: json['client_name'] as String?,
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
  final String? projectNumber;
  final String? projectName;
  final String? clientNumber;
  final String? clientName;
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
  String get projectDisplay =>
      _businessDisplay(projectNumber, projectName) ?? 'Project unavailable';
  String get clientDisplay =>
      _businessDisplay(clientNumber, clientName) ?? 'Client unavailable';
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
    this.clientId,
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
  final String? clientId;

  Map<String, dynamic> toJson() => {
    'project_id': projectId,
    if (clientId != null) 'client_id': clientId,
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

class ProjectExpenseLookups {
  const ProjectExpenseLookups({
    required this.expenseCategories,
    required this.projects,
  });

  final List<ExpenseCategoryOption> expenseCategories;
  final List<ProjectOption> projects;
}

class ExpenseCategoryOption {
  const ExpenseCategoryOption({
    required this.expenseCategoryId,
    required this.code,
    required this.name,
  });

  factory ExpenseCategoryOption.fromJson(Map<String, dynamic> json) =>
      ExpenseCategoryOption(
        expenseCategoryId: _string(json['expense_category_id']),
        code: _string(json['code']),
        name: _string(json['name']),
      );

  final String expenseCategoryId;
  final String code;
  final String name;
}

class ProjectOption {
  const ProjectOption({
    required this.projectId,
    required this.clientId,
    required this.projectNumber,
    required this.name,
  });

  factory ProjectOption.fromJson(Map<String, dynamic> json) => ProjectOption(
    projectId: _string(json['project_id']),
    clientId: _string(json['client_id']),
    projectNumber: _string(json['project_number']),
    name: _string(json['name']),
  );

  final String projectId;
  final String clientId;
  final String projectNumber;
  final String name;

  String get display => '$projectNumber - $name';
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

String? _businessDisplay(String? number, String? name) {
  final cleanNumber = number?.trim();
  final cleanName = name?.trim();
  if (cleanNumber == null || cleanNumber.isEmpty) return cleanName;
  if (cleanName == null || cleanName.isEmpty) return cleanNumber;
  return '$cleanNumber - $cleanName';
}
