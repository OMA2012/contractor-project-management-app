import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/owner_clients_projects/owner_clients_projects_models.dart';
import 'package:contractor_project_management/src/owner_clients_projects/owner_clients_projects_providers.dart';
import 'package:contractor_project_management/src/owner_clients_projects/owner_clients_projects_repository.dart';
import 'package:contractor_project_management/src/screens/owner_clients_projects_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test(
    'repository uses strict gateway actions and never sends actor identity',
    () async {
      final calls = <Map<String, dynamic>>[];
      final repository = OwnerClientsProjectsRepository(
        invokeFunction: (functionName, body) async {
          calls.add({'function': functionName, ...body});
          return switch (body['action']) {
            'client_list' => envelope({
              'clients': [clientRow()],
            }),
            'project_list' => envelope({
              'projects': [projectRow()],
            }),
            'project_transition' => envelope({
              'project': projectRow(status: 'ACTIVE'),
            }),
            _ => envelope({'client': clientRow()}),
          };
        },
      );

      await repository.listClients();
      await repository.listProjects();
      await repository.transitionProject(
        projectId: projectId,
        expectedVersionNumber: 1,
        newStatus: 'ACTIVE',
      );

      expect(calls.map((call) => call['function']).toSet(), {
        'client-projects',
      });
      for (final call in calls) {
        expect(
          call.keys.any((key) => key.toString().contains('owner_auth')),
          isFalse,
        );
        expect(
          call.keys.any((key) => key.toString().contains('actor')),
          isFalse,
        );
      }
      expect(calls.last['action'], 'project_transition');
    },
  );

  test('models expose picker labels and valid lifecycle actions only', () {
    final client = OwnerClientRecord.fromJson(clientRow());
    final approved = OwnerProjectRecord.fromJson(projectRow());
    final archived = OwnerProjectRecord.fromJson(
      projectRow(status: 'ARCHIVED'),
    );

    expect(client.pickerLabel, 'CL-000001 - Acme Client');
    expect(approved.nextStatuses, ['ACTIVE', 'CANCELLED']);
    expect(archived.nextStatuses, isEmpty);
    expect(archived.canEdit, isFalse);
  });

  test('project parse requires backend-generated project number', () {
    expect(
      () => OwnerProjectRecord.fromJson(
        {...projectRow()}..remove('project_number'),
      ),
      throwsFormatException,
    );
  });

  test('project save submits the selected reporting currency code', () async {
    Map<String, dynamic>? submittedBody;
    final repository = OwnerClientsProjectsRepository(
      invokeFunction: (functionName, body) async {
        submittedBody = body;
        return envelope({'project': projectRow(reportingCurrencyCode: 'SAR')});
      },
    );

    await repository.saveProject(
      clientId: clientId,
      name: 'School Build',
      reportingCurrencyCode: 'SAR',
    );

    expect(submittedBody?['action'], 'project_create');
    expect(submittedBody?['reporting_currency_code'], 'SAR');
  });

  testWidgets('Client detail financial actions preserve immutable Client ID', (
    tester,
  ) async {
    final repository = OwnerClientsProjectsRepository(
      invokeFunction: (_, body) async => switch (body['action']) {
        'client_detail' => envelope({'client': clientRow()}),
        'client_projects' => envelope({
          'projects': [projectRow()],
        }),
        'invitation_status' => envelope({
          'invitation': {'status': 'PENDING'},
        }),
        _ => envelope({}),
      },
    );
    final router = GoRouter(
      initialLocation: '/staff/clients/$clientId',
      routes: [
        GoRoute(
          path: '/staff/clients/:clientId',
          builder: (_, state) => OwnerClientDetailScreen(
            clientId: state.pathParameters['clientId']!,
          ),
        ),
        GoRoute(
          path: '/staff/client-payments',
          builder: (_, state) => Scaffold(body: Text(state.uri.toString())),
        ),
        GoRoute(
          path: '/staff/project-expenses',
          builder: (_, state) => Scaffold(body: Text(state.uri.toString())),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.authenticated(authUserId: 'owner-1'),
          ),
          ownerClientProjectAccessProvider.overrideWithValue(true),
          ownerClientsProjectsRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create Client Payment'));
    await tester.tap(find.text('Create Client Payment'));
    await tester.pumpAndSettle();
    expect(
      find.text('/staff/client-payments?clientId=$clientId'),
      findsOneWidget,
    );

    router.go('/staff/clients/$clientId');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create Project Expense'));
    await tester.tap(find.text('Create Project Expense'));
    await tester.pumpAndSettle();
    expect(
      find.text('/staff/project-expenses?clientId=$clientId'),
      findsOneWidget,
    );
  });
}

const clientId = '10000000-0000-4000-8000-000000000001';
const projectId = '20000000-0000-4000-8000-000000000001';

Map<String, dynamic> envelope(Map<String, dynamic> data) => {
  'success': true,
  'data': data,
};

Map<String, dynamic> clientRow() => {
  'id': clientId,
  'client_number': 'CL-000001',
  'display_name': 'Acme Client',
  'email': 'client@example.com',
  'status': 'ACTIVE',
  'is_active': true,
  'portal_user_id': null,
  'version_number': 1,
  'project_count': 1,
};

Map<String, dynamic> projectRow({
  String status = 'APPROVED',
  String reportingCurrencyCode = 'SGD',
}) => {
  'id': projectId,
  'client_id': clientId,
  'client_number': 'CL-000001',
  'client_name': 'Acme Client',
  'project_number': 'PRJ-2026-0001',
  'name': 'Villa Build',
  'status': status,
  'reporting_currency_code': reportingCurrencyCode,
  'version_number': 1,
};
