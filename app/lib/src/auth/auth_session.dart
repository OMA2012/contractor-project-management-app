import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AccountRole { staff, client }

enum AuthSessionStatus {
  initializing,
  unauthenticated,
  authenticated,
  passwordRecovery,
}

class AuthSessionState {
  const AuthSessionState({
    required this.status,
    this.role,
    this.authUserId,
    this.email,
  });

  const AuthSessionState.initializing()
    : status = AuthSessionStatus.initializing,
      role = null,
      email = null,
      authUserId = null;

  const AuthSessionState.unauthenticated()
    : status = AuthSessionStatus.unauthenticated,
      role = null,
      email = null,
      authUserId = null;

  const AuthSessionState.authenticated({this.authUserId, this.email})
    : status = AuthSessionStatus.authenticated,
      role = null;

  const AuthSessionState.passwordRecovery({this.email})
    : status = AuthSessionStatus.passwordRecovery,
      role = null,
      authUserId = null;

  final AuthSessionStatus status;
  final AccountRole? role;
  final String? authUserId;
  final String? email;

  bool get isAuthenticated => status == AuthSessionStatus.authenticated;

  bool get isInitializing => status == AuthSessionStatus.initializing;
}

final initialAuthSessionProvider = Provider<AuthSessionState?>((ref) => null);

final authSessionSourceProvider = Provider<AuthSessionSource>((ref) {
  return SupabaseAuthSessionSource();
});

final authActionsProvider = Provider<AuthActions>((ref) {
  return SupabaseAuthActions();
});

final passwordRecoveryRedirectProvider = Provider<String>((ref) {
  return Uri.base.resolve('/update-password').toString();
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

    state = AuthSessionState.authenticated(
      authUserId: restoredSession.authUserId,
      email: restoredSession.email,
    );
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
        state = AuthSessionState.authenticated(
          authUserId: change.session!.authUserId,
          email: change.session!.email,
        );
      case AuthSessionChangeEvent.signedOut:
        state = const AuthSessionState.unauthenticated();
      case AuthSessionChangeEvent.passwordRecovery:
        state = AuthSessionState.passwordRecovery(email: change.session?.email);
    }
  }

  Future<void> signIn(String email, String password) async {
    final session = await ref
        .read(authActionsProvider)
        .signInWithPassword(email.trim(), password);
    state = AuthSessionState.authenticated(
      authUserId: session.authUserId,
      email: session.email,
    );
  }

  Future<void> requestPasswordReset(String email) {
    return ref
        .read(authActionsProvider)
        .resetPasswordForEmail(
          email.trim(),
          ref.read(passwordRecoveryRedirectProvider),
        );
  }

  Future<void> updatePassword(String password) async {
    await ref.read(authActionsProvider).updatePassword(password);
    await signOut();
  }

  Future<void> signOut() async {
    try {
      await ref.read(authActionsProvider).signOut();
    } catch (_) {
      // Local protected state still fails closed when remote sign-out is
      // temporarily unavailable.
    } finally {
      state = const AuthSessionState.unauthenticated();
    }
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
  const AuthSessionSnapshot({this.authUserId, this.email});

  final String? authUserId;
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

abstract class AuthActions {
  Future<AuthSessionSnapshot> signInWithPassword(String email, String password);

  Future<void> resetPasswordForEmail(String email, String redirectTo);

  Future<void> updatePassword(String password);

  Future<void> signOut();
}

class SupabaseAuthActions implements AuthActions {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  Future<AuthSessionSnapshot> signInWithPassword(
    String email,
    String password,
  ) async {
    final response = await _auth.signInWithPassword(
      email: email,
      password: password,
    );
    final session = response.session;
    if (session == null) {
      throw const AuthException('Authentication failed.');
    }
    return AuthSessionSnapshot(
      authUserId: session.user.id,
      email: session.user.email,
    );
  }

  @override
  Future<void> resetPasswordForEmail(String email, String redirectTo) {
    return _auth.resetPasswordForEmail(email, redirectTo: redirectTo);
  }

  @override
  Future<void> updatePassword(String password) async {
    await _auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> signOut() => _auth.signOut();
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

    return AuthSessionSnapshot(
      authUserId: session.user.id,
      email: session.user.email,
    );
  }
}
