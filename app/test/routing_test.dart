import 'dart:async';

import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/app.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('restores unauthenticated users to login', (tester) async {
    final source = FakeAuthSessionSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionSourceProvider.overrideWithValue(source)],
        child: const ContractorProjectManagementApp(),
      ),
    );

    expect(find.text('Account loading'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('restored authenticated users do not briefly redirect to login', (
    tester,
  ) async {
    final source = FakeAuthSessionSource(
      restoredSession: const AuthSessionSnapshot(email: 'person@example.com'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionSourceProvider.overrideWithValue(source),
          currentAccountRepositoryProvider.overrideWithValue(
            CurrentAccountRepository(
              rpc: (_) async => <Map<String, dynamic>>[],
            ),
          ),
        ],
        child: const ContractorProjectManagementApp(),
      ),
    );

    await tester.pump();

    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Account loading'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Account not provisioned'), findsOneWidget);
  });

  testWidgets('sign-out auth event returns to login', (tester) async {
    final source = FakeAuthSessionSource(
      restoredSession: const AuthSessionSnapshot(email: 'person@example.com'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionSourceProvider.overrideWithValue(source),
          currentAccountRepositoryProvider.overrideWithValue(
            CurrentAccountRepository(rpc: (_) async => activeStaffRow()),
          ),
        ],
        child: const ContractorProjectManagementApp(),
      ),
    );
    await tester.pumpAndSettle();

    source.emit(
      const AuthSessionChange(event: AuthSessionChangeEvent.signedOut),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('password-recovery auth event opens password update', (
    tester,
  ) async {
    final source = FakeAuthSessionSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionSourceProvider.overrideWithValue(source)],
        child: const ContractorProjectManagementApp(),
      ),
    );
    await tester.pumpAndSettle();

    source.emit(
      const AuthSessionChange(
        event: AuthSessionChangeEvent.passwordRecovery,
        session: AuthSessionSnapshot(email: 'person@example.com'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose a new password to continue.'), findsOneWidget);
  });

  testWidgets('trusted staff account opens staff shell only', (tester) async {
    await tester.pumpWidget(appWithTrustedAccount(activeStaffRow()));
    await tester.pumpAndSettle();

    expect(find.text('Staff workspace'), findsOneWidget);
    expect(find.text('Client workspace'), findsNothing);
  });

  testWidgets('trusted client account opens client shell only', (tester) async {
    await tester.pumpWidget(appWithTrustedAccount(activeClientRow()));
    await tester.pumpAndSettle();

    expect(find.text('Client workspace'), findsOneWidget);
    expect(find.text('Staff workspace'), findsNothing);
  });

  testWidgets('pending invite cannot enter a protected shell', (tester) async {
    await tester.pumpWidget(appWithTrustedAccount(statusRow('INVITED')));
    await tester.pumpAndSettle();

    expect(find.text('Account pending'), findsOneWidget);
  });

  testWidgets('suspended account cannot enter a protected shell', (
    tester,
  ) async {
    await tester.pumpWidget(appWithTrustedAccount(statusRow('SUSPENDED')));
    await tester.pumpAndSettle();

    expect(find.text('Account suspended'), findsOneWidget);
  });

  testWidgets('deactivated account cannot enter a protected shell', (
    tester,
  ) async {
    await tester.pumpWidget(appWithTrustedAccount(statusRow('DISABLED')));
    await tester.pumpAndSettle();

    expect(find.text('Account deactivated'), findsOneWidget);
  });

  testWidgets('active account with no role cannot enter a protected shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      appWithTrustedAccount(statusRow('ACTIVE', accessAllowed: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No active role'), findsOneWidget);
  });

  testWidgets('reserved staff roles cannot enter a protected shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      appWithTrustedAccount(
        statusRow(
          'ACTIVE',
          accessAllowed: false,
          activeRoleCodes: ['project_manager'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No active role'), findsOneWidget);
    expect(find.text('Staff workspace'), findsNothing);
    expect(find.text('Client workspace'), findsNothing);
  });

  testWidgets('rpc failure stays retryable and does not enter shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.authenticated(email: 'person@example.com'),
          ),
          currentAccountRepositoryProvider.overrideWithValue(
            CurrentAccountRepository(
              rpc: (_) async => throw StateError('down'),
            ),
          ),
        ],
        child: const ContractorProjectManagementApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account loading'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Staff workspace'), findsNothing);
  });
}

ProviderScope appWithTrustedAccount(dynamic rpcResponse) {
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(email: 'person@example.com'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        CurrentAccountRepository(rpc: (_) async => rpcResponse),
      ),
    ],
    child: const ContractorProjectManagementApp(),
  );
}

List<Map<String, dynamic>> activeStaffRow() {
  return [
    {
      'application_user_id': '10000000-0000-0000-0000-000000000201',
      'account_status': 'ACTIVE',
      'is_active': true,
      'access_allowed': true,
      'user_type': 'STAFF',
      'full_name': 'Staff Person',
      'job_title': 'Project Manager',
      'active_role_codes': ['owner_admin'],
    },
  ];
}

List<Map<String, dynamic>> activeClientRow() {
  return [
    {
      'application_user_id': '10000000-0000-0000-0000-000000000202',
      'account_status': 'ACTIVE',
      'is_active': true,
      'access_allowed': true,
      'user_type': 'CLIENT',
      'full_name': 'Client Person',
      'job_title': null,
      'active_role_codes': ['client'],
    },
  ];
}

List<Map<String, dynamic>> statusRow(
  String status, {
  bool accessAllowed = false,
  List<String> activeRoleCodes = const <String>[],
}) {
  return [
    {
      'application_user_id': '10000000-0000-0000-0000-000000000203',
      'account_status': status,
      'is_active': status == 'ACTIVE',
      'access_allowed': accessAllowed,
      'user_type': 'STAFF',
      'full_name': status == 'ACTIVE' ? 'Person' : null,
      'job_title': status == 'ACTIVE' ? 'Role' : null,
      'active_role_codes': activeRoleCodes,
    },
  ];
}

class FakeAuthSessionSource implements AuthSessionSource {
  FakeAuthSessionSource({this.restoredSession});

  final AuthSessionSnapshot? restoredSession;
  final controller = StreamController<AuthSessionChange>.broadcast();

  @override
  AuthSessionSnapshot? get currentSession => restoredSession;

  @override
  Stream<AuthSessionChange> get onAuthStateChange => controller.stream;

  void emit(AuthSessionChange change) {
    controller.add(change);
  }
}
