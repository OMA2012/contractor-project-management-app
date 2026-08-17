import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';
import 'financial_correction_models.dart';
import 'financial_correction_repository.dart';

final financialCorrectionRepositoryProvider =
    Provider<FinancialCorrectionRepository>(
      (ref) => FinancialCorrectionRepository(),
    );

final ownerFinancialCorrectionAccessProvider = Provider<bool>(
  (ref) =>
      ref.watch(currentAccountProvider).routeTarget ==
      TrustedAccountRouteTarget.staff,
);

final correctionSourceListProvider =
    AsyncNotifierProvider<
      CorrectionSourceListController,
      List<CorrectionSource>
    >(CorrectionSourceListController.new);
final reversalListProvider =
    AsyncNotifierProvider<ReversalListController, List<FinancialReversal>>(
      ReversalListController.new,
    );
final adjustmentListProvider =
    AsyncNotifierProvider<AdjustmentListController, List<FinancialAdjustment>>(
      AdjustmentListController.new,
    );
final reversalDetailProvider =
    NotifierProvider.family<
      ReversalDetailController,
      AsyncValue<FinancialReversal>,
      String
    >((id) => ReversalDetailController(id));
final adjustmentDetailProvider =
    NotifierProvider.family<
      AdjustmentDetailController,
      AsyncValue<FinancialAdjustment>,
      String
    >((id) => AdjustmentDetailController(id));

abstract class _ListController<T> extends AsyncNotifier<List<T>> {
  Future<List<T>> fetch(FinancialCorrectionRepository repo);
  @override
  Future<List<T>> build() async {
    ref.watch(authSessionProvider);
    if (!ref.watch(ownerFinancialCorrectionAccessProvider)) return const [];
    return const [];
  }

  Future<void> load() async {
    if (!ref.read(ownerFinancialCorrectionAccessProvider)) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => fetch(ref.read(financialCorrectionRepositoryProvider)),
    );
  }
}

class CorrectionSourceListController extends _ListController<CorrectionSource> {
  @override
  Future<List<CorrectionSource>> fetch(FinancialCorrectionRepository repo) =>
      repo.eligibleSources();
}

class ReversalListController extends _ListController<FinancialReversal> {
  @override
  Future<List<FinancialReversal>> fetch(FinancialCorrectionRepository repo) =>
      repo.reversals();
}

class AdjustmentListController extends _ListController<FinancialAdjustment> {
  @override
  Future<List<FinancialAdjustment>> fetch(FinancialCorrectionRepository repo) =>
      repo.adjustments();
}

class ReversalDetailController extends Notifier<AsyncValue<FinancialReversal>> {
  ReversalDetailController(this.id);
  final String id;
  @override
  AsyncValue<FinancialReversal> build() {
    Future.microtask(reload);
    return const AsyncLoading();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(financialCorrectionRepositoryProvider).reversalDetail(id),
    );
  }

  Future<bool> submit() => _run(
    (x) => ref
        .read(financialCorrectionRepositoryProvider)
        .submitReversal(x.financialEventId, x.versionNumber),
  );
  Future<bool> approve() => _run(
    (x) => ref
        .read(financialCorrectionRepositoryProvider)
        .approveReversal(x.financialEventId, x.versionNumber),
  );
  Future<bool> reject(String reason) => _run(
    (x) => ref
        .read(financialCorrectionRepositoryProvider)
        .rejectReversal(x.financialEventId, x.versionNumber, reason),
  );
  Future<bool> _run(
    Future<CorrectionMutationResult> Function(FinancialReversal) op,
  ) async {
    final item = state.value;
    if (item == null) return false;
    try {
      await op(item);
      await reload();
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }
}

class AdjustmentDetailController
    extends Notifier<AsyncValue<FinancialAdjustment>> {
  AdjustmentDetailController(this.id);
  final String id;
  @override
  AsyncValue<FinancialAdjustment> build() {
    Future.microtask(reload);
    return const AsyncLoading();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () =>
          ref.read(financialCorrectionRepositoryProvider).adjustmentDetail(id),
    );
  }

  Future<bool> update(AdjustmentDraft draft) async {
    final item = state.value;
    if (item == null) return false;
    try {
      await ref
          .read(financialCorrectionRepositoryProvider)
          .updateAdjustment(item.financialEventId, item.versionNumber, draft);
      await reload();
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }

  Future<bool> submit() => _run(
    (x) => ref
        .read(financialCorrectionRepositoryProvider)
        .submitAdjustment(x.financialEventId, x.versionNumber),
  );
  Future<bool> approve() => _run(
    (x) => ref
        .read(financialCorrectionRepositoryProvider)
        .approveAdjustment(x.financialEventId, x.versionNumber),
  );
  Future<bool> reject(String reason) => _run(
    (x) => ref
        .read(financialCorrectionRepositoryProvider)
        .rejectAdjustment(x.financialEventId, x.versionNumber, reason),
  );
  Future<bool> _run(
    Future<CorrectionMutationResult> Function(FinancialAdjustment) op,
  ) async {
    final item = state.value;
    if (item == null) return false;
    try {
      await op(item);
      await reload();
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }
}
