import 'dart:async';

import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_models.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_providers.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_repository.dart';
import 'package:contractor_project_management/src/routing/app_router.dart';
import 'package:contractor_project_management/src/screens/financial_accounts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owner admin route is allowed and client/deferred staff are denied', () {
    const session = AuthSessionState.authenticated(authUserId: 'auth-1');
    expect(
      authRedirect(
        session,
        loadedAccount(staffAccount()),
        Uri.parse('/staff/financial-accounts'),
      ),
      isNull,
    );
    expect(
      authRedirect(
        session,
        loadedAccount(clientAccount()),
        Uri.parse('/staff/financial-accounts'),
      ),
      '/client',
    );
    expect(
      authRedirect(
        session,
        const CurrentAccountState.noActiveRole(),
        Uri.parse('/staff/financial-accounts'),
      ),
      '/inactive-account',
    );
  });

  testWidgets(
    'list renders separate currencies safe CASH and BANK metadata on mobile and laptop',
    (tester) async {
      final repository = FakeFinancialAccountRepository();
      await tester.binding.setSurfaceSize(const Size(390, 800));
      await tester.pumpWidget(listScreen(repository));
      await tester.pumpAndSettle();

      expect(find.text('Cash & Bank Accounts'), findsOneWidget);
      expect(find.text('USD 125.00'), findsWidgets);
      expect(find.text('SAR 88.50'), findsWidgets);
      expect(find.textContaining('grand'), findsNothing);
      expect(find.textContaining('total balance'), findsNothing);
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cash Drawer'), findsOneWidget);
      expect(find.textContaining('Cash - USD - Active'), findsOneWidget);
      expect(find.textContaining('****1111'), findsNothing);
      expect(find.textContaining('Operating Bank'), findsOneWidget);
      expect(find.textContaining('Safe Bank'), findsOneWidget);
      expect(find.textContaining('****2222'), findsOneWidget);
      expect(find.textContaining('encrypted'), findsNothing);

      await tester.binding.setSurfaceSize(const Size(1000, 800));
      await tester.pumpWidget(listScreen(repository));
      await tester.pumpAndSettle();
      expect(find.text('Cash total'), findsOneWidget);
      expect(find.text('Bank total'), findsOneWidget);
    },
  );

  testWidgets(
    'detail renders safe fields, no delete, no encrypted field, and lifecycle actions',
    (tester) async {
      final repository = FakeFinancialAccountRepository();
      await tester.pumpWidget(detailScreen(repository));
      await tester.pumpAndSettle();

      expect(find.text('Operating Bank'), findsWidgets);
      expect(find.text('FA-000002'), findsOneWidget);
      expect(find.text('USD 1250.75'), findsOneWidget);
      expect(find.text('****2222'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(find.textContaining('encrypted'), findsNothing);

      await tester.tap(find.widgetWithText(ActionChip, 'Deactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
      await tester.pumpAndSettle();
      expect(repository.lifecycleActions, contains('deactivate:bank-1:3'));

      await tester.tap(find.widgetWithText(ActionChip, 'Activate'));
      await tester.pumpAndSettle();
      expect(repository.lifecycleActions, contains('activate:bank-1:4'));

      await tester.tap(find.widgetWithText(ActionChip, 'Archive'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not deletion'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();
      expect(repository.lifecycleActions, contains('archive:bank-1:5'));
    },
  );

  testWidgets('create CASH and BANK use safe fields and no balance input', (
    tester,
  ) async {
    final repository = FakeFinancialAccountRepository();
    await tester.pumpWidget(listScreen(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Balance'), findsNothing);
    expect(find.textContaining('encrypted'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Account name'),
      'Petty Cash',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Currency code'),
      'yer',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repository.created.single.type, FinancialAccountType.cash);
    expect(repository.created.single.currencyCode, 'YER');
    expect(repository.created.single.maskedAccountIdentifier, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Account name'),
      'Reserve Bank',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Currency code'),
      'usd',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Bank name'),
      'Safe Reserve',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Masked account identifier'),
      '****9090',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repository.created.last.type, FinancialAccountType.bank);
    expect(repository.created.last.bankName, 'Safe Reserve');
    expect(repository.created.last.maskedAccountIdentifier, '****9090');
  });

  testWidgets(
    'edit safe metadata goes through update with optimistic version',
    (tester) async {
      final repository = FakeFinancialAccountRepository();
      await tester.pumpWidget(detailScreen(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ActionChip, 'Edit'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Balance'), findsNothing);
      expect(find.textContaining('encrypted'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Account name'),
        'Operating Bank Updated',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Notes'),
        'safe updated note',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repository.updated.single.accountId, 'bank-1');
      expect(repository.updated.single.expectedVersionNumber, 3);
      expect(repository.updated.single.draft.name, 'Operating Bank Updated');
      expect(repository.updated.single.draft.notes, 'safe updated note');
    },
  );

  testWidgets('stale authenticated session response is suppressed', (
    tester,
  ) async {
    final repository = FakeFinancialAccountRepository(delayList: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financialAccountRepositoryProvider.overrideWithValue(repository),
          ownerFinancialAccountAccessProvider.overrideWithValue(true),
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.authenticated(authUserId: 'auth-1'),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FinancialAccountsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financialAccountRepositoryProvider.overrideWithValue(repository),
          ownerFinancialAccountAccessProvider.overrideWithValue(false),
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.unauthenticated(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FinancialAccountsScreen()),
        ),
      ),
    );
    repository.completeDelayedList();
    await tester.pumpAndSettle();

    expect(find.text('Cash Drawer'), findsNothing);
    expect(find.text('No financial accounts found.'), findsOneWidget);
  });
}

Widget listScreen(FakeFinancialAccountRepository repository) {
  return ProviderScope(
    overrides: [
      financialAccountRepositoryProvider.overrideWithValue(repository),
      ownerFinancialAccountAccessProvider.overrideWithValue(true),
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'auth-1'),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: FinancialAccountsScreen())),
  );
}

Widget detailScreen(FakeFinancialAccountRepository repository) {
  return ProviderScope(
    overrides: [
      financialAccountRepositoryProvider.overrideWithValue(repository),
      ownerFinancialAccountAccessProvider.overrideWithValue(true),
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'auth-1'),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: FinancialAccountDetailScreen(accountId: 'bank-1')),
    ),
  );
}

CurrentAccountState loadedAccount(CurrentAccount account) =>
    CurrentAccountState.loaded(account);

CurrentAccount staffAccount() => const CurrentAccount(
  applicationUserId: 'staff-user',
  accountStatus: AccountStatus.active,
  isActive: true,
  accessAllowed: true,
  userType: AccountUserType.staff,
  fullName: 'Owner Admin',
  jobTitle: 'Owner',
  activeRoleCodes: ['owner_admin'],
);

CurrentAccount clientAccount() => const CurrentAccount(
  applicationUserId: 'client-user',
  accountStatus: AccountStatus.active,
  isActive: true,
  accessAllowed: true,
  userType: AccountUserType.client,
  fullName: 'Client',
  jobTitle: null,
  activeRoleCodes: ['client'],
);

class FakeFinancialAccountRepository implements FinancialAccountRepository {
  FakeFinancialAccountRepository({this.delayList = false});

  final bool delayList;
  Completer<List<FinancialAccount>>? _listCompleter;
  final created = <FinancialAccountDraft>[];
  final updated = <UpdateCall>[];
  final lifecycleActions = <String>[];
  var _bankActive = true;
  var _bankArchived = false;
  var _bankVersion = 3;
  var _nextId = 10;

  @override
  Future<List<FinancialAccount>> listAccounts() {
    if (delayList) {
      _listCompleter = Completer<List<FinancialAccount>>();
      return _listCompleter!.future;
    }
    return Future.value(accounts);
  }

  void completeDelayedList() {
    _listCompleter?.complete(accounts);
  }

  @override
  Future<FinancialAccount> detail(String accountId) async {
    return accounts.firstWhere((account) => account.id == accountId);
  }

  @override
  Future<ExactMoney> balance(String accountId) async {
    final account = accounts.firstWhere((item) => item.id == accountId);
    return account.balance!;
  }

  @override
  Future<List<ExactMoney>> cashTotalsByCurrency() async => const [
    ExactMoney(currencyCode: 'USD', amount: '125.00'),
    ExactMoney(currencyCode: 'YER', amount: '3000.00'),
  ];

  @override
  Future<List<ExactMoney>> bankTotalsByCurrency() async => const [
    ExactMoney(currencyCode: 'SAR', amount: '88.50'),
    ExactMoney(currencyCode: 'USD', amount: '1250.75'),
  ];

  @override
  Future<FinancialAccountMutationResult> create(
    FinancialAccountDraft draft,
  ) async {
    created.add(draft);
    _nextId++;
    return FinancialAccountMutationResult(
      financialAccountId: 'created-$_nextId',
      versionNumber: 1,
    );
  }

  @override
  Future<FinancialAccountMutationResult> update({
    required String accountId,
    required int expectedVersionNumber,
    required FinancialAccountDraft draft,
  }) async {
    updated.add(UpdateCall(accountId, expectedVersionNumber, draft));
    _bankVersion++;
    return FinancialAccountMutationResult(
      financialAccountId: accountId,
      versionNumber: _bankVersion,
    );
  }

  @override
  Future<FinancialAccountMutationResult> activate(
    String accountId,
    int expectedVersionNumber,
  ) async {
    lifecycleActions.add('activate:$accountId:$expectedVersionNumber');
    _bankActive = true;
    _bankVersion++;
    return FinancialAccountMutationResult(
      financialAccountId: accountId,
      versionNumber: _bankVersion,
    );
  }

  @override
  Future<FinancialAccountMutationResult> deactivate(
    String accountId,
    int expectedVersionNumber,
  ) async {
    lifecycleActions.add('deactivate:$accountId:$expectedVersionNumber');
    _bankActive = false;
    _bankVersion++;
    return FinancialAccountMutationResult(
      financialAccountId: accountId,
      versionNumber: _bankVersion,
    );
  }

  @override
  Future<FinancialAccountMutationResult> archive(
    String accountId,
    int expectedVersionNumber,
  ) async {
    lifecycleActions.add('archive:$accountId:$expectedVersionNumber');
    _bankActive = false;
    _bankArchived = true;
    _bankVersion++;
    return FinancialAccountMutationResult(
      financialAccountId: accountId,
      versionNumber: _bankVersion,
    );
  }

  List<FinancialAccount> get accounts => [
    const FinancialAccount(
      id: 'cash-1',
      accountNumber: 'FA-000001',
      name: 'Cash Drawer',
      type: FinancialAccountType.cash,
      currencyCode: 'USD',
      isActive: true,
      versionNumber: 1,
      balance: ExactMoney(currencyCode: 'USD', amount: '125.00'),
    ),
    FinancialAccount(
      id: 'bank-1',
      accountNumber: 'FA-000002',
      name: 'Operating Bank',
      type: FinancialAccountType.bank,
      currencyCode: 'USD',
      bankName: 'Safe Bank',
      maskedAccountIdentifier: '****2222',
      isActive: _bankActive,
      archivedAt: _bankArchived ? '2026-08-15T00:00:00Z' : null,
      versionNumber: _bankVersion,
      notes: 'safe note',
      balance: const ExactMoney(currencyCode: 'USD', amount: '1250.75'),
    ),
    const FinancialAccount(
      id: 'sar-bank',
      accountNumber: 'FA-000003',
      name: 'SAR Bank',
      type: FinancialAccountType.bank,
      currencyCode: 'SAR',
      bankName: 'Riyadh Safe',
      maskedAccountIdentifier: '****3333',
      isActive: true,
      versionNumber: 1,
      balance: ExactMoney(currencyCode: 'SAR', amount: '88.50'),
    ),
  ];
}

class UpdateCall {
  const UpdateCall(this.accountId, this.expectedVersionNumber, this.draft);

  final String accountId;
  final int expectedVersionNumber;
  final FinancialAccountDraft draft;
}
