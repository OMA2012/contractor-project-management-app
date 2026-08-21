import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/app.dart';
import 'package:contractor_project_management/src/auth/account_activation_repository.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('/accept-invitation invokes linked acceptance contract', (
    tester,
  ) async {
    String? functionName;
    Map<String, dynamic>? requestBody;
    final repository = AccountActivationRepository(
      invokeFunction: (name, body) async {
        functionName = name;
        requestBody = body;
        return {
          'success': true,
          'data': {
            'client_user_id': '10000000-0000-4000-8000-000000000002',
            'status': 'ACTIVE',
          },
        };
      },
    );
    await tester.pumpWidget(
      activationApp(
        location: '/accept-invitation?token=invited-client-token',
        activationRepository: repository,
        accountRows: activeClientRow(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Accept invitation'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'Invited Client');
    await tester.tap(find.widgetWithText(FilledButton, 'Accept invitation'));
    await tester.pumpAndSettle();

    expect(functionName, 'accept-client-invitation');
    expect(requestBody, {
      'token': 'invited-client-token',
      'full_name': 'Invited Client',
    });
    expect(requestBody!.containsKey('client_id'), isFalse);
    expect(find.textContaining('Client account is active'), findsOneWidget);
  });

  testWidgets('/accept-invitation handles invalid or expired invitation', (
    tester,
  ) async {
    final repository = AccountActivationRepository(
      invokeFunction: (_, _) async =>
          throw const AccountActivationFailure('backend detail'),
    );
    await tester.pumpWidget(
      activationApp(
        location: '/accept-invitation?token=expired-token',
        activationRepository: repository,
        accountRows: const [],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Invited Client');
    await tester.tap(find.widgetWithText(FilledButton, 'Accept invitation'));
    await tester.pumpAndSettle();

    expect(find.textContaining('invalid, expired'), findsOneWidget);
    expect(find.textContaining('backend detail'), findsNothing);
  });

  testWidgets('/owner/activate invokes first-Owner activation contract', (
    tester,
  ) async {
    final calls = <String>[];
    final repository = AccountActivationRepository(
      rpc: (name) async {
        calls.add(name);
        return '10000000-0000-4000-8000-000000000001';
      },
    );
    await tester.pumpWidget(
      activationApp(
        location: '/owner/activate',
        activationRepository: repository,
        accountRows: activeOwnerRow(),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, ['activate_current_invited_owner']);
    expect(find.text('Owner account activated successfully.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('/owner/activate handles invalid activation safely', (
    tester,
  ) async {
    final repository = AccountActivationRepository(rpc: (_) async => null);
    await tester.pumpWidget(
      activationApp(
        location: '/owner/activate',
        activationRepository: repository,
        accountRows: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('invalid, expired'), findsOneWidget);
  });

  testWidgets('activation routes do not create public signup entry points', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.unauthenticated(),
          ),
          routerInitialLocationProvider.overrideWithValue(
            '/accept-invitation?token=token',
          ),
        ],
        child: const ContractorProjectManagementApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('no authenticated invitation session'),
      findsOneWidget,
    );
    expect(find.textContaining('Sign up'), findsNothing);
  });
}

ProviderScope activationApp({
  required String location,
  required AccountActivationRepository activationRepository,
  required List<Map<String, dynamic>> accountRows,
}) {
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(
          authUserId: '00000000-0000-4000-8000-000000000010',
          email: 'invited@example.test',
        ),
      ),
      accountActivationRepositoryProvider.overrideWithValue(
        activationRepository,
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        CurrentAccountRepository(rpc: (_) async => accountRows),
      ),
      routerInitialLocationProvider.overrideWithValue(location),
    ],
    child: const ContractorProjectManagementApp(),
  );
}

List<Map<String, dynamic>> activeClientRow() => [
  {
    'application_user_id': '10000000-0000-4000-8000-000000000002',
    'account_status': 'ACTIVE',
    'is_active': true,
    'access_allowed': true,
    'user_type': 'CLIENT',
    'full_name': 'Invited Client',
    'job_title': null,
    'active_role_codes': ['client'],
  },
];

List<Map<String, dynamic>> activeOwnerRow() => [
  {
    'application_user_id': '10000000-0000-4000-8000-000000000001',
    'account_status': 'ACTIVE',
    'is_active': true,
    'access_allowed': true,
    'user_type': 'STAFF',
    'full_name': 'First Owner',
    'job_title': null,
    'active_role_codes': ['owner_admin'],
  },
];
