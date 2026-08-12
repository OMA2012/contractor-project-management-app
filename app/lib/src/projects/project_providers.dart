import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';
import '../documents/document_models.dart';
import '../documents/document_providers.dart';
import 'project_models.dart';
import 'project_repository.dart';

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => const SupabaseProjectRepository(),
);

final clientProjectListProvider =
    NotifierProvider<ClientProjectListController, ClientProjectListState>(
      ClientProjectListController.new,
    );

final clientProjectDetailProvider =
    NotifierProvider.family<
      ClientProjectDetailController,
      ClientProjectDetailState,
      String
    >((projectId) => ClientProjectDetailController(projectId));

final clientProjectCompletionProvider =
    NotifierProvider.family<
      ClientProjectCompletionController,
      ClientProjectCompletionState,
      String
    >((projectId) => ClientProjectCompletionController(projectId));

final clientProjectProgressUpdatesProvider =
    NotifierProvider.family<
      ClientProjectProgressUpdatesController,
      ClientProgressUpdateListState,
      String
    >((projectId) => ClientProjectProgressUpdatesController(projectId));

final clientProjectDocumentsProvider =
    NotifierProvider.family<
      ClientProjectDocumentsController,
      DocumentPageState,
      String
    >((projectId) => ClientProjectDocumentsController(projectId));

final clientProjectPhotographsProvider =
    NotifierProvider.family<
      ClientProjectPhotographsController,
      PhotographGalleryState,
      String
    >((projectId) => ClientProjectPhotographsController(projectId));

final clientProjectAccessProvider = Provider<bool>((ref) {
  return ref.watch(clientProjectAccessContextProvider) != null;
});

final clientProjectAccessContextProvider =
    Provider<ClientProjectAccessContext?>((ref) {
      final session = ref.watch(authSessionProvider);
      final account = ref.watch(currentAccountProvider);
      if (session.status != AuthSessionStatus.authenticated ||
          account is! CurrentAccountLoaded ||
          account.routeTarget != TrustedAccountRouteTarget.client) {
        return null;
      }

      final currentAccount = account.account;
      return ClientProjectAccessContext(
        authStatus: session.status,
        authUserId: session.authUserId,
        applicationUserId: currentAccount.applicationUserId,
        routeTarget: account.routeTarget,
        accountStatus: currentAccount.accountStatus,
        isActive: currentAccount.isActive,
        accessAllowed: currentAccount.accessAllowed,
        userType: currentAccount.userType,
      );
    });

class ClientProjectAccessContext {
  const ClientProjectAccessContext({
    required this.authStatus,
    required this.authUserId,
    required this.applicationUserId,
    required this.routeTarget,
    required this.accountStatus,
    required this.isActive,
    required this.accessAllowed,
    required this.userType,
  });

  final AuthSessionStatus authStatus;
  final String? authUserId;
  final String applicationUserId;
  final TrustedAccountRouteTarget routeTarget;
  final AccountStatus accountStatus;
  final bool isActive;
  final bool accessAllowed;
  final AccountUserType userType;

  @override
  bool operator ==(Object other) {
    return other is ClientProjectAccessContext &&
        other.authStatus == authStatus &&
        other.authUserId == authUserId &&
        other.applicationUserId == applicationUserId &&
        other.routeTarget == routeTarget &&
        other.accountStatus == accountStatus &&
        other.isActive == isActive &&
        other.accessAllowed == accessAllowed &&
        other.userType == userType;
  }

  @override
  int get hashCode => Object.hash(
    authStatus,
    authUserId,
    applicationUserId,
    routeTarget,
    accountStatus,
    isActive,
    accessAllowed,
    userType,
  );
}

class ClientProjectListController extends Notifier<ClientProjectListState> {
  static const defaultLimit = 50;

  var _generation = 0;
  var _offset = 0;
  var _limit = defaultLimit;
  var _seen = <String>{};
  ClientProjectAccessContext? _accessContext;

