import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/screens/protected_shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('protected routes have stable meaningful Back fallbacks', () {
    expect(protectedBackDestination(Uri.parse('/staff')), isNull);
    expect(protectedBackDestination(Uri.parse('/client')), isNull);
    expect(
      protectedBackDestination(Uri.parse('/staff/project-expenses/event-1')),
      '/staff/project-expenses',
    );
    expect(
      protectedBackDestination(Uri.parse('/staff/clients/client-1/edit')),
      '/staff/clients/client-1',
    );
    expect(
      protectedBackDestination(
        Uri.parse('/staff/projects/new?clientId=client-1'),
      ),
      '/staff/clients/client-1',
    );
    expect(
      protectedBackDestination(Uri.parse('/client/payments/payment-1')),
      '/client/payments',
    );
  });

  testWidgets('subordinate shell page exposes Back navigation', (tester) async {
    await tester.pumpWidget(
      shellAt(Uri.parse('/staff/project-expenses/event-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('Expense detail'), findsOneWidget);
  });

  testWidgets('root staff workspace has no meaningless Back control', (
    tester,
  ) async {
    await tester.pumpWidget(shellAt(Uri.parse('/staff')));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Staff workspace'), findsOneWidget);
  });
}

Widget shellAt(Uri location) => ProviderScope(
  overrides: [
    initialAuthSessionProvider.overrideWithValue(
      const AuthSessionState.authenticated(
        authUserId: 'owner-1',
        email: 'owner@example.com',
      ),
    ),
    currentAccountRepositoryProvider.overrideWithValue(
      CurrentAccountRepository(rpc: (_) async => [staffAccountRow()]),
    ),
  ],
  child: MaterialApp(
    home: ProtectedShellScreen(
      location: location,
      child: Text(
        location.path == '/staff' ? 'Staff workspace' : 'Expense detail',
      ),
    ),
  ),
);

Map<String, dynamic> staffAccountRow() => {
  'application_user_id': 'user-1',
  'account_status': 'ACTIVE',
  'is_active': true,
  'access_allowed': true,
  'user_type': 'STAFF',
  'full_name': 'Owner Person',
  'job_title': 'Owner',
  'active_role_codes': ['owner_admin'],
};
