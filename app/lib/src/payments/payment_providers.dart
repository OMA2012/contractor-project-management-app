import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../projects/project_providers.dart';
import 'payment_models.dart';
import 'payment_repository.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => const SupabasePaymentRepository(),
);

final clientApprovedPaymentListProvider =
    NotifierProvider<
      ClientApprovedPaymentListController,
      ClientPaymentListState
    >(ClientApprovedPaymentListController.new);

final clientApprovedPaymentDetailProvider =
    NotifierProvider.family<
      ClientApprovedPaymentDetailController,
      ClientPaymentDetailState,
      String
    >((paymentId) => ClientApprovedPaymentDetailController(paymentId));

final clientPaymentRequestListProvider =
    NotifierProvider<
      ClientPaymentRequestListController,
      ClientPaymentRequestListState
    >(ClientPaymentRequestListController.new);

final clientPaymentRequestDetailProvider =
    NotifierProvider.family<
      ClientPaymentRequestDetailController,
      ClientPaymentRequestDetailState,
      String
    >((requestId) => ClientPaymentRequestDetailController(requestId));

final clientPaymentSubmitProvider =
    NotifierProvider<ClientPaymentSubmitController, ClientPaymentSubmitState>(
      ClientPaymentSubmitController.new,
    );

class ClientApprovedPaymentListController
    extends Notifier<ClientPaymentListState> {
  static const defaultLimit = 50;

  var _generation = 0;
  var _offset = 0;
  var _limit = defaultLimit;
  var _seen = <String>{};
  ClientProjectAccessContext? _accessContext;

  @override
  ClientPaymentListState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null || accessContext != _accessContext) _clear();
      },
      fireImmediately: true,
    );
    return ref.watch(clientProjectAccessContextProvider) == null
        ? const ClientPaymentListState(hasMore: false)
        : const ClientPaymentListState(isLoading: true);
  }

  Future<void> load({int limit = defaultLimit}) async {
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const ClientPaymentListState(hasMore: false);
      return;
    }
    _limit = limit.clamp(1, 100);
    _offset = 0;
    _seen = <String>{};
    _accessContext = accessContext;
    final generation = ++_generation;
    state = const ClientPaymentListState(isLoading: true);
    await _loadPage(generation, accessContext, append: false);
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const ClientPaymentListState(hasMore: false);
      return;
    }
    _accessContext = accessContext;
    final generation = ++_generation;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    await _loadPage(generation, accessContext, append: true);
  }

  Future<void> _loadPage(
    int generation,
    ClientProjectAccessContext accessContext, {
    required bool append,
  }) async {
    try {
      final page = await ref
          .read(paymentRepositoryProvider)
          .listApprovedPayments(limit: _limit, offset: _offset);
      if (!_canApply(generation, accessContext)) return;
      _offset += page.rawCount;
      final payments = append ? [...state.payments] : <ClientApprovedPayment>[];
      for (final payment in page.payments) {
        if (_seen.add(payment.clientPaymentId)) payments.add(payment);
      }
      state = ClientPaymentListState(
        payments: payments,
        hasMore: page.rawCount == _limit,
      );
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = ClientPaymentListState(
        payments: append ? state.payments : const [],
        error: error,
        hasMore: append ? state.hasMore : false,
      );
    }
  }

  bool _canApply(int generation, ClientProjectAccessContext accessContext) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(clientProjectAccessContextProvider) == accessContext &&
      _accessContext == accessContext;

  void _clear() {
    _generation++;
    _offset = 0;
    _seen = <String>{};
    _accessContext = null;
  }
}

class ClientApprovedPaymentDetailController
    extends Notifier<ClientPaymentDetailState> {
  ClientApprovedPaymentDetailController(this._paymentId);

  final String _paymentId;
  var _generation = 0;
  ClientProjectAccessContext? _accessContext;

  @override
  ClientPaymentDetailState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null || accessContext != _accessContext) _clear();
      },
      fireImmediately: true,
    );
    return ref.watch(clientProjectAccessContextProvider) == null
        ? const ClientPaymentDetailState.unavailable()
        : const ClientPaymentDetailState.loading();
  }

  Future<void> load() async {
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const ClientPaymentDetailState.unavailable();
      return;
    }
    _accessContext = accessContext;
    final generation = ++_generation;
    state = const ClientPaymentDetailState.loading();
    try {
      final payment = await ref
          .read(paymentRepositoryProvider)
          .getApprovedPaymentDetail(_paymentId);
      if (!_canApply(generation, accessContext)) return;
      state = payment == null
          ? const ClientPaymentDetailState.unavailable()
          : ClientPaymentDetailState.loaded(payment);
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = ClientPaymentDetailState.failure(error);
    }
  }

  bool _canApply(int generation, ClientProjectAccessContext accessContext) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(clientProjectAccessContextProvider) == accessContext &&
      _accessContext == accessContext;

  void _clear() {
    _generation++;
    _accessContext = null;
  }
}