  @override
  ClientProjectListState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null || accessContext != _accessContext) {
          _clear();
        }
      },
      fireImmediately: true,
    );
    final accessContext = ref.watch(clientProjectAccessContextProvider);
    if (accessContext == null) {
      if (ref.watch(currentAccountProvider).routeTarget ==
          TrustedAccountRouteTarget.loading) {
        return const ClientProjectListState(isLoading: true);
      }
      _clear();
      return const ClientProjectListState(hasMore: false);
    }
    if (_accessContext != accessContext) {
      _clear();
    }
    _accessContext = accessContext;
    return const ClientProjectListState(isLoading: true);
  }

  Future<void> load({int limit = defaultLimit}) async {
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      if (ref.read(currentAccountProvider).routeTarget ==
          TrustedAccountRouteTarget.loading) {
        state = const ClientProjectListState(isLoading: true);
        return;
      }
      _clear();
      state = const ClientProjectListState(hasMore: false);
      return;
    }
    _limit = limit.clamp(1, 100);
    _offset = 0;
    _seen = <String>{};
    _accessContext = accessContext;
    final generation = ++_generation;
    state = const ClientProjectListState(isLoading: true);
    await _loadPage(generation, accessContext, append: false);
  }

  Future<void> refresh() => load(limit: _limit);

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const ClientProjectListState(hasMore: false);
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
          .read(projectRepositoryProvider)
          .listClientProjects(limit: _limit, offset: _offset);
      if (!_canApply(generation, accessContext)) return;
      _offset += page.rawCount;
      final projects = append ? [...state.projects] : <ClientProject>[];
      for (final project in page.projects) {
        if (_seen.add(project.id)) projects.add(project);
      }
      state = ClientProjectListState(
        projects: projects,
        hasMore: page.rawCount == _limit,
      );
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = ClientProjectListState(
        projects: append ? state.projects : const [],
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

class ClientProjectDetailController extends Notifier<ClientProjectDetailState> {
  ClientProjectDetailController(this._projectId);

  final String _projectId;
  var _generation = 0;
  ClientProjectAccessContext? _accessContext;

  @override
  ClientProjectDetailState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null) {
          _generation++;
          _accessContext = null;
          state = const ClientProjectDetailState.unavailable();
        } else if (accessContext != _accessContext) {
          _generation++;
          _accessContext = null;
        }
      },
      fireImmediately: true,
    );
    final accessContext = ref.watch(clientProjectAccessContextProvider);
    if (accessContext == null) {
      if (ref.watch(currentAccountProvider).routeTarget ==
          TrustedAccountRouteTarget.loading) {
        return const ClientProjectDetailState.loading();
      }
      _generation++;
      _accessContext = null;
      return const ClientProjectDetailState.unavailable();
    }
    if (_accessContext != accessContext) {
      _generation++;
      _accessContext = accessContext;
    }
    return const ClientProjectDetailState.loading();
  }

  Future<void> load() async {
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      if (ref.read(currentAccountProvider).routeTarget ==
          TrustedAccountRouteTarget.loading) {
        state = const ClientProjectDetailState.loading();
        return;
      }
      _generation++;
      _accessContext = null;
      state = const ClientProjectDetailState.unavailable();
      return;
    }
    _accessContext = accessContext;
    final generation = ++_generation;
    state = const ClientProjectDetailState.loading();
    try {
      final project = await ref
          .read(projectRepositoryProvider)
          .getClientProject(_projectId);
      if (!_canApply(generation, accessContext)) return;
      state = project == null
          ? const ClientProjectDetailState.unavailable()
          : ClientProjectDetailState.loaded(project);
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = ClientProjectDetailState.failure(error);
    }
  }

  bool _canApply(int generation, ClientProjectAccessContext accessContext) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(clientProjectAccessContextProvider) == accessContext &&
      _accessContext == accessContext;
}

