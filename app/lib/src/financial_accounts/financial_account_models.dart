enum FinancialAccountType { cash, bank }

class FinancialAccount {
  const FinancialAccount({
    required this.id,
    required this.accountNumber,
    required this.name,
    required this.type,
    required this.currencyCode,
    required this.isActive,
    required this.versionNumber,
    this.bankName,
    this.maskedAccountIdentifier,
    this.notes,
    this.archivedAt,
    this.balance,
  });

  factory FinancialAccount.fromJson(Map<String, dynamic> json) {
    return FinancialAccount(
      id: _string(json['id'] ?? json['financial_account_id']),
      accountNumber: _string(json['account_number']),
      name: _string(json['name']),
      type: _type(json['account_type']),
      currencyCode: _string(json['currency_code']),
      bankName: json['bank_name'] as String?,
      maskedAccountIdentifier: json['masked_account_identifier'] as String?,
      notes: json['notes'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      archivedAt: json['archived_at'] as String?,
      versionNumber: json['version_number'] as int? ?? 1,
    );
  }

  final String id;
  final String accountNumber;
  final String name;
  final FinancialAccountType type;
  final String currencyCode;
  final String? bankName;
  final String? maskedAccountIdentifier;
  final bool isActive;
  final String? archivedAt;
  final int versionNumber;
  final String? notes;
  final ExactMoney? balance;

  bool get isArchived => archivedAt != null;
  bool get isBank => type == FinancialAccountType.bank;
  String get typeCode => isBank ? 'BANK' : 'CASH';

  FinancialAccount copyWith({ExactMoney? balance, int? versionNumber}) {
    return FinancialAccount(
      id: id,
      accountNumber: accountNumber,
      name: name,
      type: type,
      currencyCode: currencyCode,
      bankName: bankName,
      maskedAccountIdentifier: maskedAccountIdentifier,
      isActive: isActive,
      archivedAt: archivedAt,
      versionNumber: versionNumber ?? this.versionNumber,
      notes: notes,
      balance: balance ?? this.balance,
    );
  }
}

class ExactMoney {
  const ExactMoney({required this.currencyCode, required this.amount});

  factory ExactMoney.fromJson(Map<String, dynamic> json) => ExactMoney(
    currencyCode: _string(json['currency_code']),
    amount: _string(json['balance']),
  );

  final String currencyCode;
  final String amount;

  String get display => '$currencyCode $amount';
}

class FinancialAccountMutationResult {
  const FinancialAccountMutationResult({
    required this.financialAccountId,
    required this.versionNumber,
    this.accountNumber,
  });

  factory FinancialAccountMutationResult.fromJson(Map<String, dynamic> json) {
    return FinancialAccountMutationResult(
      financialAccountId: _string(json['financial_account_id']),
      accountNumber: json['account_number'] as String?,
      versionNumber: json['version_number'] as int? ?? 1,
    );
  }

  final String financialAccountId;
  final String? accountNumber;
  final int versionNumber;
}

class FinancialAccountDraft {
  const FinancialAccountDraft({
    required this.name,
    required this.type,
    required this.currencyCode,
    this.bankName,
    this.maskedAccountIdentifier,
    this.notes,
  });

  final String name;
  final FinancialAccountType type;
  final String currencyCode;
  final String? bankName;
  final String? maskedAccountIdentifier;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'name': name,
    'account_type': type == FinancialAccountType.bank ? 'BANK' : 'CASH',
    'currency_code': currencyCode,
    if (type == FinancialAccountType.bank) 'bank_name': bankName,
    if (type == FinancialAccountType.bank)
      'masked_account_identifier': maskedAccountIdentifier,
    'notes': notes,
  };
}

class FinancialAccountListState {
  const FinancialAccountListState({
    this.accounts = const [],
    this.cashTotals = const [],
    this.bankTotals = const [],
    this.isLoading = false,
    this.error,
  });

  const FinancialAccountListState.loading() : this(isLoading: true);
  const FinancialAccountListState.loaded({
    required List<FinancialAccount> accounts,
    required List<ExactMoney> cashTotals,
    required List<ExactMoney> bankTotals,
  }) : this(accounts: accounts, cashTotals: cashTotals, bankTotals: bankTotals);
  const FinancialAccountListState.failure(Object error) : this(error: error);

  final List<FinancialAccount> accounts;
  final List<ExactMoney> cashTotals;
  final List<ExactMoney> bankTotals;
  final bool isLoading;
  final Object? error;
}

class FinancialAccountDetailState {
  const FinancialAccountDetailState({
    this.account,
    this.isLoading = false,
    this.isMutating = false,
    this.error,
    this.mutationError,
  });

  const FinancialAccountDetailState.loading() : this(isLoading: true);
  const FinancialAccountDetailState.loaded(FinancialAccount account)
    : this(account: account);
  const FinancialAccountDetailState.failure(Object error) : this(error: error);

  final FinancialAccount? account;
  final bool isLoading;
  final bool isMutating;
  final Object? error;
  final Object? mutationError;

  FinancialAccountDetailState copyWith({
    FinancialAccount? account,
    bool? isMutating,
    Object? mutationError,
    bool clearMutationError = false,
  }) => FinancialAccountDetailState(
    account: account ?? this.account,
    isMutating: isMutating ?? this.isMutating,
    error: error,
    mutationError: clearMutationError
        ? null
        : mutationError ?? this.mutationError,
  );
}

FinancialAccountType _type(Object? value) {
  if (value == 'BANK') return FinancialAccountType.bank;
  return FinancialAccountType.cash;
}

String _string(Object? value) {
  if (value is String) return value;
  return value?.toString() ?? '';
}
