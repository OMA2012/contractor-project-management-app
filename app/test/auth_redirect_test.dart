import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/routing/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initialization does not redirect protected routes to login', () {
    final redirect = authRedirect(
      const AuthSessionState.initializing(),
      const CurrentAccountState.initializing(),
      Uri(path: '/staff'),
    );

    expect(redirect, isNull);
  });

  test('unauthenticated users are redirected away from protected routes', () {
    final redirect = authRedirect(
      const AuthSessionState.unauthenticated(),
      const CurrentAccountState.notProvisioned(),
      Uri(path: '/staff'),
    );

    expect(redirect, '/login');
  });

  test('restored authenticated session loads trusted account', () {
    final redirect = authRedirect(
      const AuthSessionState.authenticated(email: 'person@example.com'),
      const CurrentAccountState.loading(),
      Uri(path: '/staff'),
    );

    expect(redirect, '/account-loading');
  });

  test('password recovery redirects to password update', () {
    final redirect = authRedirect(
      const AuthSessionState.passwordRecovery(email: 'person@example.com'),
      const CurrentAccountState.notProvisioned(),
      Uri(path: '/staff'),
    );

    expect(redirect, '/update-password');
  });

  test('password recovery permits password update route', () {
    final redirect = authRedirect(
      const AuthSessionState.passwordRecovery(email: 'person@example.com'),
      const CurrentAccountState.notProvisioned(),
      Uri(path: '/update-password'),
    );

    expect(redirect, isNull);
  });

  test('inactive account route does not loop for deactivated account', () {
    final redirect = authRedirect(
      const AuthSessionState.authenticated(email: 'person@example.com'),
      const CurrentAccountState.deactivated(),
      Uri(path: '/inactive-account'),
    );

    expect(redirect, isNull);
  });

  test('staff access uses trusted current-account state', () {
    final redirect = authRedirect(
      const AuthSessionState.authenticated(email: 'person@example.com'),
      CurrentAccountState.loaded(staffAccount()),
      Uri(path: '/client'),
    );

    expect(redirect, '/staff');
  });

  test('client access uses trusted current-account state', () {
    final redirect = authRedirect(
      const AuthSessionState.authenticated(email: 'person@example.com'),
      CurrentAccountState.loaded(clientAccount()),
      Uri(path: '/staff'),
    );

    expect(redirect, '/client');
  });

  test('root waits during auth initialization', () {
    expect(
      rootRedirect(
        const AuthSessionState.initializing(),
        const CurrentAccountState.initializing(),
      ),
      isNull,
    );
  });
}

CurrentAccount staffAccount() {
  return const CurrentAccount(
    applicationUserId: '10000000-0000-0000-0000-000000000201',
    accountStatus: AccountStatus.active,
    isActive: true,
    accessAllowed: true,
    userType: AccountUserType.staff,
    fullName: 'Staff Person',
    jobTitle: 'Project Manager',
    activeRoleCodes: ['owner_admin'],
  );
}

CurrentAccount clientAccount() {
  return const CurrentAccount(
    applicationUserId: '10000000-0000-0000-0000-000000000202',
    accountStatus: AccountStatus.active,
    isActive: true,
    accessAllowed: true,
    userType: AccountUserType.client,
    fullName: 'Client Person',
    jobTitle: null,
    activeRoleCodes: ['client'],
  );
}
