import 'dart:async';

import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_models.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_providers.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_repository.dart';
import 'package:contractor_project_management/src/opening_balances/opening_balance_models.dart';
import 'package:contractor_project_management/src/opening_balances/opening_balance_providers.dart';
import 'package:contractor_project_management/src/opening_balances/opening_balance_repository.dart';
import 'package:contractor_project_management/src/project_expenses/project_expense_models.dart';
import 'package:contractor_project_management/src/project_expenses/project_expense_providers.dart';
import 'package:contractor_project_management/src/project_expenses/project_expense_repository.dart';
import 'package:contractor_project_management/src/routing/app_router.dart';
import 'package:contractor_project_management/src/screens/opening_balances_screen.dart';
import 'package:contractor_project_management/src/screens/owner_project_expenses_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('Owner/Admin route is allowed and Client denied', () {
    const session = AuthSessionState.authenticated(authUserId: 'auth-1');
    expect(
      authRedirect(
        session,
        loadedAccount(staffAccount()),
        Uri.parse('/staff/project-expenses'),
      ),
      isNull,
    );
    expect(
      authRedirect(
        session,
        loadedAccount(clientAccount()),
        Uri.parse('/staff/project-expenses'),
      ),
      '/client',
    );
  });

  test(
    'repository preserves exact values and rejects spoof fields through gateway envelope',
    () async {
      final calls = <Map<String, dynamic>>[];
      final repository = ProjectExpenseRepository(
        invokeFunction: (name, body) async {
          calls.add({'function': name, ...body});
          return {
            'data': {
              'project_expense': mutationJson(),
              'project_expenses': [expenseJson()],
            },
          };
        },
      );
      await repository.list();
      await repository.create(draft());
      await repository.update(
        financialEventId: 'event-1',
        expectedVersionNumber: 2,
        draft: draft(),
      );
      await repository.submit('event-1', 3);
      await repository.approve('event-1', 4);
      await repository.reject('event-1', 4, 'not valid');
      expect(calls[1]['amount'], '123.45');
      expect(calls[1]['currency_code'], 'USD');
      expect(calls[1]['project_id'], 'project-1');
      expect(calls[1]['expense_category_id'], 'category-1');
      expect(calls[1].keys, isNot(contains('p_verified_owner_auth_subject')));
      expect(calls.map((c) => c['action']), [
        'list',
        'create',
        'update',
        'submit',
        'approve',
        'reject',
      ]);
    },
  );

  test('repository loads project and category selector lookups', () async {
    final calls = <Map<String, dynamic>>[];
    final repository = ProjectExpenseRepository(
      invokeFunction: (name, body) async {
        calls.add({'function': name, ...body});
        return {
          'data': {
            'expense_categories': [
              {
                'expense_category_id': 'category-1',
                'code': 'MATERIALS',
                'name': 'Materials',
              },
            ],
            'projects': [
              {
                'project_id': 'project-1',
                'client_id': 'client-1',
                'project_number': 'PRJ-1',
                'name': 'Villa',
              },
            ],
          },
        };
      },
    );
    final lookups = await repository.lookups();
    expect(calls.single['action'], 'lookup');
    expect(lookups.expenseCategories.single.name, 'Materials');
    expect(lookups.projects.single.display, 'PRJ-1 - Villa');
  });

  testWidgets('client-context expense picker isolates Client A and Client B', (
    tester,
  ) async {
    final repository = FakeProjectExpenseRepository();
    await tester.binding.setSurfaceSize(const Size(900, 900));

    await tester.pumpWidget(
      projectExpenseList(repository, clientId: 'client-a'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<ProjectOption>));
    await tester.pumpAndSettle();
    expect(find.text('PRJ-A - Client A Project'), findsWidgets);
    expect(find.text('PRJ-B - Client B Project'), findsNothing);
    expect(find.textContaining('project-a-uuid'), findsNothing);
    expect(repository.lookupClientIds.last, 'client-a');
    await tester.tap(find.text('PRJ-A - Client A Project').last);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Create project expense'))).pop();
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      projectExpenseList(repository, clientId: 'client-b'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<ProjectOption>));
    await tester.pumpAndSettle();
    expect(find.text('PRJ-B - Client B Project'), findsWidgets);
    expect(find.text('PRJ-A - Client A Project'), findsNothing);
    expect(find.textContaining('project-b-uuid'), findsNothing);
    expect(repository.lookupClientIds.last, 'client-b');
  });

  testWidgets('global expense picker retains projects across clients', (
    tester,
  ) async {
    final repository = FakeProjectExpenseRepository();
    await tester.binding.setSurfaceSize(const Size(900, 900));
    await tester.pumpWidget(projectExpenseList(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<ProjectOption>));
    await tester.pumpAndSettle();
    expect(find.text('PRJ-A - Client A Project'), findsWidgets);
    expect(find.text('PRJ-B - Client B Project'), findsWidgets);
    expect(repository.lookupClientIds.last, isNull);
  });

  testWidgets('client expense shows an empty state and disables save', (
    tester,
  ) async {
    final repository = FakeProjectExpenseRepository()
      ..projectOptions = const [];
    await tester.binding.setSurfaceSize(const Size(900, 900));
    await tester.pumpWidget(
      projectExpenseList(repository, clientId: 'client-empty'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('No projects available for this client.'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save Draft'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets(
    'expense currency and paid-from account stay constrained, filtered, and readable',
    (tester) async {
      final repository = FakeProjectExpenseRepository();
      final accounts = FakeFinancialAccounts(
        accounts: const [
          FinancialAccount(
            id: '11111111-1111-4111-8111-111111111111',
            accountNumber: 'FA-USD',
            name: 'Site Cash',
            type: FinancialAccountType.cash,
            currencyCode: 'USD',
            isActive: true,
            versionNumber: 1,
          ),
          FinancialAccount(
            id: '22222222-2222-4222-8222-222222222222',
            accountNumber: 'FA-SAR',
            name: 'Operations',
            type: FinancialAccountType.bank,
            currencyCode: 'SAR',
            bankName: 'Safe Bank',
            maskedAccountIdentifier: '****4321',
            isActive: true,
            versionNumber: 1,
          ),
          FinancialAccount(
            id: '33333333-3333-4333-8333-333333333333',
            accountNumber: 'FA-INACTIVE',
            name: 'Old Cash',
            type: FinancialAccountType.cash,
            currencyCode: 'SAR',
            isActive: false,
            versionNumber: 1,
          ),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      await tester.pumpWidget(
        projectExpenseList(repository, accountsRepository: accounts),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('expense-project-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PRJ-1 - Villa').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expense-category-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Materials').last);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '10.00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Supplies',
      );

      expect(find.widgetWithText(TextFormField, 'Currency'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('expense-currency-dropdown')));
      await tester.pumpAndSettle();
      expect(find.text('USD'), findsWidgets);
      expect(find.text('SAR'), findsOneWidget);
      expect(find.text('YER'), findsOneWidget);
      expect(find.text('EUR'), findsNothing);
      await tester.tap(find.text('USD').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('paid-from-USD')));
      await tester.pumpAndSettle();
      expect(find.text('Site Cash · Cash · USD'), findsOneWidget);
      expect(find.textContaining('11111111-1111'), findsNothing);
      expect(
        find.text('Operations · Bank · SAR · Safe Bank · ****4321'),
        findsNothing,
      );
      await tester.tap(find.text('Site Cash · Cash · USD'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('expense-currency-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SAR').last);
      await tester.pumpAndSettle();
      expect(find.text('Site Cash · Cash · USD'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('paid-from-SAR')));
      await tester.pumpAndSettle();
      expect(
        find.text('Operations · Bank · SAR · Safe Bank · ****4321'),
        findsOneWidget,
      );
      expect(find.textContaining('22222222-2222'), findsNothing);
      expect(find.textContaining('Old Cash'), findsNothing);
      await tester.tap(
        find.text('Operations · Bank · SAR · Safe Bank · ****4321'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('expense-currency-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('YER').last);
      await tester.pumpAndSettle();
      expect(find.text('No active YER accounts available.'), findsOneWidget);
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save Draft'),
      );
      expect(save.onPressed, isNull);
    },
  );

  testWidgets('list renders loading empty error mobile and laptop states', (
    tester,
  ) async {
    final repository = FakeProjectExpenseRepository();
    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pumpWidget(projectExpenseList(repository));
    expect(find.text('Loading project expenses...'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Project Expenses'), findsOneWidget);
    expect(find.textContaining('FE-000101'), findsOneWidget);
    expect(find.textContaining('USD 123.45'), findsOneWidget);
    expect(find.textContaining('PRJ-1 - Villa'), findsOneWidget);
    expect(find.textContaining('project-1'), findsNothing);

    await tester.binding.setSurfaceSize(const Size(1000, 800));
    repository.items = [];
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('No project expenses found.'), findsOneWidget);

    repository.failure = true;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Project expenses could not be loaded.'), findsOneWidget);
  });

  testWidgets(
    'detail supports edit draft submit approval rejection and posted immutable/no delete',
    (tester) async {
      final repository = FakeProjectExpenseRepository();
      await tester.pumpWidget(projectExpenseDetail(repository));
      await tester.pumpAndSettle();
      expect(find.text('Edit Draft'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('USD 123.45'), findsOneWidget);
      expect(find.text('PRJ-1 - Villa'), findsOneWidget);
      expect(find.text('CL-000001 - Acme Client'), findsOneWidget);
      expect(find.textContaining('project-1'), findsNothing);

      await tester.tap(find.text('Edit Draft'));
      await tester.pumpAndSettle();
      expect(find.text('Project'), findsWidgets);
      expect(find.text('PRJ-1 - Villa'), findsWidgets);
      expect(find.text('Expense category'), findsOneWidget);
      expect(find.text('Materials'), findsOneWidget);
      expect(find.text('Paid from account'), findsWidgets);
      expect(find.widgetWithText(TextFormField, 'Amount'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(repository.actions, contains('submit'));
      repository.current = expense(status: 'SUBMITTED', version: 3);
      await tester.pumpWidget(projectExpenseDetail(repository));
      await tester.pumpAndSettle();
      expect(find.textContaining('Another Owner'), findsOneWidget);
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'not valid',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();
      expect(repository.actions, contains('reject:not valid'));

      expect(find.text('Delete'), findsNothing);
    },
  );

  testWidgets('posted expense is immutable and has no delete action', (
    tester,
  ) async {
    final repository = FakeProjectExpenseRepository()
      ..current = expense(status: 'APPROVED', txStatus: 'POSTED', version: 4);
    await tester.pumpWidget(projectExpenseDetail(repository));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Posted expenses are immutable and balances derive from posted ledger entries.',
      ),
      findsOneWidget,
    );
    expect(find.text('Edit Draft'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('missing Project Expense metadata uses unavailable labels', (
    tester,
  ) async {
    final repository = FakeProjectExpenseRepository()
      ..current = expense(metadata: false);
    await tester.pumpWidget(projectExpenseDetail(repository));
    await tester.pumpAndSettle();
    expect(find.text('Project unavailable'), findsOneWidget);
    expect(find.text('Client unavailable'), findsOneWidget);
    expect(find.textContaining('project-1'), findsNothing);
  });

  testWidgets('eligible second Owner approval posts from submitted detail', (
    tester,
  ) async {
    final repository = FakeProjectExpenseRepository()
      ..current = expense(status: 'SUBMITTED', version: 3);
    await tester.pumpWidget(projectExpenseDetail(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve & Post'));
    await tester.pumpAndSettle();
    expect(repository.actions, contains('approve'));
    expect(find.text('Approved and posted.'), findsOneWidget);
  });

  testWidgets('creator cannot approve failure stays safe', (tester) async {
    final repository = FakeProjectExpenseRepository()
      ..selfApprovalFails = true
      ..current = expense(status: 'SUBMITTED', version: 3);
    await tester.pumpWidget(projectExpenseDetail(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve & Post'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No financial data was changed'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Financial Approval Queue navigates all known types and unknown type safely',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/staff/financial-approval-queue',
        routes: [
          GoRoute(
            path: '/staff/financial-approval-queue',
            builder: (_, _) =>
                const Scaffold(body: FinancialApprovalQueueScreen()),
          ),
          GoRoute(
            path: '/staff/opening-balances/:id',
            builder: (_, _) => const Scaffold(body: Text('opening target')),
          ),
          GoRoute(
            path: '/staff/client-payments/:id',
            builder: (_, _) => const Scaffold(body: Text('payment target')),
          ),
          GoRoute(
            path: '/staff/project-expenses/:id',
            builder: (_, _) => const Scaffold(body: Text('expense target')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAuthSessionProvider.overrideWithValue(
              const AuthSessionState.authenticated(authUserId: 'auth-1'),
            ),
            currentAccountRepositoryProvider.overrideWithValue(
              CurrentAccountRepository(rpc: (_) async => [staffAccountJson()]),
            ),
            ownerOpeningBalanceAccessProvider.overrideWithValue(true),
            openingBalanceRepositoryProvider.overrideWithValue(
              FakeOpeningBalanceRepository(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(queueTile('OPENING_BALANCE'));
      await tester.pumpAndSettle();
      expect(find.text('opening target'), findsOneWidget);
      router.go('/staff/financial-approval-queue');
      await tester.pumpAndSettle();
      await tester.tap(queueTile('CLIENT_PAYMENT'));
      await tester.pumpAndSettle();
      expect(find.text('payment target'), findsOneWidget);
      router.go('/staff/financial-approval-queue');
      await tester.pumpAndSettle();
      await tester.tap(queueTile('PROJECT_EXPENSE'));
      await tester.pumpAndSettle();
      expect(find.text('expense target'), findsOneWidget);
      router.go('/staff/financial-approval-queue');
      await tester.pumpAndSettle();
      await tester.tap(queueTile('UNKNOWN_EVENT'));
      await tester.pumpAndSettle();
      expect(find.text('Financial Approval Queue'), findsOneWidget);
    },
  );

  test(
    'stale account/session protection does not apply stale list result',
    () async {
      final completer = Completer<List<ProjectExpense>>();
      final repository = FakeProjectExpenseRepository()
        ..pendingList = completer.future;
      final container = ProviderContainer(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.authenticated(authUserId: 'auth-1'),
          ),
          currentAccountRepositoryProvider.overrideWithValue(
            CurrentAccountRepository(rpc: (_) async => [staffAccountJson()]),
          ),
          projectExpenseRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      unawaited(container.read(projectExpenseListProvider.notifier).load());
      await Future<void>.delayed(Duration.zero);
      container.updateOverrides([
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.unauthenticated(),
        ),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(rpc: (_) async => <Map<String, dynamic>>[]),
        ),
        projectExpenseRepositoryProvider.overrideWithValue(repository),
      ]);
      completer.complete([expense()]);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(projectExpenseListProvider).value,
        isNot(contains(expense())),
      );
    },
  );
}

Widget projectExpenseList(
  FakeProjectExpenseRepository repository, {
  String? clientId,
  FinancialAccountRepository? accountsRepository,
}) => ProviderScope(
  overrides: [
    initialAuthSessionProvider.overrideWithValue(
      const AuthSessionState.authenticated(authUserId: 'auth-1'),
    ),
    currentAccountRepositoryProvider.overrideWithValue(
      CurrentAccountRepository(rpc: (_) async => [staffAccountJson()]),
    ),
    ownerProjectExpenseAccessProvider.overrideWithValue(true),
    ownerFinancialAccountAccessProvider.overrideWithValue(true),
    projectExpenseRepositoryProvider.overrideWithValue(repository),
    financialAccountRepositoryProvider.overrideWithValue(
      accountsRepository ?? FakeFinancialAccounts(),
    ),
  ],
  child: MaterialApp(
    home: Scaffold(body: OwnerProjectExpensesScreen(clientId: clientId)),
  ),
);

Widget projectExpenseDetail(FakeProjectExpenseRepository repository) =>
    ProviderScope(
      overrides: [
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.authenticated(authUserId: 'auth-1'),
        ),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(rpc: (_) async => [staffAccountJson()]),
        ),
        ownerProjectExpenseAccessProvider.overrideWithValue(true),
        ownerFinancialAccountAccessProvider.overrideWithValue(true),
        projectExpenseRepositoryProvider.overrideWithValue(repository),
        financialAccountRepositoryProvider.overrideWithValue(
          FakeFinancialAccounts(),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: OwnerProjectExpenseDetailScreen(financialEventId: 'event-1'),
        ),
      ),
    );

ProjectExpenseDraft draft() => const ProjectExpenseDraft(
  projectId: 'project-1',
  expenseCategoryId: 'category-1',
  amount: '123.45',
  currencyCode: 'USD',
  paidFromAccountId: 'account-1',
  expenseDate: '2026-08-15',
  description: 'Concrete',
  vendorName: 'Vendor',
  vendorReference: 'INV-1',
  privateNotes: 'private',
);

ProjectExpense expense({
  String status = 'DRAFT',
  String txStatus = 'DRAFT',
  int version = 2,
  bool metadata = true,
}) => ProjectExpense.fromJson({
  ...expenseJson(),
  'event_status': status,
  'transaction_status': txStatus,
  'version_number': version,
  if (!metadata) ...{
    'project_number': null,
    'project_name': null,
    'client_number': null,
    'client_name': null,
  },
});

Map<String, dynamic> expenseJson() => {
  'project_expense_id': 'expense-1',
  'financial_event_id': 'event-1',
  'event_number': 'FE-000101',
  'financial_transaction_id': 'tx-1',
  'transaction_number': 'FT-000101',
  'expense_number': 'EXP-000101',
  'project_id': 'project-1',
  'project_number': 'PRJ-1',
  'project_name': 'Villa',
  'client_number': 'CL-000001',
  'client_name': 'Acme Client',
  'expense_category_id': 'category-1',
  'amount': '123.45',
  'currency_code': 'USD',
  'paid_from_account_id': 'account-1',
  'expense_date': '2026-08-15',
  'vendor_name': 'Vendor',
  'vendor_reference': 'INV-1',
  'description': 'Concrete',
  'private_notes': 'private',
  'reporting_currency_code': 'USD',
  'event_status': 'DRAFT',
  'transaction_status': 'DRAFT',
  'version_number': 2,
};

Map<String, dynamic> mutationJson() => {
  'financial_event_id': 'event-1',
  'version_number': 2,
};

class FakeProjectExpenseRepository extends ProjectExpenseRepository {
  List<ProjectExpense> items = [expense()];
  ProjectExpense current = expense();
  bool failure = false;
  bool selfApprovalFails = false;
  Future<List<ProjectExpense>>? pendingList;
  final actions = <String>[];
  final updatedAmounts = <String>[];
  final lookupClientIds = <String?>[];
  List<ProjectOption> projectOptions = const [
    ProjectOption(
      projectId: 'project-1',
      clientId: 'client-1',
      projectNumber: 'PRJ-1',
      name: 'Villa',
    ),
    ProjectOption(
      projectId: 'project-a-uuid',
      clientId: 'client-a',
      projectNumber: 'PRJ-A',
      name: 'Client A Project',
    ),
    ProjectOption(
      projectId: 'project-b-uuid',
      clientId: 'client-b',
      projectNumber: 'PRJ-B',
      name: 'Client B Project',
    ),
  ];

  @override
  Future<List<ProjectExpense>> list() async {
    if (pendingList != null) return pendingList!;
    if (failure) throw StateError('down');
    return items;
  }

  @override
  Future<ProjectExpense> detail(String financialEventId) async => current;
  @override
  Future<ProjectExpenseLookups> lookups({String? clientId}) async {
    lookupClientIds.add(clientId);
    return ProjectExpenseLookups(
      expenseCategories: const [
        ExpenseCategoryOption(
          expenseCategoryId: 'category-1',
          code: 'MATERIALS',
          name: 'Materials',
        ),
      ],
      projects: projectOptions,
    );
  }

  @override
  Future<ProjectExpenseMutationResult> create(
    ProjectExpenseDraft draft,
  ) async => const ProjectExpenseMutationResult(
    financialEventId: 'event-1',
    versionNumber: 1,
  );
  @override
  Future<ProjectExpenseMutationResult> update({
    required String financialEventId,
    required int expectedVersionNumber,
    required ProjectExpenseDraft draft,
  }) async {
    updatedAmounts.add(draft.amount);
    current = expense();
    return const ProjectExpenseMutationResult(
      financialEventId: 'event-1',
      versionNumber: 3,
    );
  }

  @override
  Future<ProjectExpenseMutationResult> submit(String id, int version) async {
    actions.add('submit');
    current = expense(status: 'SUBMITTED', version: 3);
    return const ProjectExpenseMutationResult(
      financialEventId: 'event-1',
      versionNumber: 3,
    );
  }

  @override
  Future<ProjectExpenseMutationResult> approve(String id, int version) async {
    actions.add('approve');
    if (selfApprovalFails) {
      throw const ProjectExpenseFailure('Operation is not authorized.');
    }
    current = expense(status: 'APPROVED', txStatus: 'POSTED', version: 4);
    return const ProjectExpenseMutationResult(
      financialEventId: 'event-1',
      versionNumber: 4,
    );
  }

  @override
  Future<ProjectExpenseMutationResult> reject(
    String id,
    int version,
    String reason,
  ) async {
    actions.add('reject:$reason');
    current = expense(status: 'REJECTED', txStatus: 'REJECTED', version: 4);
    return const ProjectExpenseMutationResult(
      financialEventId: 'event-1',
      versionNumber: 4,
    );
  }
}

class FakeFinancialAccounts implements FinancialAccountRepository {
  FakeFinancialAccounts({
    this.accounts = const [
      FinancialAccount(
        id: 'account-1',
        accountNumber: 'FA-1',
        name: 'Cash',
        type: FinancialAccountType.cash,
        currencyCode: 'USD',
        isActive: true,
        versionNumber: 1,
      ),
    ],
  });

  final List<FinancialAccount> accounts;

  @override
  Future<List<FinancialAccount>> listAccounts() async => accounts;
  @override
  Future<List<ExactMoney>> bankTotalsByCurrency() async => const [];
  @override
  Future<ExactMoney> balance(String accountId) async =>
      const ExactMoney(currencyCode: 'USD', amount: '0');
  @override
  Future<List<ExactMoney>> cashTotalsByCurrency() async => const [];
  @override
  Future<FinancialAccountMutationResult> activate(
    String accountId,
    int expectedVersionNumber,
  ) => throw UnimplementedError();
  @override
  Future<FinancialAccountMutationResult> archive(
    String accountId,
    int expectedVersionNumber,
  ) => throw UnimplementedError();
  @override
  Future<FinancialAccountMutationResult> create(FinancialAccountDraft draft) =>
      throw UnimplementedError();
  @override
  Future<FinancialAccountMutationResult> deactivate(
    String accountId,
    int expectedVersionNumber,
  ) => throw UnimplementedError();
  @override
  Future<FinancialAccount> detail(String accountId) async =>
      (await listAccounts()).single;
  @override
  Future<FinancialAccountMutationResult> update({
    required String accountId,
    required int expectedVersionNumber,
    required FinancialAccountDraft draft,
  }) => throw UnimplementedError();
}

class FakeOpeningBalanceRepository implements OpeningBalanceRepository {
  @override
  Future<List<FinancialApprovalQueueItem>> queue(String section) async =>
      section == 'eligible'
      ? [
          queueItem('OPENING_BALANCE'),
          queueItem('CLIENT_PAYMENT'),
          queueItem('PROJECT_EXPENSE'),
          queueItem('UNKNOWN_EVENT'),
        ]
      : [];
  @override
  Future<OpeningBalanceMutationResult> approve(String id, int version) =>
      throw UnimplementedError();
  @override
  Future<OpeningBalanceMutationResult> create(OpeningBalanceDraft draft) =>
      throw UnimplementedError();
  @override
  Future<OpeningBalance> detail(String financialEventId) =>
      throw UnimplementedError();
  @override
  Future<List<OpeningBalance>> list() => throw UnimplementedError();
  @override
  Future<OpeningBalanceMutationResult> reject(
    String id,
    int version,
    String reason,
  ) => throw UnimplementedError();
  @override
  Future<OpeningBalanceMutationResult> submit(String id, int version) =>
      throw UnimplementedError();
  @override
  Future<OpeningBalanceMutationResult> update({
    required String financialEventId,
    required int expectedVersionNumber,
    required OpeningBalanceDraft draft,
  }) => throw UnimplementedError();
}

FinancialApprovalQueueItem queueItem(String type) => FinancialApprovalQueueItem(
  financialEventId: 'event-$type',
  eventNumber: 'FE-$type',
  eventType: type,
  relatedLabel: 'Queue label',
  amount: '10.00',
  currencyCode: 'USD',
  eventDate: '2026-08-15',
  eventStatus: 'SUBMITTED',
  transactionStatus: 'SUBMITTED',
  createdByMe: false,
  eligibleForMyApproval: true,
  versionNumber: 2,
);

Finder queueTile(String type) => find
    .ancestor(
      of: find.textContaining('FE-$type'),
      matching: find.byType(ListTile),
    )
    .first;

CurrentAccountLoaded loadedAccount(CurrentAccount account) =>
    CurrentAccountLoaded(account);
CurrentAccount staffAccount() => const CurrentAccount(
  applicationUserId: 'user-1',
  accountStatus: AccountStatus.active,
  isActive: true,
  accessAllowed: true,
  userType: AccountUserType.staff,
  fullName: 'Staff Person',
  jobTitle: 'Owner',
  activeRoleCodes: ['owner_admin'],
);
CurrentAccount clientAccount() => const CurrentAccount(
  applicationUserId: 'user-2',
  accountStatus: AccountStatus.active,
  isActive: true,
  accessAllowed: true,
  userType: AccountUserType.client,
  fullName: 'Client Person',
  jobTitle: null,
  activeRoleCodes: ['client'],
);

Map<String, dynamic> staffAccountJson() => {
  'application_user_id': 'user-1',
  'account_status': 'ACTIVE',
  'is_active': true,
  'access_allowed': true,
  'user_type': 'STAFF',
  'full_name': 'Staff Person',
  'job_title': 'Owner',
  'active_role_codes': ['owner_admin'],
};
