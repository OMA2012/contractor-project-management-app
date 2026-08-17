import 'package:contractor_project_management/src/owner_clients_projects/owner_clients_projects_models.dart';
import 'package:contractor_project_management/src/owner_clients_projects/owner_clients_projects_repository.dart';
import 'package:flutter_test/flutter_test.dart';

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

Map<String, dynamic> projectRow({String status = 'APPROVED'}) => {
  'id': projectId,
  'client_id': clientId,
  'client_number': 'CL-000001',
  'client_name': 'Acme Client',
  'project_number': 'PRJ-2026-0001',
  'name': 'Villa Build',
  'status': status,
  'reporting_currency_code': 'SGD',
  'version_number': 1,
};
