import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';
import '../financial_accounts/financial_account_providers.dart';
import '../opening_balances/opening_balance_providers.dart';
import 'owner_payment_models.dart';
import 'owner_payment_repository.dart';

final ownerPaymentRepositoryProvider = Provider<OwnerPaymentRepository>(
  (ref) => SupabaseOwnerPaymentRepository(),
);

final ownerPaymentAccessProvider = Provider<bool>(
  (ref) =>
      ref.watch(currentAccountProvider).routeTarget ==
      TrustedAccountRouteTarget.staff,
);

final ownerClientPaymentListProvider =
    AsyncNotifierProvider<
      OwnerClientPaymentListController,
      List<OwnerClientPayment>
    >(OwnerClientPaymentListController.new);

final ownerClientPaymentDetailProvider =
    NotifierProvider.family<
      OwnerClientPaymentDetailController,
      AsyncValue<OwnerClientPayment>,
      String
    >((id) => OwnerClientPaymentDetailController(id));

final ownerPaymentRequestListProvider =
    AsyncNotifierProvider<
      OwnerPaymentRequestListController,
      List<OwnerPaymentRequest>
    >(OwnerPaymentRequestListController.new);

final ownerPaymentRequestDetailProvider =
    NotifierProvider.family<
      OwnerPaymentRequestDetailController,
      AsyncValue<OwnerPaymentRequest>,
      String
    >((id) => OwnerPaymentRequestDetailController(id));

class OwnerClientPaymentListController
    extends AsyncNotifier<List<OwnerClientPayment>> {
  var _generation = 0;
  String? _authUserId;
  @override
  Future<List<OwnerClientPayment>> build() async {
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
      final rows = await ref
          .read(ownerPaymentRepositoryProvider)
          .listPayments();
      return _canApply(generation, session.authUserId)
          ? rows
          : state.value ?? [];
    });
  }

  Future<void> refresh() => load();
  void _watchIsolation() {
    final session = ref.watch(authSessionProvider);
    final hasAccess = ref.watch(ownerPaymentAccessProvider);
    if (session.status != AuthSessionStatus.authenticated || !hasAccess) {
      _generation++;
      _authUserId = null;
    }
  }

  bool _hasAccess() =>
      ref.read(authSessionProvider).status == AuthSessionStatus.authenticated &&
      ref.read(ownerPaymentAccessProvider);
  bool _canApply(int generation, String? authUserId) =>
      ref.mounted &&
      generation == _generation &&
      _hasAccess() &&
      _authUserId == authUserId &&
      ref.read(authSessionProvider).authUserId == authUserId;
}

