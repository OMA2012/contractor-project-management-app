import 'dart:async';

import 'package:contractor_project_management/src/owner_clients_projects/owner_clients_projects_models.dart';
import 'package:contractor_project_management/src/owner_clients_projects/owner_clients_projects_providers.dart';
import 'package:contractor_project_management/src/owner_clients_projects/owner_clients_projects_repository.dart';
import 'package:contractor_project_management/src/screens/owner_clients_projects_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'reporting currency is a closed dropdown with only USD SAR and YER',
    (tester) async {
      final repository = _ProjectFormRepository();
      await tester.pumpWidget(_projectForm(repository));
      await tester.pumpAndSettle();

      final currencyDropdown = _currencyDropdown();
      expect(currencyDropdown, findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Reporting currency'),
        findsNothing,
      );
      expect(
        find.descendant(
          of: currencyDropdown,
          matching: find.byType(EditableText),
        ),
        findsNothing,
      );

      await tester.tap(currencyDropdown);
      await tester.pumpAndSettle();

      expect(find.text('USD'), findsWidgets);
      expect(find.text('SAR'), findsOneWidget);
      expect(find.text('YER'), findsOneWidget);
      expect(find.text('SGD'), findsNothing);
      expect(find.text('ABC'), findsNothing);
    },
  );

  testWidgets('contractor default currency is selected for creation', (
    tester,
  ) async {
    final repository = _ProjectFormRepository();
    await tester.pumpWidget(
      _projectForm(repository, contractorDefaultReportingCurrencyCode: 'SAR'),
    );
    await tester.pumpAndSettle();

    expect(_selectedCurrency(tester), 'SAR');
  });

  testWidgets(
    'unsupported or unavailable contractor default falls back to USD',
    (tester) async {
      final repository = _ProjectFormRepository();
      await tester.pumpWidget(
        _projectForm(repository, contractorDefaultReportingCurrencyCode: 'SGD'),
      );
      await tester.pumpAndSettle();

      expect(_selectedCurrency(tester), 'USD');
    },
  );

  testWidgets('existing project currency is selected during editing', (
    tester,
  ) async {
    final repository = _ProjectFormRepository(
      project: _project(reportingCurrencyCode: 'YER'),
    );
    await tester.pumpWidget(_projectForm(repository, projectId: projectId));
    await tester.pumpAndSettle();

    expect(_selectedCurrency(tester), 'YER');
  });

  testWidgets('selected currency code is submitted to client-projects', (
    tester,
  ) async {
    final repository = _ProjectFormRepository();
    await tester.pumpWidget(_projectForm(repository));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Project name'),
      'School Build',
    );
    await tester.tap(_currencyDropdown());
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAR').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(repository.submittedReportingCurrencyCode, 'SAR');
  });
}

Finder _currencyDropdown() => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.decoration.labelText == 'Reporting currency',
);

String? _selectedCurrency(WidgetTester tester) =>
    tester.state<FormFieldState<String>>(_currencyDropdown()).value;

Widget _projectForm(
  _ProjectFormRepository repository, {
  String? projectId,
  String? contractorDefaultReportingCurrencyCode = 'USD',
}) => ProviderScope(
  overrides: [
    ownerClientProjectAccessProvider.overrideWithValue(true),
    ownerClientsProjectsRepositoryProvider.overrideWithValue(repository),
  ],
  child: MaterialApp(
    home: OwnerProjectFormScreen(
      projectId: projectId,
      initialClientId: clientId,
      contractorDefaultReportingCurrencyCode:
          contractorDefaultReportingCurrencyCode,
    ),
  ),
);

class _ProjectFormRepository extends OwnerClientsProjectsRepository {
  _ProjectFormRepository({OwnerProjectRecord? project})
    : project = project ?? _project();

  final OwnerProjectRecord project;
  String? submittedReportingCurrencyCode;
  final _pendingSave = Completer<OwnerProjectRecord>();

  @override
  Future<List<OwnerClientRecord>> listClients() async => const [
    OwnerClientRecord(
      id: clientId,
      clientNumber: 'CL-000001',
      displayName: 'Acme Client',
      status: 'ACTIVE',
      isActive: true,
      versionNumber: 1,
    ),
  ];

  @override
  Future<OwnerProjectRecord> projectDetail(String projectId) async => project;

  @override
  Future<OwnerProjectRecord> saveProject({
    String? projectId,
    int? expectedVersionNumber,
    required String clientId,
    required String name,
    required String reportingCurrencyCode,
    String? projectType,
    String? location,
    String? clientVisibleSummary,
  }) {
    submittedReportingCurrencyCode = reportingCurrencyCode;
    return _pendingSave.future;
  }
}

OwnerProjectRecord _project({String reportingCurrencyCode = 'USD'}) =>
    OwnerProjectRecord(
      id: projectId,
      clientId: clientId,
      projectNumber: 'PRJ-2026-0001',
      name: 'Villa Build',
      status: 'DRAFT',
      reportingCurrencyCode: reportingCurrencyCode,
      versionNumber: 1,
    );

const clientId = '10000000-0000-4000-8000-000000000001';
const projectId = '20000000-0000-4000-8000-000000000001';
