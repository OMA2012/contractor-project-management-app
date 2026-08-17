import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';
import '../financial_accounts/financial_account_providers.dart';
import '../opening_balances/opening_balance_providers.dart';
import 'currency_exchange_models.dart';
import 'currency_exchange_repository.dart';

final currencyExchangeRepositoryProvider = Provider<CurrencyExchangeRepository>(
  (ref) => CurrencyExchangeRepository(),
);

final ownerCurrencyExchangeAccessProvider = Provider<bool>(
  (ref) =>
      ref.watch(currentAccountProvider).routeTarget ==
      TrustedAccountRouteTarget.staff,
);

final currencyExchangeListProvider =
    AsyncNotifierProvider<
      CurrencyExchangeListController,
      List<CurrencyExchange>
    >(CurrencyExchangeListController.new);

final currencyExchangeDetailProvider =
    NotifierProvider.family<
      CurrencyExchangeDetailController,
      AsyncValue<CurrencyExchange>,
      String
    >((id) => CurrencyExchangeDetailController(id));

class CurrencyExchangeListController
    extends AsyncNotifier<List<CurrencyExchange>> {
  var _generation = 0;
  String? _authUserId;
  @override
  Future<List<CurrencyExchange>> build() async {
    _watchIsolation();
    return const [];
  }

  Future<void> load() async {
    if (!_hasAccess()) {
      state = const AsyncData([]);
      return;
    }
    final session = ref.read(authSessionProvider);
    _authUserId = session.authUserId;
    final generation = ++_generation;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final items = await ref.read(currencyExchangeRepositoryProvider).list();
      return _canApply(generation, session.authUserId)
          ? items
          : state.value ?? [];
    });
  }

  Future<void> refresh() => load();

  void _watchIsolation() {
    final session = ref.watch(authSessionProvider);
    final hasAccess = ref.watch(ownerCurrencyExchangeAccessProvider);
    if (session.status != AuthSessionStatus.authenticated || !hasAccess) {
      _generation++;
      _authUserId = null;
    }
  }

  bool _hasAccess() =>
      ref.read(authSessionProvider).status == AuthSessionStatus.authenticated &&
      ref.read(ownerCurrencyExchangeAccessProvider);
  bool _canApply(int generation, String? authUserId) =>
      ref.mounted &&
      generation == _generation &&
      _hasAccess() &&
      _authUserId == authUserId &&
      ref.read(authSessionProvider).authUserId == authUserId;
}

class CurrencyExchangeDetailController
    extends Notifier<AsyncValue<CurrencyExchange>> {
  CurrencyExchangeDetailController(this._financialEventId);
  final String _financialEventId;
  var _generation = 0;

  @override
  AsyncValue<CurrencyExchange> build() {
    if (!ref.watch(ownerCurrencyExchangeAccessProvider)) {
      return const AsyncError(
        CurrencyExchangeFailure(
          'Currency exchanges require an active Owner/Admin session.',
        ),
        StackTrace.empty,
      );
    }
    Future.microtask(reload);
    return const AsyncLoading();
  }

  Future<bool> createOrUpdate(CurrencyExchangeDraft draft) async {
    final current = state.value;
    try {
      if (current == null) {
        final result = await ref
            .read(currencyExchangeRepositoryProvider)
            .create(draft);
        await ref.read(currencyExchangeListProvider.notifier).refresh();
        state = AsyncData(
          await ref
              .read(currencyExchangeRepositoryProvider)
              .detail(result.financialEventId),
        );
      } else {
        await ref
            .read(currencyExchangeRepositoryProvider)
            .update(
              financialEventId: current.financialEventId,
              expectedVersionNumber: current.versionNumber,
              draft: draft,
            );
        await reload();
      }
      return true;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
    }
  }

  Future<bool> submit() => _mutate(
    (item) => ref
        .read(currencyExchangeRepositoryProvider)
        .submit(item.financialEventId, item.versionNumber),
  );
  Future<bool> approve() => _mutate(
    (item) => ref
        .read(currencyExchangeRepositoryProvider)
        .approve(item.financialEventId, item.versionNumber),
  );
  Future<bool> reject(String reason) => _mutate(
    (item) => ref
        .read(currencyExchangeRepositoryProvider)
        .reject(item.financialEventId, item.versionNumber, reason),
  );

  Future<void> reload() async {
    final generation = ++_generation;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final item = await ref
          .read(currencyExchangeRepositoryProvider)
          .detail(_financialEventId);
      return ref.mounted && generation == _generation ? item : state.value!;
    });
  }

  Future<bool> _mutate(
    Future<CurrencyExchangeMutationResult> Function(CurrencyExchange item)
    action,
  ) async {
    final current = state.value;
    if (current == null) return false;
    try {
      await action(current);
      await reload();
      await ref.read(currencyExchangeListProvider.notifier).refresh();
      await ref.read(financialApprovalQueueProvider.notifier).load();
      ref.invalidate(financialAccountListProvider);
      return true;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
    }
  }
}
