import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AccountRole { staff, client }

enum AuthSessionStatus {
  initializing,
  unauthenticated,
  accountLoading,
  authenticated,
  passwordRecovery,
  inactive,
}

class AuthSessionState {
  const AuthSessionState({required this.status, this.role, this.email});

  const AuthSessionState.initializing()
    : status = AuthSessionStatus.initializing,
      role = null,
      email = null;

  const AuthSessionState.unauthenticated()
    : status = AuthSessionStatus.unauthenticated,
      role = null,
      email = null;

  const AuthSessionState.accountLoading({this.email})
    : status = AuthSessionStatus.accountLoading,
      role = null;

  const AuthSessionState.authenticated({
    required AccountRole this.role,
    this.email,
  }) : status = AuthSessionStatus.authenticated;

  const AuthSessionState.passwordRecovery({this.email})
    : status = AuthSessionStatus.passwordRecovery,
      role = null;

  const AuthSessionState.inactive({this.email})
    : status = AuthSessionStatus.inactive,
      role = null;

  final AuthSessionStatus status;
  final AccountRole? role;
  final String? email;

  bool get isAuthenticated =>
      status == AuthSessionStatus.accountLoading ||
      status == AuthSessionStatus.authenticated;

  bool get isInitializing => status == AuthSessionStatus.initializing;
}

final initialAuthSessionProvider = Provider<AuthSessionState?>((ref) => null);

final trustedAccountRoleProvider = Provider<AccountRole?>((ref) => null);

final authSessionSourceProvider = Provider<AuthSessionSource>((ref) {
  return SupabaseAuthSessionSource();
});

final authSessionProvider =
    NotifierProvider<AuthSessionController, AuthSessionState>(
      AuthSessionController.new,
    );

class AuthSessionController extends Notifier<AuthSessionState> {
  StreamSubscription<AuthSessionChange>? _authSubscription;

  @override
  AuthSessionState build() {
    final initialSession = ref.watch(initialAuthSessionProvider);
    if (initialSession != null) {
      return initialSession;
    }

    final source = ref.watch(authSessionSourceProvider);
    _authSubscription = source.onAuthStateChange.listen(_applyAuthChange);
    ref.onDispose(() => _authSubscription?.cancel());

    Future<void>.microtask(() => _restoreSession(source));

    return const AuthSessionState.initializing();
  }

  Future<void> _restoreSession(AuthSessionSource source) async {
    final restoredSession = source.currentSession;
    if (restoredSession == null) {
      state = const AuthSessionState.unauthenticated();
      return;
    }

    state = _authenticatedStateFor(restoredSession.email);
  }

  void _applyAuthChange(AuthSessionChange change) {
    switch (change.event) {
      case AuthSessionChangeEvent.initialSession:
      case AuthSessionChangeEvent.signedIn:
      case AuthSessionChangeEvent.tokenRefreshed:
      case AuthSessionChangeEvent.userUpdated:
        if (change.session == null) {
          state = const AuthSessionState.unauthenticated();
          return;
        }
        state = _authenticatedStateFor(change.session!.email);
      case AuthSessionChangeEvent.signedOut:
        state = const AuthSessionState.unauthenticated();
      case AuthSessionChangeEvent.passwordRecovery:
        state = AuthSessionState.passwordRecovery(email: change.session?.email);
    }
  }

  AuthSessionState _authenticatedStateFor(String? email) {
    final trustedRole = ref.read(trustedAccountRoleProvider);
    if (trustedRole == null) {
      return AuthSessionState.accountLoading(email: email);
    }

    return AuthSessionState.authenticated(role: trustedRole, email: email);
  }

  void signInAsStaff(String email) {
    state = AuthSessionState.authenticated(
      role: AccountRole.staff,
      email: email,
    );
  }

  void signInAsClient(String email) {
    state = AuthSessionState.authenticated(
      role: AccountRole.client,
      email: email,
    );
  }

  void requestPasswordReset(String email) {
    state = AuthSessionState.passwordRecovery(email: email);
  }

  void updatePassword() {
    state = const AuthSessionState.unauthenticated();
  }

  void markInactive(String email) {
    state = AuthSessionState.inactive(email: email);
  }

  void signOut() {
    state = const AuthSessionState.unauthenticated();
  }
}

enum AuthSessionChangeEvent {
  initialSession,
  signedIn,
  signedOut,
  tokenRefreshed,
  userUpdated,
  passwordRecovery,
}

class AuthSessionSnapshot {
  const AuthSessionSnapshot({this.email});

  final String? email;
}

class AuthSessionChange {
  const AuthSessionChange({required this.event, this.session});

  final AuthSessionChangeEvent event;
  final AuthSessionSnapshot? session;
}

abstract class AuthSessionSource {
  AuthSessionSnapshot? get currentSession;

  Stream<AuthSessionChange> get onAuthStateChange;
}

class SupabaseAuthSessionSource implements AuthSessionSource {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  AuthSessionSnapshot? get currentSession => _snapshotFor(_auth.currentSession);

  @override
  Stream<AuthSessionChange> get onAuthStateChange =>
      _auth.onAuthStateChange.map(_changeFor);

  AuthSessionChange _changeFor(AuthState state) {
    return AuthSessionChange(
      event: _eventFor(state.event),
      session: _snapshotFor(state.session),
    );
  }

  AuthSessionChangeEvent _eventFor(AuthChangeEvent event) {
    return switch (event) {
      AuthChangeEvent.initialSession => AuthSessionChangeEvent.initialSession,
      AuthChangeEvent.signedIn => AuthSessionChangeEvent.signedIn,
      AuthChangeEvent.signedOut => AuthSessionChangeEvent.signedOut,
      AuthChangeEvent.tokenRefreshed => AuthSessionChangeEvent.tokenRefreshed,
      AuthChangeEvent.userUpdated => AuthSessionChangeEvent.userUpdated,
      AuthChangeEvent.passwordRecovery =>
        AuthSessionChangeEvent.passwordRecovery,
      AuthChangeEvent.mfaChallengeVerified =>
        AuthSessionChangeEvent.userUpdated,
      _ => AuthSessionChangeEvent.userUpdated,
    };
  }

  AuthSessionSnapshot? _snapshotFor(Session? session) {
    if (session == null) {
      return null;
    }

    return AuthSessionSnapshot(email: session.user.email);
  }
}
