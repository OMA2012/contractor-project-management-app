import 'dart:async';

import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/account_transfers/account_transfer_models.dart';
import 'package:contractor_project_management/src/account_transfers/account_transfer_providers.dart';
import 'package:contractor_project_management/src/account_transfers/account_transfer_repository.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_models.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_providers.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_repository.dart';
import 'package:contractor_project_management/src/routing/app_router.dart';
import 'package:contractor_project_management/src/screens/owner_account_transfers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Owner/Admin route is allowed and Client denied', () {
    const session = AuthSessionState.authenticated(authUserId: 'auth-1');
    expect(
      authRedirect(
        session,
        CurrentAccountLoaded(staffAccount()),
        Uri.parse('/staff/account-transfers'),
      ),
      isNull,
    );
    expect(
      authRedirect(
        session,
        CurrentAccountLoaded(clientAccount()),
        Uri.parse('/staff/account-transfers'),
      ),
      '/client',
    );
  });

  test(
    'repository preserves exact values and never sends Owner identity',
    () async {
      final calls = <Map<String, dynamic>>[];
      final repository = AccountTransferRepository(
        invokeFunction: (name, body) async {
          calls.add({'function': name, ...body});
          return {
            'data': {
              'account_transfer': mutationJson(),
              'account_transfers': [transferJson()],
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
      expect(calls[1]['amount'], '123.4500');
      expect(calls[1]['currency_code'], 'USD');
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

  testWidgets('list renders mobile and laptop states', (tester) async {
    final repository = FakeAccountTransferRepository();
    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pumpWidget(transferList(repository));
    expect(find.text('Loading account transfers...'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Account Transfers'), findsOneWidget);
    expect(find.textContaining('FE-000101'), findsOneWidget);
    expect(find.textContaining('USD 123.4500'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1000, 800));
    repository.items = [];
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('No account transfers found.'), findsOneWidget);
  });

  testWidgets(
    'detail supports draft workflow, projection labels, Cash/Bank display, and posted immutability',
    (tester) async {
      final repository = FakeAccountTransferRepository();
      await tester.pumpWidget(transferDetail(repository));
      await tester.pumpAndSettle();
      expect(find.text('Edit Draft'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Projected Balance Change'), findsOneWidget);
      expect(find.textContaining('Cash - USD'), findsWidgets);
      expect(
        find.textContaining('Bank - USD - Demo Bank - **1234'),
        findsWidgets,
      );
      expect(
        find.textContaining('Destination Before -> After'),
        findsOneWidget,
      );
      expect(find.textContaining('225.5500'), findsOneWidget);

      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(repository.actions, contains('submit'));

      repository.current = transfer(status: 'SUBMITTED', version: 3);
      await tester.pumpWidget(transferDetail(repository));
      await tester.pumpAndSettle();
      expect(find.textContaining('Another Owner'), findsOneWidget);
      await tester.tap(find.text('Approve & Post'));
      await tester.pumpAndSettle();
      expect(repository.actions, contains('approve'));

      repository.current = transfer(
        status: 'APPROVED',
        txStatus: 'POSTED',
        version: 4,
      );
      await tester.pumpWidget(transferDetail(repository));
      await tester.pumpAndSettle();
      expect(find.text('Edit Draft'), findsNothing);
      expect(
        find.textContaining('Posted transfers are immutable'),
        findsOneWidget,
      );
    },
  );

  test(
    'stale account/session protection does not apply stale list result',
    () async {
      final completer = Completer<List<AccountTransfer>>();
      final repository = FakeAccountTransferRepository()
        ..pendingList = completer.future;
      final container = ProviderContainer(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.authenticated(authUserId: 'auth-1'),
          ),
          currentAccountRepositoryProvider.overrideWithValue(
            CurrentAccountRepository(rpc: (_) async => [staffAccountJson()]),
          ),
          accountTransferRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      unawaited(container.read(accountTransferListProvider.notifier).load());
      await Future<void>.delayed(Duration.zero);
      container.updateOverrides([
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.unauthenticated(),
        ),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(rpc: (_) async => <Map<String, dynamic>>[]),
        ),
        accountTransferRepositoryProvider.overrideWithValue(repository),
      ]);
      completer.complete([transfer()]);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(accountTransferListProvider).value,
        isNot(contains(transfer())),
      );
    },
  );
}

Widget transferList(FakeAccountTransferRepository repository) => ProviderScope(
  overrides: [
    initialAuthSessionProvider.overrideWithValue(
      const AuthSessionState.authenticated(authUserId: 'auth-1'),
    ),
    currentAccountRepositoryProvider.overrideWithValue(
      CurrentAccountRepository(rpc: (_) async => [staffAccountJson()]),
    ),
    ownerAccountTransferAccessProvider.overrideWithValue(true),
    accountTransferRepositoryProvider.overrideWithValue(repository),
    financialAccountRepositoryProvider.overrideWithValue(
      FakeFinancialAccounts(),
    ),
  ],
  child: const MaterialApp(home: Scaffold(body: OwnerAccountTransfersScreen())),
);

Widget transferDetail(FakeAccountTransferRepository repository) =>
    ProviderScope(
      overrides: [
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.authenticated(authUserId: 'auth-1'),
        ),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(rpc: (_) async => [staffAccountJson()]),
        ),
        ownerAccountTransferAccessProvider.overrideWithValue(true),
        accountTransferRepositoryProvider.overrideWithValue(repository),
        financialAccountRepositoryProvider.overrideWithValue(
          FakeFinancialAccounts(),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: OwnerAccountTransferDetailScreen(financialEventId: 'event-1'),
        ),
      ),
    );

AccountTransferDraft draft() => const AccountTransferDraft(
  sourceAccountId: 'cash-1',
  destinationAccountId: 'bank-1',
  amount: '123.4500',
  currencyCode: 'USD',
  transferDate: '2026-08-15',
  reference: 'owner-ref',
  notes: 'private',
);

AccountTransfer transfer({
  String status = 'DRAFT',
  String txStatus = 'DRAFT',
  int version = 2,
}) => AccountTransfer.fromJson({
  ...transferJson(),
  'event_status': status,
  'transaction_status': txStatus,
  'version_number': version,
});

Map<String, dynamic> transferJson() => {
  'account_transfer_id': 'transfer-1',
  'financial_event_id': 'event-1',
  'event_number': 'FE-000101',
  'financial_transaction_id': 'tx-1',
  'transaction_number': 'FT-000101',
  'source_account_id': 'cash-1',
  'destination_account_id': 'bank-1',
  'amount': '123.4500',
  'currency_code': 'USD',
  'transfer_date': '2026-08-15',
  'reference': 'owner-ref',
  'notes': 'private',
  'reporting_currency_code': 'USD',
  'event_status': 'DRAFT',
  'transaction_status': 'DRAFT',
  'version_number': 2,
};

Map<String, dynamic> mutationJson() => {
  'financial_event_id': 'event-1',
  'version_number': 2,
};

class FakeAccountTransferRepository extends AccountTransferRepository {
  List<AccountTransfer> items = [transfer()];
  AccountTransfer current = transfer();
  Future<List<AccountTransfer>>? pendingList;
  final actions = <String>[];

  @override
  Future<List<AccountTransfer>> list() async => pendingList ?? items;
  @override
  Future<AccountTransfer> detail(String financialEventId) async => current;
  @override
  Future<AccountTransferMutationResult> create(
    AccountTransferDraft draft,
  ) async => const AccountTransferMutationResult(
    financialEventId: 'event-1',
    versionNumber: 1,
  );
  @override
  Future<AccountTransferMutationResult> update({
    required String financialEventId,
    required int expectedVersionNumber,
    required AccountTransferDraft draft,
  }) async => const AccountTransferMutationResult(
    financialEventId: 'event-1',
    versionNumber: 3,
  );
  @override
  Future<AccountTransferMutationResult> submit(String id, int version) async {
    actions.add('submit');
    current = transfer(status: 'SUBMITTED', version: 3);
    return const AccountTransferMutationResult(
      financialEventId: 'event-1',
      versionNumber: 3,
    );
  }

  @override
  Future<AccountTransferMutationResult> approve(String id, int version) async {
    actions.add('approve');
    current = transfer(status: 'APPROVED', txStatus: 'POSTED', version: 4);
    return const AccountTransferMutationResult(
      financialEventId: 'event-1',
      versionNumber: 4,
    );
  }

  @override
  Future<AccountTransferMutationResult> reject(
    String id,
    int version,
    String reason,
  ) async {
    actions.add('reject:$reason');
    current = transfer(status: 'REJECTED', txStatus: 'REJECTED', version: 4);
    return const AccountTransferMutationResult(
      financialEventId: 'event-1',
      versionNumber: 4,
    );
  }
}

class FakeFinancialAccounts implements FinancialAccountRepository {
  @override
  Future<List<FinancialAccount>> listAccounts() async => [
    const FinancialAccount(
      id: 'cash-1',
      accountNumber: 'FA-1',
      name: 'Main Cash',
      type: FinancialAccountType.cash,
      currencyCode: 'USD',
      isActive: true,
      versionNumber: 1,
      balance: ExactMoney(currencyCode: 'USD', amount: '200.0000'),
    ),
    const FinancialAccount(
      id: 'bank-1',
      accountNumber: 'FA-2',
      name: 'Operating',
      type: FinancialAccountType.bank,
      currencyCode: 'USD',
      bankName: 'Demo Bank',
      maskedAccountIdentifier: '**1234',
      isActive: true,
      versionNumber: 1,
      balance: ExactMoney(currencyCode: 'USD', amount: '102.1000'),
    ),
  ];
  @override
  Future<List<ExactMoney>> bankTotalsByCurrency() async => const [];
  @override
  Future<ExactMoney> balance(String accountId) async =>
      const ExactMoney(currencyCode: 'USD', amount: '0');
  @override
  Future<List<ExactMoney>> cashTotalsByCurrency() async => const [];
  @override
  Future<FinancialAccount> detail(String accountId) async =>
      (await listAccounts()).firstWhere((a) => a.id == accountId);
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
  Future<FinancialAccountMutationResult> update({
    required String accountId,
    required int expectedVersionNumber,
    required FinancialAccountDraft draft,
  }) => throw UnimplementedError();
}

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
