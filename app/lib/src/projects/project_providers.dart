import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';
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

final clientProjectAccessProvider = Provider<bool>((ref) {
  return ref.watch(clientProjectAccessContextProvider) != null;
});

final clientProjectAccessContextProvider =
    Provider<_ClientProjectAccessContext?>((ref) {
      final session = ref.watch(authSessionProvider);
      final account = ref.watch(currentAccountProvider);
      if (session.status != AuthSessionStatus.authenticated ||
          account is! CurrentAccountLoaded ||
          account.routeTarget != TrustedAccountRouteTarget.client) {
        return null;
      }

      final currentAccount = account.account;
      return _ClientProjectAccessContext(
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

class _ClientProjectAccessContext {
  const _ClientProjectAccessContext({
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
    return other is _ClientProjectAccessContext &&
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
  _ClientProjectAccessContext? _accessContext;

  @override
  ClientProjectListState build() {
    ref.listen<_ClientProjectAccessContext?>(
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
    _ClientProjectAccessContext accessContext, {
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

  bool _canApply(int generation, _ClientProjectAccessContext accessContext) =>
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
  _ClientProjectAccessContext? _accessContext;

  @override
  ClientProjectDetailState build() {
    ref.listen<_ClientProjectAccessContext?>(
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

  bool _canApply(int generation, _ClientProjectAccessContext accessContext) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(clientProjectAccessContextProvider) == accessContext &&
      _accessContext == accessContext;
}
