import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/routing/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initialization does not redirect protected routes to login', () {
    final redirect = authRedirect(
      const AuthSessionState.initializing(),
      Uri(path: '/staff'),
    );

    expect(redirect, isNull);
  });

  test('unauthenticated users are redirected away from protected routes', () {
    final redirect = authRedirect(
      const AuthSessionState.unauthenticated(),
      Uri(path: '/staff'),
    );

    expect(redirect, '/login');
  });

  test('restored authenticated session without trusted role loads account', () {
    final redirect = authRedirect(
      const AuthSessionState.accountLoading(email: 'person@example.com'),
      Uri(path: '/staff'),
    );

    expect(redirect, '/account-loading');
  });

  test('account loading route does not redirect to login', () {
    final redirect = authRedirect(
      const AuthSessionState.accountLoading(email: 'person@example.com'),
      Uri(path: '/account-loading'),
    );

    expect(redirect, isNull);
  });

  test('allows unauthenticated users to request a password reset', () {
    final redirect = authRedirect(
      const AuthSessionState.unauthenticated(),
      Uri(path: '/reset-password'),
    );

    expect(redirect, isNull);
  });

  test('password recovery redirects to password update', () {
    final redirect = authRedirect(
      const AuthSessionState.passwordRecovery(email: 'person@example.com'),
      Uri(path: '/staff'),
    );

    expect(redirect, '/update-password');
  });

  test('password recovery permits password update route', () {
    final redirect = authRedirect(
      const AuthSessionState.passwordRecovery(email: 'person@example.com'),
      Uri(path: '/update-password'),
    );

    expect(redirect, isNull);
  });

  test('inactive account route does not loop', () {
    final redirect = authRedirect(
      const AuthSessionState.inactive(email: 'person@example.com'),
      Uri(path: '/inactive-account'),
    );

    expect(redirect, isNull);
  });

  test('keeps staff out of the client shell using trusted role state', () {
    final redirect = authRedirect(
      const AuthSessionState.authenticated(role: AccountRole.staff),
      Uri(path: '/client'),
    );

    expect(redirect, '/staff');
  });

  test('root waits during initialization', () {
    expect(rootRedirect(const AuthSessionState.initializing()), isNull);
  });
}