class ClientPaymentRequestListController
    extends Notifier<ClientPaymentRequestListState> {
  static const defaultLimit = 50;

  var _generation = 0;
  var _offset = 0;
  var _limit = defaultLimit;
  var _seen = <String>{};
  ClientProjectAccessContext? _accessContext;

  @override
  ClientPaymentRequestListState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null || accessContext != _accessContext) _clear();
      },
      fireImmediately: true,
    );
    return ref.watch(clientProjectAccessContextProvider) == null
        ? const ClientPaymentRequestListState(hasMore: false)
        : const ClientPaymentRequestListState(isLoading: true);
  }

  Future<void> load({int limit = defaultLimit}) async {
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const ClientPaymentRequestListState(hasMore: false);
      return;
    }
    _limit = limit.clamp(1, 100);
    _offset = 0;
    _seen = <String>{};
    _accessContext = accessContext;
    final generation = ++_generation;
    state = const ClientPaymentRequestListState(isLoading: true);
    await _loadPage(generation, accessContext, append: false);
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const ClientPaymentRequestListState(hasMore: false);
      return;
    }
    _accessContext = accessContext;
    final generation = ++_generation;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    await _loadPage(generation, accessContext, append: true);
  }

  Future<void> _loadPage(
    int generation,
    ClientProjectAccessContext accessContext, {
    required bool append,
  }) async {
    try {
      final page = await ref
          .read(paymentRepositoryProvider)
          .listPaymentRequests(limit: _limit, offset: _offset);
      if (!_canApply(generation, accessContext)) return;
      _offset += page.rawCount;
      final requests = append ? [...state.requests] : <ClientPaymentRequest>[];
      for (final request in page.requests) {
        if (_seen.add(request.paymentRequestId)) requests.add(request);
      }
      state = ClientPaymentRequestListState(
        requests: requests,
        hasMore: page.rawCount == _limit,
      );
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = ClientPaymentRequestListState(
        requests: append ? state.requests : const [],
        error: error,
        hasMore: append ? state.hasMore : false,
      );
    }
  }

  bool _canApply(int generation, ClientProjectAccessContext accessContext) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(clientProjectAccessContextProvider) == accessContext &&
      _accessContext == accessContext;

  void _clear() {
    _generation++;
    _offset = 0;
    _seen = <String>{};
    _accessContext = null;
  }
}

class ClientPaymentRequestDetailController
    extends Notifier<ClientPaymentRequestDetailState> {
  ClientPaymentRequestDetailController(this._requestId);

  final String _requestId;
  var _generation = 0;
  ClientProjectAccessContext? _accessContext;

  @override
  ClientPaymentRequestDetailState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null || accessContext != _accessContext) _clear();
      },
      fireImmediately: true,
    );
    return ref.watch(clientProjectAccessContextProvider) == null
        ? const ClientPaymentRequestDetailState.unavailable()
        : const ClientPaymentRequestDetailState.loading();
  }

  Future<void> load() async {
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const ClientPaymentRequestDetailState.unavailable();
      return;
    }
    _accessContext = accessContext;
    final generation = ++_generation;
    state = const ClientPaymentRequestDetailState.loading();
    try {
      final request = await ref
          .read(paymentRepositoryProvider)
          .viewPaymentRequestDetail(_requestId);
      if (!_canApply(generation, accessContext)) return;
      state = request == null
          ? const ClientPaymentRequestDetailState.unavailable()
          : ClientPaymentRequestDetailState.loaded(request);
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = ClientPaymentRequestDetailState.failure(error);
    }
  }

  bool _canApply(int generation, ClientProjectAccessContext accessContext) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(clientProjectAccessContextProvider) == accessContext &&
      _accessContext == accessContext;

  void _clear() {
    _generation++;
    _accessContext = null;
  }
}

class ClientPaymentSubmitController extends Notifier<ClientPaymentSubmitState> {
  var _generation = 0;
  ClientProjectAccessContext? _accessContext;

  @override
  ClientPaymentSubmitState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null || accessContext != _accessContext) {
          _generation++;
          _accessContext = null;
          state = const ClientPaymentSubmitState();
        }
      },
      fireImmediately: true,
    );
    return const ClientPaymentSubmitState();
  }

  Future<void> submit({
    required String projectId,
    required ExactMoney amount,
    required String currencyCode,
    required DateTime receivedDate,
    String? paymentReference,
    String? payerName,
  }) async {
    if (state.isSubmitting) return;
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      state = const ClientPaymentSubmitState(
        error: PaymentFailure('Payment submission is unavailable.'),
      );
      return;
    }
    _accessContext = accessContext;
    final generation = ++_generation;
    state = const ClientPaymentSubmitState(isSubmitting: true);
    try {
      final result = await ref
          .read(paymentRepositoryProvider)
          .submitPayment(
            projectId: projectId,
            amount: amount,
            currencyCode: currencyCode,
            receivedDate: receivedDate,
            paymentReference: paymentReference,
            payerName: payerName,
          );
      if (!_canApply(generation, accessContext)) return;
      state = ClientPaymentSubmitState(result: result);
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = ClientPaymentSubmitState(error: error);
    }
  }

  bool _canApply(int generation, ClientProjectAccessContext accessContext) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(clientProjectAccessContextProvider) == accessContext &&
      _accessContext == accessContext;
}
