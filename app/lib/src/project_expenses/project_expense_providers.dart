import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';
import '../financial_accounts/financial_account_providers.dart';
import '../opening_balances/opening_balance_providers.dart';
import 'project_expense_models.dart';
import 'project_expense_repository.dart';

final projectExpenseRepositoryProvider = Provider<ProjectExpenseRepository>(
  (ref) => ProjectExpenseRepository(),
);

final ownerProjectExpenseAccessProvider = Provider<bool>(
  (ref) =>
      ref.watch(currentAccountProvider).routeTarget ==
      TrustedAccountRouteTarget.staff,
);

final projectExpenseListProvider =
    AsyncNotifierProvider<ProjectExpenseListController, List<ProjectExpense>>(
      ProjectExpenseListController.new,
    );

final projectExpenseDetailProvider =
    NotifierProvider.family<
      ProjectExpenseDetailController,
      AsyncValue<ProjectExpense>,
      String
    >((id) => ProjectExpenseDetailController(id));

class ProjectExpenseListController extends AsyncNotifier<List<ProjectExpense>> {
  var _generation = 0;
  String? _authUserId;
  @override
  Future<List<ProjectExpense>> build() async {
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
      final items = await ref.read(projectExpenseRepositoryProvider).list();
      return _canApply(generation, session.authUserId)
          ? items
          : state.value ?? [];
    });
  }

  Future<void> refresh() => load();

  void _watchIsolation() {
    final session = ref.watch(authSessionProvider);
    final hasAccess = ref.watch(ownerProjectExpenseAccessProvider);
    if (session.status != AuthSessionStatus.authenticated || !hasAccess) {
      _generation++;
      _authUserId = null;
    }
  }

  bool _hasAccess() =>
      ref.read(authSessionProvider).status == AuthSessionStatus.authenticated &&
      ref.read(ownerProjectExpenseAccessProvider);
  bool _canApply(int generation, String? authUserId) =>
      ref.mounted &&
      generation == _generation &&
      _hasAccess() &&
      _authUserId == authUserId &&
      ref.read(authSessionProvider).authUserId == authUserId;
}

class ProjectExpenseDetailController
    extends Notifier<AsyncValue<ProjectExpense>> {
  ProjectExpenseDetailController(this._financialEventId);
  final String _financialEventId;
  var _generation = 0;

  @override
  AsyncValue<ProjectExpense> build() {
    if (!ref.watch(ownerProjectExpenseAccessProvider)) {
      return const AsyncError(
        ProjectExpenseFailure(
          'Project expenses require an active Owner/Admin session.',
        ),
        StackTrace.empty,
      );
    }
    Future.microtask(reload);
    return const AsyncLoading();
  }

  Future<bool> createOrUpdate(ProjectExpenseDraft draft) async {
    final current = state.value;
    try {
      if (current == null) {
        final result = await ref
            .read(projectExpenseRepositoryProvider)
            .create(draft);
        await ref.read(projectExpenseListProvider.notifier).refresh();
        state = AsyncData(
          await ref
              .read(projectExpenseRepositoryProvider)
              .detail(result.financialEventId),
        );
      } else {
        await ref
            .read(projectExpenseRepositoryProvider)
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
        .read(projectExpenseRepositoryProvider)
        .submit(item.financialEventId, item.versionNumber),
  );
  Future<bool> approve() => _mutate(
    (item) => ref
        .read(projectExpenseRepositoryProvider)
        .approve(item.financialEventId, item.versionNumber),
  );
  Future<bool> reject(String reason) => _mutate(
    (item) => ref
        .read(projectExpenseRepositoryProvider)
        .reject(item.financialEventId, item.versionNumber, reason),
  );

  Future<void> reload() async {
    final generation = ++_generation;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final item = await ref
          .read(projectExpenseRepositoryProvider)
          .detail(_financialEventId);
      return ref.mounted && generation == _generation ? item : state.value!;
    });
  }

  Future<bool> _mutate(
    Future<ProjectExpenseMutationResult> Function(ProjectExpense item) action,
  ) async {
    final current = state.value;
    if (current == null) return false;
    try {
      await action(current);
      await reload();
      await ref.read(projectExpenseListProvider.notifier).refresh();
      await ref.read(financialApprovalQueueProvider.notifier).load();
      ref.invalidate(financialAccountListProvider);
      return true;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
    }
  }
}
