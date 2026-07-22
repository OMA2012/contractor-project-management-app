import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_session.dart';
import '../screens/account_loading_screen.dart';
import '../screens/inactive_account_screen.dart';
import '../screens/login_screen.dart';
import '../screens/password_reset_request_screen.dart';
import '../screens/password_update_screen.dart';
import '../screens/protected_shell_screen.dart';
import '../screens/role_home_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(authSessionProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) => authRedirect(session, state.uri),
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => rootRedirect(session),
        builder: (context, state) => const AccountLoadingScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const PasswordResetRequestScreen(),
      ),
      GoRoute(
        path: '/update-password',
        builder: (context, state) => const PasswordUpdateScreen(),
      ),
      GoRoute(
        path: '/inactive-account',
        builder: (context, state) => const InactiveAccountScreen(),
      ),
      GoRoute(
        path: '/account-loading',
        builder: (context, state) => const AccountLoadingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => ProtectedShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/staff',
            builder: (context, state) =>
                const RoleHomeScreen(role: AccountRole.staff),
          ),
          GoRoute(
            path: '/client',
            builder: (context, state) =>
                const RoleHomeScreen(role: AccountRole.client),
          ),
        ],
      ),
    ],
  );
});

String? authRedirect(AuthSessionState session, Uri uri) {
  final path = uri.path;
  final isLogin = path == '/login';
  final isPasswordReset = path == '/reset-password';
  final isPasswordUpdate = path == '/update-password';
  final isInactive = path == '/inactive-account';
  final isAccountLoading = path == '/account-loading';
  final isPublic = isLogin || isPasswordReset || isPasswordUpdate || isInactive;

  if (session.isInitializing) {
    return null;
  }

  if (session.status == AuthSessionStatus.inactive) {
    return isInactive ? null : '/inactive-account';
  }

  if (session.status == AuthSessionStatus.passwordRecovery) {
    return isPasswordUpdate ? null : '/update-password';
  }

  if (!session.isAuthenticated) {
    if (isPublic) {
      return null;
    }
    return '/login';
  }

  if (session.status == AuthSessionStatus.accountLoading) {
    return isAccountLoading ? null : '/account-loading';
  }

  if (isPublic) {
    return defaultHomeFor(session);
  }

  if (path == '/staff' && session.role != AccountRole.staff) {
    return defaultHomeFor(session);
  }

  if (path == '/client' && session.role != AccountRole.client) {
    return defaultHomeFor(session);
  }

  return null;
}

String? rootRedirect(AuthSessionState session) {
  return switch (session.status) {
    AuthSessionStatus.initializing => null,
    AuthSessionStatus.unauthenticated => '/login',
    AuthSessionStatus.accountLoading => '/account-loading',
    AuthSessionStatus.passwordRecovery => '/update-password',
    AuthSessionStatus.inactive => '/inactive-account',
    AuthSessionStatus.authenticated => defaultHomeFor(session),
  };
}

String defaultHomeFor(AuthSessionState session) {
  return switch (session.role) {
    AccountRole.client => '/client',
    AccountRole.staff || null => '/staff',
  };
}