class OwnerClientPaymentDetailController
    extends Notifier<AsyncValue<OwnerClientPayment>> {
  OwnerClientPaymentDetailController(this._financialEventId);
  final String _financialEventId;
  var _generation = 0;
  @override
  AsyncValue<OwnerClientPayment> build() {
    if (!ref.watch(ownerPaymentAccessProvider)) {
      return const AsyncError(
        OwnerPaymentFailure(
          'Client payments require an active Owner/Admin session.',
        ),
        StackTrace.empty,
      );
    }
    Future.microtask(reload);
    return const AsyncLoading();
  }

  Future<void> reload() async {
    final generation = ++_generation;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final item = await ref
          .read(ownerPaymentRepositoryProvider)
          .paymentDetail(_financialEventId);
      return ref.mounted && generation == _generation ? item : state.value!;
    });
  }

  Future<bool> createOrUpdate(OwnerClientPaymentDraft draft) async {
    final current = state.value;
    try {
      if (current == null) {
        final result = await ref
            .read(ownerPaymentRepositoryProvider)
            .createPayment(draft);
        if (result.financialEventId != null) {
          state = AsyncData(
            await ref
                .read(ownerPaymentRepositoryProvider)
                .paymentDetail(result.financialEventId!),
          );
        }
      } else {
        await ref
            .read(ownerPaymentRepositoryProvider)
            .updatePayment(
              financialEventId: current.financialEventId,
              expectedVersionNumber: current.versionNumber,
              draft: draft,
            );
        await reload();
      }
      await ref.read(ownerClientPaymentListProvider.notifier).refresh();
      return true;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
    }
  }

  Future<bool> verifyClientSubmitted(String accountId, String? notes) =>
      _mutate(
        (item) => ref
            .read(ownerPaymentRepositoryProvider)
            .verifyClientSubmitted(
              financialEventId: item.financialEventId,
              expectedVersionNumber: item.versionNumber,
              receivedAccountId: accountId,
              notes: notes,
            ),
      );
  Future<bool> submit() => _mutate(
    (item) => ref
        .read(ownerPaymentRepositoryProvider)
        .submitPayment(item.financialEventId, item.versionNumber),
  );
  Future<bool> approve() => _mutate(
    (item) => ref
        .read(ownerPaymentRepositoryProvider)
        .approvePayment(item.financialEventId, item.versionNumber),
  );
  Future<bool> reject(String reason) => _mutate(
    (item) => ref
        .read(ownerPaymentRepositoryProvider)
        .rejectPayment(item.financialEventId, item.versionNumber, reason),
  );
  Future<bool> _mutate(
    Future<OwnerPaymentMutationResult> Function(OwnerClientPayment item) action,
  ) async {
    final current = state.value;
    if (current == null) return false;
    try {
      await action(current);
      await reload();
      await ref.read(ownerClientPaymentListProvider.notifier).refresh();
      await ref.read(financialApprovalQueueProvider.notifier).load();
      ref.invalidate(financialAccountListProvider);
      return true;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
    }
  }
}

class OwnerPaymentRequestListController
    extends AsyncNotifier<List<OwnerPaymentRequest>> {
  @override
  Future<List<OwnerPaymentRequest>> build() async {
    if (!ref.watch(ownerPaymentAccessProvider)) return const [];
    return const [];
  }

  Future<void> load() async {
    if (!ref.read(ownerPaymentAccessProvider)) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(ownerPaymentRepositoryProvider).listRequests(),
    );
  }

  Future<void> refresh() => load();
}

class OwnerPaymentRequestDetailController
    extends Notifier<AsyncValue<OwnerPaymentRequest>> {
  OwnerPaymentRequestDetailController(this._paymentRequestId);
  final String _paymentRequestId;
  @override
  AsyncValue<OwnerPaymentRequest> build() {
    if (!ref.watch(ownerPaymentAccessProvider)) {
      return const AsyncError(
        OwnerPaymentFailure(
          'Payment requests require an active Owner/Admin session.',
        ),
        StackTrace.empty,
      );
    }
    Future.microtask(reload);
    return const AsyncLoading();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(ownerPaymentRepositoryProvider)
          .requestDetail(_paymentRequestId),
    );
  }

  Future<bool> createOrUpdate(OwnerPaymentRequestDraft draft) async {
    final current = state.value;
    try {
      if (current != null) {
        await ref
            .read(ownerPaymentRepositoryProvider)
            .updateRequest(
              paymentRequestId: current.paymentRequestId,
              expectedVersionNumber: current.versionNumber,
              draft: draft,
            );
        await reload();
      }
      await ref.read(ownerPaymentRequestListProvider.notifier).refresh();
      return true;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
    }
  }

  Future<bool> send() => _mutate(
    (item) => ref
        .read(ownerPaymentRepositoryProvider)
        .sendRequest(item.paymentRequestId, item.versionNumber),
  );
  Future<bool> cancel(String reason) => _mutate(
    (item) => ref
        .read(ownerPaymentRepositoryProvider)
        .cancelRequest(item.paymentRequestId, item.versionNumber, reason),
  );
  Future<bool> _mutate(
    Future<OwnerPaymentMutationResult> Function(OwnerPaymentRequest item)
    action,
  ) async {
    final current = state.value;
    if (current == null) return false;
    try {
      await action(current);
      await reload();
      await ref.read(ownerPaymentRequestListProvider.notifier).refresh();
      return true;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
    }
  }
}
