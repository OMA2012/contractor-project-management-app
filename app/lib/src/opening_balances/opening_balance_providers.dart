import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';
import '../financial_accounts/financial_account_providers.dart';
import 'opening_balance_models.dart';
import 'opening_balance_repository.dart';

final openingBalanceRepositoryProvider = Provider<OpeningBalanceRepository>(
  (ref) => SupabaseOpeningBalanceRepository(),
);

final ownerOpeningBalanceAccessProvider = Provider<bool>(
  (ref) =>
      ref.watch(currentAccountProvider).routeTarget ==
      TrustedAccountRouteTarget.staff,
);

final openingBalanceListProvider =
    AsyncNotifierProvider<OpeningBalanceListController, List<OpeningBalance>>(
      OpeningBalanceListController.new,
    );

final openingBalanceDetailProvider =
    NotifierProvider.family<
      OpeningBalanceDetailController,
      AsyncValue<OpeningBalance>,
      String
    >((id) => OpeningBalanceDetailController(id));

final financialApprovalQueueProvider =
    AsyncNotifierProvider<
      FinancialApprovalQueueController,
      FinancialApprovalQueue
    >(FinancialApprovalQueueController.new);

class OpeningBalanceListController extends AsyncNotifier<List<OpeningBalance>> {
  var _generation = 0;
  String? _authUserId;

  @override
  Future<List<OpeningBalance>> build() async {
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
      final items = await ref.read(openingBalanceRepositoryProvider).list();
      return _canApply(generation, session.authUserId)
          ? items
          : state.value ?? [];
    });
  }

  Future<void> refresh() => load();

  void _watchIsolation() {
    final session = ref.watch(authSessionProvider);
    final hasAccess = ref.watch(ownerOpeningBalanceAccessProvider);
    if (session.status != AuthSessionStatus.authenticated || !hasAccess) {
      _generation++;
      _authUserId = null;
    }
  }

  bool _hasAccess() =>
      ref.read(authSessionProvider).status == AuthSessionStatus.authenticated &&
      ref.read(ownerOpeningBalanceAccessProvider);
  bool _canApply(int generation, String? authUserId) =>
      ref.mounted &&
      generation == _generation &&
      _hasAccess() &&
      _authUserId == authUserId &&
      ref.read(authSessionProvider).authUserId == authUserId;
}

class OpeningBalanceDetailController
    extends Notifier<AsyncValue<OpeningBalance>> {
  OpeningBalanceDetailController(this._financialEventId);

  final String _financialEventId;
  var _generation = 0;

  @override
  AsyncValue<OpeningBalance> build() {
    if (!ref.watch(ownerOpeningBalanceAccessProvider)) {
      return const AsyncError(
        OpeningBalanceFailure(
          'Opening balances require an active Owner/Admin session.',
        ),
        StackTrace.empty,
      );
    }
    Future.microtask(reload);
    return const AsyncLoading();
  }

  Future<bool> createOrUpdate(OpeningBalanceDraft draft) async {
    final current = state.value;
    try {
      if (current == null) {
        final result = await ref
            .read(openingBalanceRepositoryProvider)
            .create(draft);
        await ref.read(openingBalanceListProvider.notifier).refresh();
        state = AsyncData(
          await ref
              .read(openingBalanceRepositoryProvider)
              .detail(result.financialEventId),
        );
      } else {
        await ref
            .read(openingBalanceRepositoryProvider)
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
        .read(openingBalanceRepositoryProvider)
        .submit(item.financialEventId, item.versionNumber),
  );
  Future<bool> approve() => _mutate(
    (item) => ref
        .read(openingBalanceRepositoryProvider)
        .approve(item.financialEventId, item.versionNumber),
  );
  Future<bool> reject(String reason) => _mutate(
    (item) => ref
        .read(openingBalanceRepositoryProvider)
        .reject(item.financialEventId, item.versionNumber, reason),
  );

  Future<void> reload() async {
    final generation = ++_generation;
    final id = _financialEventId;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final item = await ref.read(openingBalanceRepositoryProvider).detail(id);
      return ref.mounted && generation == _generation ? item : state.value!;
    });
  }

  Future<bool> _mutate(
    Future<OpeningBalanceMutationResult> Function(OpeningBalance item) action,
  ) async {
    final current = state.value;
    if (current == null) return false;
    try {
      await action(current);
      await reload();
      await ref.read(openingBalanceListProvider.notifier).refresh();
      await ref.read(financialApprovalQueueProvider.notifier).load();
      ref.invalidate(financialAccountListProvider);
      return true;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
    }
  }
}

class FinancialApprovalQueue {
  const FinancialApprovalQueue({
    this.eligible = const [],
    this.createdByMe = const [],
    this.recent = const [],
    this.rejected = const [],
  });
  final List<FinancialApprovalQueueItem> eligible;
  final List<FinancialApprovalQueueItem> createdByMe;
  final List<FinancialApprovalQueueItem> recent;
  final List<FinancialApprovalQueueItem> rejected;
}

class FinancialApprovalQueueController
    extends AsyncNotifier<FinancialApprovalQueue> {
  @override
  Future<FinancialApprovalQueue> build() async {
    if (!ref.watch(ownerOpeningBalanceAccessProvider)) {
      return const FinancialApprovalQueue();
    }
    return const FinancialApprovalQueue();
  }

  Future<void> load() async {
    if (!ref.read(ownerOpeningBalanceAccessProvider)) {
      state = const AsyncData(FinancialApprovalQueue());
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(openingBalanceRepositoryProvider);
      final rows = await Future.wait([
        repo.queue('eligible'),
        repo.queue('created_by_me'),
        repo.queue('recent'),
        repo.queue('rejected'),
      ]);
      return FinancialApprovalQueue(
        eligible: rows[0],
        createdByMe: rows[1],
        recent: rows[2],
        rejected: rows[3],
      );
    });
  }
}
