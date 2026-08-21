import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('real sign-in action receives entered email and password', () async {
    final actions = FakeAuthActions();
    final container = ProviderContainer(
      overrides: [
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.unauthenticated(),
        ),
        authActionsProvider.overrideWithValue(actions),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(authSessionProvider.notifier)
        .signIn(' person@example.test ', 'correct-password');

    expect(actions.signInEmail, 'person@example.test');
    expect(actions.signInPassword, 'correct-password');
    expect(container.read(authSessionProvider).authUserId, actions.userId);
  });

  testWidgets('authentication failure surfaces only a safe error', (
    tester,
  ) async {
    final actions = FakeAuthActions(signInError: StateError('raw auth detail'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.unauthenticated(),
          ),
          authActionsProvider.overrideWithValue(actions),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'person@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'wrong-password',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      find.text('Sign in failed. Check your credentials.'),
      findsOneWidget,
    );
    expect(find.textContaining('raw auth detail'), findsNothing);
  });

  test('password reset uses approved recovery redirect', () async {
    final actions = FakeAuthActions();
    final container = ProviderContainer(
      overrides: [
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.unauthenticated(),
        ),
        authActionsProvider.overrideWithValue(actions),
        passwordRecoveryRedirectProvider.overrideWithValue(
          'https://app.example.test/update-password',
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(authSessionProvider.notifier)
        .requestPasswordReset(' person@example.test ');

    expect(actions.resetEmail, 'person@example.test');
    expect(actions.resetRedirect, 'https://app.example.test/update-password');
    expect(
      container.read(authSessionProvider).status,
      AuthSessionStatus.unauthenticated,
    );
  });

  test(
    'password update reaches Auth and returns to signed-out state',
    () async {
      final actions = FakeAuthActions();
      final container = ProviderContainer(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.passwordRecovery(
              email: 'person@example.test',
            ),
          ),
          authActionsProvider.overrideWithValue(actions),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(authSessionProvider.notifier)
          .updatePassword('new-secure-password');

      expect(actions.calls, ['update:new-secure-password', 'signOut']);
      expect(
        container.read(authSessionProvider).status,
        AuthSessionStatus.unauthenticated,
      );
    },
  );

  test('sign-out calls Auth and clears protected account state', () async {
    final actions = FakeAuthActions();
    final container = ProviderContainer(
      overrides: [
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.authenticated(
            authUserId: '00000000-0000-4000-8000-000000000001',
            email: 'owner@example.test',
          ),
        ),
        authActionsProvider.overrideWithValue(actions),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(rpc: (_) async => activeOwnerRow()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      currentAccountProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await pumpProvider();
    expect(container.read(currentAccountProvider), isA<CurrentAccountLoaded>());

    await container.read(authSessionProvider.notifier).signOut();
    await pumpProvider();

    expect(actions.calls, ['signOut']);
    expect(
      container.read(currentAccountProvider),
      isA<CurrentAccountNotProvisioned>(),
    );
  });

  test('deferred staff roles remain denied even if access flag is true', () {
    for (final role in ['project_manager', 'accountant', 'site_supervisor']) {
      final account = CurrentAccount.fromJson({
        'application_user_id': 'user-$role',
        'account_status': 'ACTIVE',
        'is_active': true,
        'access_allowed': true,
        'user_type': 'STAFF',
        'active_role_codes': [role],
      });
      expect(account.hasStaffRole, isFalse);
    }
  });
}

class FakeAuthActions implements AuthActions {
  FakeAuthActions({this.signInError});

  final Object? signInError;
  final userId = '00000000-0000-4000-8000-000000000001';
  final calls = <String>[];
  String? signInEmail;
  String? signInPassword;
  String? resetEmail;
  String? resetRedirect;

  @override
  Future<AuthSessionSnapshot> signInWithPassword(
    String email,
    String password,
  ) async {
    signInEmail = email;
    signInPassword = password;
    if (signInError != null) throw signInError!;
    return AuthSessionSnapshot(authUserId: userId, email: email);
  }

  @override
  Future<void> resetPasswordForEmail(String email, String redirectTo) async {
    resetEmail = email;
    resetRedirect = redirectTo;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
  }

  @override
  Future<void> updatePassword(String password) async {
    calls.add('update:$password');
  }
}

List<Map<String, dynamic>> activeOwnerRow() => [
  {
    'application_user_id': '10000000-0000-4000-8000-000000000001',
    'account_status': 'ACTIVE',
    'is_active': true,
    'access_allowed': true,
    'user_type': 'STAFF',
    'full_name': 'Owner Person',
    'job_title': null,
    'active_role_codes': ['owner_admin'],
  },
];

Future<void> pumpProvider() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
