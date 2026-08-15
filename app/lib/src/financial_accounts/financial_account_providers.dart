import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';
import 'financial_account_models.dart';
import 'financial_account_repository.dart';

final financialAccountRepositoryProvider = Provider<FinancialAccountRepository>(
  (ref) => SupabaseFinancialAccountRepository(),
);

final ownerFinancialAccountAccessProvider = Provider<bool>((ref) {
  return ref.watch(currentAccountProvider).routeTarget ==
      TrustedAccountRouteTarget.staff;
});

final financialAccountListProvider =
    NotifierProvider<FinancialAccountListController, FinancialAccountListState>(
      FinancialAccountListController.new,
    );

final financialAccountDetailProvider =
    NotifierProvider.family<
      FinancialAccountDetailController,
      FinancialAccountDetailState,
      String
    >((id) => FinancialAccountDetailController(id));

class FinancialAccountListController
    extends Notifier<FinancialAccountListState> {
  var _generation = 0;
  String? _authUserId;

  @override
  FinancialAccountListState build() {
    ref.listen<bool>(ownerFinancialAccountAccessProvider, (_, hasAccess) {
      if (!hasAccess) _clear();
    }, fireImmediately: true);
    final session = ref.watch(authSessionProvider);
    if (session.status != AuthSessionStatus.authenticated ||
        !ref.watch(ownerFinancialAccountAccessProvider)) {
      _clear();
      return const FinancialAccountListState.loaded(
        accounts: [],
        cashTotals: [],
        bankTotals: [],
      );
    }
    if (_authUserId != session.authUserId) _clear();
    _authUserId = session.authUserId;
    return const FinancialAccountListState.loading();
  }

  Future<void> load() async {
    final session = ref.read(authSessionProvider);
    if (!_hasAccess(session)) {
      _clear();
      return;
    }
    _authUserId = session.authUserId;
    final generation = ++_generation;
    state = const FinancialAccountListState.loading();
    try {
      final repository = ref.read(financialAccountRepositoryProvider);
      final results = await Future.wait([
        repository.listAccounts(),
        repository.cashTotalsByCurrency(),
        repository.bankTotalsByCurrency(),
      ]);
      if (!_canApply(generation, session.authUserId)) return;
      state = FinancialAccountListState.loaded(
        accounts: results[0] as List<FinancialAccount>,
        cashTotals: results[1] as List<ExactMoney>,
        bankTotals: results[2] as List<ExactMoney>,
      );
    } catch (error) {
      if (!_canApply(generation, session.authUserId)) return;
      state = FinancialAccountListState.failure(error);
    }
  }

  Future<void> refresh() => load();

  bool _hasAccess(AuthSessionState session) =>
      session.status == AuthSessionStatus.authenticated &&
      ref.read(ownerFinancialAccountAccessProvider);

  bool _canApply(int generation, String? authUserId) =>
      ref.mounted &&
      generation == _generation &&
      _hasAccess(ref.read(authSessionProvider)) &&
      ref.read(authSessionProvider).authUserId == authUserId &&
      _authUserId == authUserId;

  void _clear() {
    _generation++;
    _authUserId = null;
  }
}

class FinancialAccountDetailController
    extends Notifier<FinancialAccountDetailState> {
  FinancialAccountDetailController(this._accountId);

  final String _accountId;
  var _generation = 0;

  @override
  FinancialAccountDetailState build() {
    if (!ref.watch(ownerFinancialAccountAccessProvider)) {
      _generation++;
      return const FinancialAccountDetailState.failure(
        FinancialAccountFailure(
          'Financial accounts require an active Owner/Admin session.',
        ),
      );
    }
    return const FinancialAccountDetailState.loading();
  }

  Future<void> load() async {
    if (!ref.read(ownerFinancialAccountAccessProvider)) return;
    final generation = ++_generation;
    state = const FinancialAccountDetailState.loading();
    try {
      final account = await ref
          .read(financialAccountRepositoryProvider)
          .detail(_accountId);
      if (!_canApply(generation)) return;
      state = FinancialAccountDetailState.loaded(account);
    } catch (error) {
      if (!_canApply(generation)) return;
      state = FinancialAccountDetailState.failure(error);
    }
  }

  Future<bool> update(FinancialAccountDraft draft) => _mutate(
    (account) => ref
        .read(financialAccountRepositoryProvider)
        .update(
          accountId: _accountId,
          expectedVersionNumber: account.versionNumber,
          draft: draft,
        ),
  );

  Future<bool> activate() => _mutate(
    (account) => ref
        .read(financialAccountRepositoryProvider)
        .activate(_accountId, account.versionNumber),
  );

  Future<bool> deactivate() => _mutate(
    (account) => ref
        .read(financialAccountRepositoryProvider)
        .deactivate(_accountId, account.versionNumber),
  );

  Future<bool> archive() => _mutate(
    (account) => ref
        .read(financialAccountRepositoryProvider)
        .archive(_accountId, account.versionNumber),
  );

  Future<bool> _mutate(
    Future<FinancialAccountMutationResult> Function(FinancialAccount account)
    operation,
  ) async {
    final current = state.account;
    if (current == null || state.isMutating) return false;
    final generation = ++_generation;
    state = state.copyWith(isMutating: true, clearMutationError: true);
    try {
      await operation(current);
      final account = await ref
          .read(financialAccountRepositoryProvider)
          .detail(_accountId);
      if (!_canApply(generation)) return false;
      state = FinancialAccountDetailState.loaded(account);
      await ref.read(financialAccountListProvider.notifier).refresh();
      return true;
    } catch (error) {
      if (!_canApply(generation)) return false;
      state = state.copyWith(isMutating: false, mutationError: error);
      return false;
    }
  }

  bool _canApply(int generation) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(ownerFinancialAccountAccessProvider);
}
