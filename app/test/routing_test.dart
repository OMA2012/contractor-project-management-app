import 'dart:async';

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
        overrides: [authSessionSourceProvider.overrideWithValue(source)],
        child: const ContractorProjectManagementApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Account loading'), findsOneWidget);
    expect(find.text('person@example.com'), findsOneWidget);
  });

  testWidgets('sign-out auth event returns to login', (tester) async {
    final source = FakeAuthSessionSource(
      restoredSession: const AuthSessionSnapshot(email: 'person@example.com'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionSourceProvider.overrideWithValue(source)],
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

  testWidgets('staff shell requires an injected trusted account role', (
    tester,
  ) async {
    final source = FakeAuthSessionSource(
      restoredSession: const AuthSessionSnapshot(email: 'person@example.com'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionSourceProvider.overrideWithValue(source),
          trustedAccountRoleProvider.overrideWithValue(AccountRole.staff),
        ],
        child: const ContractorProjectManagementApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Staff workspace'), findsOneWidget);
  });

  testWidgets('client shell requires an injected trusted account role', (
    tester,
  ) async {
    final source = FakeAuthSessionSource(
      restoredSession: const AuthSessionSnapshot(email: 'person@example.com'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionSourceProvider.overrideWithValue(source),
          trustedAccountRoleProvider.overrideWithValue(AccountRole.client),
        ],
        child: const ContractorProjectManagementApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Client workspace'), findsOneWidget);
  });
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
