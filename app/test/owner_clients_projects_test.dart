import 'dart:async';

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

  testWidgets(
    'project save prevents duplicate submit, shows progress, and confirms success',
    (tester) async {
      final save = Completer<dynamic>();
      var saveCalls = 0;
      final repository = OwnerClientsProjectsRepository(
        invokeFunction: (_, body) async {
          if (body['action'] == 'client_list') {
            return envelope({
              'clients': [clientRow()],
            });
          }
          if (body['action'] == 'project_create') {
            saveCalls++;
            return save.future;
          }
          return envelope({});
        },
      );
      final router = GoRouter(
        initialLocation: '/staff/projects/new',
        routes: [
          GoRoute(
            path: '/staff/projects/new',
            builder: (_, _) => const OwnerProjectFormScreen(),
          ),
          GoRoute(
            path: '/staff/projects/:projectId',
            builder: (_, _) => const Scaffold(body: Text('Project detail')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ownerClientProjectAccessProvider.overrideWithValue(true),
            ownerClientsProjectsRepositoryProvider.overrideWithValue(
              repository,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CL-000001 - Acme Client').last);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Project name'),
        'School Build',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(saveCalls, 1);
      expect(find.widgetWithText(FilledButton, 'Saving'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving'))
            .onPressed,
        isNull,
      );

      save.complete(
        envelope({'project': projectRow(reportingCurrencyCode: 'USD')}),
      );
      await tester.pumpAndSettle();
      expect(saveCalls, 1);
      expect(find.text('Project detail'), findsOneWidget);
      expect(find.text('Project created successfully.'), findsOneWidget);
    },
  );

  testWidgets('failed save shows a safe understandable error', (tester) async {
    final repository = OwnerClientsProjectsRepository(
      invokeFunction: (_, _) async => throw StateError(
        'SQL rpc failure for 123e4567-e89b-12d3-a456-426614174000',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ownerClientProjectAccessProvider.overrideWithValue(true),
          ownerClientsProjectsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: OwnerClientFormScreen()),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Client name'),
      'Acme Client',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Client could not be saved. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('SQL'), findsNothing);
    expect(find.textContaining('123e4567'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
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
