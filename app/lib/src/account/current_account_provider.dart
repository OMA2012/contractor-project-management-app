import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_session.dart';
import 'current_account.dart';
import 'current_account_repository.dart';

final currentAccountRepositoryProvider = Provider<CurrentAccountRepository>(
  (ref) => const CurrentAccountRepository(),
);

final currentAccountProvider =
    NotifierProvider<CurrentAccountController, CurrentAccountState>(
      CurrentAccountController.new,
    );

class CurrentAccountController extends Notifier<CurrentAccountState> {
  var _requestGeneration = 0;
  String? _activeAuthUserId;

  @override
  CurrentAccountState build() {
    final session = ref.watch(authSessionProvider);
    if (session.status == AuthSessionStatus.initializing) {
      _invalidateActiveLoad();
      return const CurrentAccountState.initializing();
    }
    if (session.status != AuthSessionStatus.authenticated) {
      _invalidateActiveLoad();
      return const CurrentAccountState.notProvisioned();
    }

    final authUserId = session.authUserId;
    _activeAuthUserId = authUserId;
    final generation = ++_requestGeneration;
    Future<void>.microtask(
      () => loadForAuthenticatedUser(authUserId, generation),
    );
    return const CurrentAccountState.loading();
  }

  Future<void> load() async {
    final session = ref.read(authSessionProvider);
    if (session.status != AuthSessionStatus.authenticated) {
      _invalidateActiveLoad();
      state = const CurrentAccountState.notProvisioned();
      return;
    }

    final authUserId = session.authUserId;
    _activeAuthUserId = authUserId;
    final generation = ++_requestGeneration;
    await loadForAuthenticatedUser(authUserId, generation);
  }

  Future<void> loadForAuthenticatedUser(
    String? authUserId,
    int generation,
  ) async {
    state = const CurrentAccountState.loading();
    try {
      final account = await ref
          .read(currentAccountRepositoryProvider)
          .loadCurrentAccount();
      if (!_canApplyResult(authUserId, generation)) {
        return;
      }
      state = _stateFor(account);
    } catch (error) {
      if (!_canApplyResult(authUserId, generation)) {
        return;
      }
      state = CurrentAccountState.failure(error);
    }
  }

  void clear() {
    _invalidateActiveLoad();
    state = const CurrentAccountState.notProvisioned();
  }

  void _invalidateActiveLoad() {
    _activeAuthUserId = null;
    _requestGeneration++;
  }

  bool _canApplyResult(String? authUserId, int generation) {
    if (!ref.mounted) {
      return false;
    }

    final session = ref.read(authSessionProvider);
    return generation == _requestGeneration &&
        session.status == AuthSessionStatus.authenticated &&
        session.authUserId == authUserId &&
        _activeAuthUserId == authUserId;
  }

  CurrentAccountState _stateFor(CurrentAccount? account) {
    if (account == null) {
      return const CurrentAccountState.notProvisioned();
    }

    return switch (account.accountStatus) {
      AccountStatus.invited => const CurrentAccountState.pendingInvite(),
      AccountStatus.suspended => const CurrentAccountState.suspended(),
      AccountStatus.disabled => const CurrentAccountState.deactivated(),
      AccountStatus.active => _activeStateFor(account),
      AccountStatus.unknown => const CurrentAccountState.noActiveRole(),
    };
  }

  CurrentAccountState _activeStateFor(CurrentAccount account) {
    if (!account.isActive || !account.accessAllowed) {
      return const CurrentAccountState.noActiveRole();
    }

    final validStaff =
        account.userType == AccountUserType.staff &&
        account.hasStaffRole &&
        !account.hasClientRole;
    final validClient =
        account.userType == AccountUserType.client &&
        account.hasClientRole &&
        !account.hasStaffRole;

    if (!validStaff && !validClient) {
      return const CurrentAccountState.noActiveRole();
    }

    return CurrentAccountState.loaded(account);
  }
}
