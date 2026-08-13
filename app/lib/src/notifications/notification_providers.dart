import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../projects/project_providers.dart';
import 'notification_models.dart';
import 'notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => const SupabaseNotificationRepository(),
);

final clientNotificationListProvider =
    NotifierProvider<
      ClientNotificationListController,
      ClientNotificationListState
    >(ClientNotificationListController.new);

final clientNotificationDetailProvider =
    NotifierProvider.family<
      ClientNotificationDetailController,
      ClientNotificationDetailState,
      String
    >((notificationId) => ClientNotificationDetailController(notificationId));

class ClientNotificationListController
    extends Notifier<ClientNotificationListState> {
  static const defaultLimit = 50;

  var _generation = 0;
  var _offset = 0;
  var _limit = defaultLimit;
  var _seen = <String>{};
  ClientProjectAccessContext? _accessContext;

  @override
  ClientNotificationListState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null || accessContext != _accessContext) {
          _clear();
        }
      },
      fireImmediately: true,
    );
    return ref.watch(clientProjectAccessContextProvider) == null
        ? const ClientNotificationListState(hasMore: false)
        : const ClientNotificationListState(isLoading: true);
  }

  Future<void> load({
    ClientNotificationListFilter? filter,
    int limit = defaultLimit,
  }) async {
    final effectiveFilter = filter ?? state.filter;
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = ClientNotificationListState(
        filter: effectiveFilter,
        hasMore: false,
      );
      return;
    }
    _limit = limit.clamp(1, 100);
    _offset = 0;
    _seen = <String>{};
    _accessContext = accessContext;
    final generation = ++_generation;
    state = ClientNotificationListState(
      filter: effectiveFilter,
      isLoading: true,
    );
    await _loadPage(generation, accessContext, effectiveFilter, append: false);
  }

  Future<void> refresh() => load(filter: state.filter, limit: _limit);

  Future<void> setFilter(ClientNotificationListFilter filter) {
    return load(filter: filter, limit: _limit);
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = ClientNotificationListState(filter: state.filter, hasMore: false);
      return;
    }
    _accessContext = accessContext;
    final generation = ++_generation;
    final filter = state.filter;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    await _loadPage(generation, accessContext, filter, append: true);
  }

  Future<void> _loadPage(
    int generation,
    ClientProjectAccessContext accessContext,
    ClientNotificationListFilter filter, {
    required bool append,
  }) async {
    try {
      final page = await ref
          .read(notificationRepositoryProvider)
          .listClientNotifications(
            status: filter.status,
            includeArchived: filter.includeArchived,
            limit: _limit,
            offset: _offset,
          );
      if (!_canApply(generation, accessContext, filter)) return;
      _offset += page.rawCount;
      final items = append ? [...state.items] : <ClientNotification>[];
      for (final item in page.items) {
        if (_seen.add(item.id)) items.add(item);
      }
      state = ClientNotificationListState(
        items: items,
        filter: filter,
        hasMore: page.rawCount == _limit,
      );
    } catch (error) {
      if (!_canApply(generation, accessContext, filter)) return;
      state = ClientNotificationListState(
        items: append ? state.items : const [],
        filter: filter,
        error: error,
        hasMore: append ? state.hasMore : false,
      );
    }
  }

  bool _canApply(
    int generation,
    ClientProjectAccessContext accessContext,
    ClientNotificationListFilter filter,
  ) {
    return ref.mounted &&
        generation == _generation &&
        state.filter == filter &&
        ref.read(clientProjectAccessContextProvider) == accessContext &&
        _accessContext == accessContext;
  }

  void _clear() {
    _generation++;
    _offset = 0;
    _seen = <String>{};
    _accessContext = null;
  }
}

class ClientNotificationDetailController
    extends Notifier<ClientNotificationDetailState> {
  ClientNotificationDetailController(this._notificationId);

  final String _notificationId;
  var _generation = 0;
  var _loadedForGeneration = false;
  var _mutating = false;
  ClientProjectAccessContext? _accessContext;

  @override
  ClientNotificationDetailState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null || accessContext != _accessContext) {
          _clear();
        }
      },
      fireImmediately: true,
    );
    return ref.watch(clientProjectAccessContextProvider) == null
        ? const ClientNotificationDetailState.unavailable()
        : const ClientNotificationDetailState.loading();
  }

  Future<void> load({bool force = false}) async {
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const ClientNotificationDetailState.unavailable();
      return;
    }
    if (!force &&
        _loadedForGeneration &&
        _accessContext == accessContext &&
        state.notification?.id == _notificationId) {
      return;
    }
    _accessContext = accessContext;
    _loadedForGeneration = true;
    final generation = ++_generation;
    state = const ClientNotificationDetailState.loading();
    try {
      final detail = await ref
          .read(notificationRepositoryProvider)
          .getClientNotification(_notificationId);
      if (!_canApply(generation, accessContext)) return;
      if (detail == null) {
        state = const ClientNotificationDetailState.unavailable();
        return;
      }
      if (detail.status == ClientNotificationStatus.unread) {
        final read = await ref
            .read(notificationRepositoryProvider)
            .markClientNotificationRead(_notificationId);
        if (!_canApply(generation, accessContext)) return;
        state = ClientNotificationDetailState.loaded(read);
        ref.invalidate(clientNotificationListProvider);
        return;
      }
      state = ClientNotificationDetailState.loaded(detail);
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = ClientNotificationDetailState.failure(error);
    }
  }

  Future<void> markRead() => _mutate(
    (repository) => repository.markClientNotificationRead(_notificationId),
  );

  Future<void> markUnread() => _mutate(
    (repository) => repository.markClientNotificationUnread(_notificationId),
  );

  Future<void> archive() => _mutate(
    (repository) => repository.archiveClientNotification(_notificationId),
  );

  Future<void> _mutate(
    Future<ClientNotification> Function(NotificationRepository repository)
    mutation,
  ) async {
    if (_mutating) return;
    final current = state.notification;
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (current == null || accessContext == null) return;
    final generation = ++_generation;
    _accessContext = accessContext;
    _mutating = true;
    state = ClientNotificationDetailState.loaded(current, isMutating: true);
    try {
      final updated = await mutation(ref.read(notificationRepositoryProvider));
      if (!_canApply(generation, accessContext)) return;
      state = ClientNotificationDetailState.loaded(updated);
      ref.invalidate(clientNotificationListProvider);
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = ClientNotificationDetailState.loaded(current, error: error);
    } finally {
      if (_canApply(generation, accessContext)) _mutating = false;
    }
  }

  bool _canApply(int generation, ClientProjectAccessContext accessContext) {
    return ref.mounted &&
        generation == _generation &&
        ref.read(clientProjectAccessContextProvider) == accessContext &&
        _accessContext == accessContext;
  }

  void _clear() {
    _generation++;
    _loadedForGeneration = false;
    _mutating = false;
    _accessContext = null;
  }
}
