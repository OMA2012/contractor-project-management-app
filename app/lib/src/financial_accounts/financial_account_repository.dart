import 'package:supabase_flutter/supabase_flutter.dart';

import 'financial_account_models.dart';

typedef FinancialAccountFunctionInvoke =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);

abstract class FinancialAccountRepository {
  Future<List<FinancialAccount>> listAccounts();
  Future<FinancialAccount> detail(String accountId);
  Future<ExactMoney> balance(String accountId);
  Future<List<ExactMoney>> cashTotalsByCurrency();
  Future<List<ExactMoney>> bankTotalsByCurrency();
  Future<FinancialAccountMutationResult> create(FinancialAccountDraft draft);
  Future<FinancialAccountMutationResult> update({
    required String accountId,
    required int expectedVersionNumber,
    required FinancialAccountDraft draft,
  });
  Future<FinancialAccountMutationResult> activate(
    String accountId,
    int expectedVersionNumber,
  );
  Future<FinancialAccountMutationResult> deactivate(
    String accountId,
    int expectedVersionNumber,
  );
  Future<FinancialAccountMutationResult> archive(
    String accountId,
    int expectedVersionNumber,
  );
}

class SupabaseFinancialAccountRepository implements FinancialAccountRepository {
  SupabaseFinancialAccountRepository({this.invokeFunction});

  final FinancialAccountFunctionInvoke? invokeFunction;

  SupabaseClient get client => Supabase.instance.client;

  @override
  Future<List<FinancialAccount>> listAccounts() async {
    final data = await _action({'action': 'list', 'include_archived': true});
    final accounts = (data['accounts'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(FinancialAccount.fromJson)
        .toList(growable: false);
    final balances = await Future.wait(accounts.map((a) => balance(a.id)));
    return [
      for (var i = 0; i < accounts.length; i++)
        accounts[i].copyWith(balance: balances[i]),
    ];
  }

  @override
  Future<FinancialAccount> detail(String accountId) async {
    final data = await _action({
      'action': 'detail',
      'financial_account_id': accountId,
    });
    final account = FinancialAccount.fromJson(data['account']);
    return account.copyWith(balance: await balance(accountId));
  }

  @override
  Future<ExactMoney> balance(String accountId) async {
    final data = await _action({
      'action': 'balance',
      'financial_account_id': accountId,
    });
    return ExactMoney.fromJson(data['balance']);
  }

  @override
  Future<List<ExactMoney>> cashTotalsByCurrency() async {
    final data = await _action({'action': 'cash_totals_by_currency'});
    return _moneyRows(data['totals']);
  }

  @override
  Future<List<ExactMoney>> bankTotalsByCurrency() async {
    final data = await _action({'action': 'bank_totals_by_currency'});
    return _moneyRows(data['totals']);
  }

  @override
  Future<FinancialAccountMutationResult> create(
    FinancialAccountDraft draft,
  ) async {
    final data = await _action({'action': 'create', ...draft.toJson()});
    return FinancialAccountMutationResult.fromJson(data['account']);
  }

  @override
  Future<FinancialAccountMutationResult> update({
    required String accountId,
    required int expectedVersionNumber,
    required FinancialAccountDraft draft,
  }) async {
    final data = await _action({
      'action': 'update',
      'financial_account_id': accountId,
      'expected_version_number': expectedVersionNumber,
      ...draft.toJson(),
    });
    return FinancialAccountMutationResult.fromJson(data['account']);
  }

  @override
  Future<FinancialAccountMutationResult> activate(
    String accountId,
    int expectedVersionNumber,
  ) => _lifecycle('activate', accountId, expectedVersionNumber);

  @override
  Future<FinancialAccountMutationResult> deactivate(
    String accountId,
    int expectedVersionNumber,
  ) => _lifecycle('deactivate', accountId, expectedVersionNumber);

  @override
  Future<FinancialAccountMutationResult> archive(
    String accountId,
    int expectedVersionNumber,
  ) => _lifecycle('archive', accountId, expectedVersionNumber);

  Future<FinancialAccountMutationResult> _lifecycle(
    String action,
    String accountId,
    int expectedVersionNumber,
  ) async {
    final data = await _action({
      'action': action,
      'financial_account_id': accountId,
      'expected_version_number': expectedVersionNumber,
    });
    return FinancialAccountMutationResult.fromJson(data['account']);
  }

  Future<Map<String, dynamic>> _action(Map<String, dynamic> body) async {
    final response = invokeFunction != null
        ? await invokeFunction!('financial-accounts', body)
        : await client.functions.invoke('financial-accounts', body: body);
    final envelope = response is FunctionResponse ? response.data : response;
    if (envelope is! Map<String, dynamic>) {
      throw const FinancialAccountFailure('Financial account response failed.');
    }
    if (envelope['error'] != null) {
      throw FinancialAccountFailure(envelope['error'].toString());
    }
    final data = envelope['data'];
    if (data is Map<String, dynamic>) return data;
    return envelope;
  }

  List<ExactMoney> _moneyRows(Object? value) => (value as List? ?? const [])
      .cast<Map<String, dynamic>>()
      .map(ExactMoney.fromJson)
      .toList(growable: false);
}

class FinancialAccountFailure implements Exception {
  const FinancialAccountFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