class ClientProjectCompletionController
    extends Notifier<ClientProjectCompletionState> {
  ClientProjectCompletionController(this._projectId);

  final String _projectId;
  var _generation = 0;
  ClientProjectAccessContext? _accessContext;

  @override
  ClientProjectCompletionState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null || accessContext != _accessContext) _clear();
      },
      fireImmediately: true,
    );
    return ref.watch(clientProjectAccessContextProvider) == null
        ? const ClientProjectCompletionState()
        : const ClientProjectCompletionState(isLoading: true);
  }

  Future<void> load() async {
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const ClientProjectCompletionState();
      return;
    }
    _accessContext = accessContext;
    final generation = ++_generation;
    state = const ClientProjectCompletionState(isLoading: true);
    try {
      final completion = await ref
          .read(projectRepositoryProvider)
          .getClientProjectCompletion(_projectId);
      if (!_canApply(generation, accessContext)) return;
      state = ClientProjectCompletionState(completion: completion);
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = ClientProjectCompletionState(error: error);
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

class ClientProjectProgressUpdatesController
    extends Notifier<ClientProgressUpdateListState> {
  ClientProjectProgressUpdatesController(this._projectId);

  static const defaultLimit = 10;

  final String _projectId;
  var _generation = 0;
  var _offset = 0;
  var _limit = defaultLimit;
  var _seen = <String>{};
  ClientProjectAccessContext? _accessContext;

  @override
  ClientProgressUpdateListState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null || accessContext != _accessContext) _clear();
      },
      fireImmediately: true,
    );
    return ref.watch(clientProjectAccessContextProvider) == null
        ? const ClientProgressUpdateListState(hasMore: false)
        : const ClientProgressUpdateListState(isLoading: true);
  }

  Future<void> load({int limit = defaultLimit}) async {
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const ClientProgressUpdateListState(hasMore: false);
      return;
    }
    _limit = limit.clamp(1, 100);
    _offset = 0;
    _seen = <String>{};
    _accessContext = accessContext;
    final generation = ++_generation;
    state = const ClientProgressUpdateListState(isLoading: true);
    await _loadPage(generation, accessContext, append: false);
  }

  Future<void> refresh() => load(limit: _limit);

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const ClientProgressUpdateListState(hasMore: false);
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
          .read(projectRepositoryProvider)
          .listClientProgressUpdates(
            _projectId,
            limit: _limit,
            offset: _offset,
          );
      if (!_canApply(generation, accessContext)) return;
      _offset += page.rawCount;
      final items = append ? [...state.items] : <ClientProgressUpdate>[];
      for (final item in page.items) {
        if (_seen.add(item.id)) items.add(item);
      }
      state = ClientProgressUpdateListState(
        items: items,
        hasMore: page.rawCount == _limit,
      );
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = ClientProgressUpdateListState(
        items: append ? state.items : const [],
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

class ClientProjectDocumentsController extends Notifier<DocumentPageState> {
  ClientProjectDocumentsController(this._projectId);

  static const defaultLimit = 10;

  final String _projectId;
  var _generation = 0;
  var _offset = 0;
  var _limit = defaultLimit;
  var _seen = <String>{};
  ClientProjectAccessContext? _accessContext;

  @override
  DocumentPageState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null || accessContext != _accessContext) _clear();
      },
      fireImmediately: true,
    );
    return ref.watch(clientProjectAccessContextProvider) == null
        ? const DocumentPageState(hasMore: false)
        : const DocumentPageState(isLoading: true);
  }

  Future<void> load({int limit = defaultLimit}) async {
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const DocumentPageState(hasMore: false);
      return;
    }
    _limit = limit.clamp(1, 100);
    _offset = 0;
    _seen = <String>{};
    _accessContext = accessContext;
    final generation = ++_generation;
    state = const DocumentPageState(isLoading: true);
    await _loadPage(generation, accessContext, append: false);
  }

  Future<void> refresh() => load(limit: _limit);

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const DocumentPageState(hasMore: false);
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
          .read(documentRepositoryProvider)
          .listClientProjectDocuments(
            _projectId,
            limit: _limit,
            offset: _offset,
          );
      if (!_canApply(generation, accessContext)) return;
      _offset += page.rawCount;
      final documents = append ? [...state.documents] : <SafeDocument>[];
      for (final document in page.documents) {
        if (_seen.add(document.id)) documents.add(document);
      }
      state = DocumentPageState(
        documents: documents,
        hasMore: page.rawCount == _limit,
      );
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = DocumentPageState(
        documents: append ? state.documents : const [],
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

class ClientProjectPhotographsController
    extends Notifier<PhotographGalleryState> {
  ClientProjectPhotographsController(this._projectId);

  static const defaultLimit = 12;

  final String _projectId;
  var _generation = 0;
  var _offset = 0;
  var _limit = defaultLimit;
  var _seen = <String>{};
  ClientProjectAccessContext? _accessContext;

  @override
  PhotographGalleryState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, accessContext) {
        if (accessContext == null || accessContext != _accessContext) _clear();
      },
      fireImmediately: true,
    );
    return ref.watch(clientProjectAccessContextProvider) == null
        ? const PhotographGalleryState(hasMore: false)
        : const PhotographGalleryState(isLoading: true);
  }

  Future<void> load({int limit = defaultLimit}) async {
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const PhotographGalleryState(hasMore: false);
      return;
    }
    _limit = limit.clamp(1, 100);
    _offset = 0;
    _seen = <String>{};
    _accessContext = accessContext;
    final generation = ++_generation;
    state = const PhotographGalleryState(isLoading: true);
    await _loadPage(generation, accessContext, append: false);
  }

  Future<void> refresh() => load(limit: _limit);

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final accessContext = ref.read(clientProjectAccessContextProvider);
    if (accessContext == null) {
      _clear();
      state = const PhotographGalleryState(hasMore: false);
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
          .read(documentRepositoryProvider)
          .listClientProjectPhotographs(
            _projectId,
            limit: _limit,
            offset: _offset,
          );
      if (!_canApply(generation, accessContext)) return;
      _offset += page.rawCount;
      final items = append ? [...state.items] : <PhotographGalleryItem>[];
      for (final item in page.items) {
        if (_seen.add(item.id)) items.add(item);
      }
      state = PhotographGalleryState(
        items: items,
        hasMore: page.rawCount == _limit,
      );
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = PhotographGalleryState(
        items: append ? state.items : const [],
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
