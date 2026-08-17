import 'dart:async';

import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_models.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_providers.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_repository.dart';
import 'package:contractor_project_management/src/financial_corrections/financial_correction_models.dart';
import 'package:contractor_project_management/src/financial_corrections/financial_correction_providers.dart';
import 'package:contractor_project_management/src/financial_corrections/financial_correction_repository.dart';
import 'package:contractor_project_management/src/opening_balances/opening_balance_models.dart';
import 'package:contractor_project_management/src/opening_balances/opening_balance_providers.dart';
import 'package:contractor_project_management/src/opening_balances/opening_balance_repository.dart';
import 'package:contractor_project_management/src/routing/app_router.dart';
import 'package:contractor_project_management/src/screens/financial_corrections_screen.dart';
import 'package:contractor_project_management/src/screens/opening_balances_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('Owner/Admin correction routes are allowed and Client denied', () {
    const session = AuthSessionState.authenticated(authUserId: 'auth-1');
    expect(
      authRedirect(
        session,
        CurrentAccountLoaded(staffAccount()),
        Uri.parse('/staff/financial-reversals'),
      ),
      isNull,
    );
    expect(
      authRedirect(
        session,
        CurrentAccountLoaded(staffAccount()),
        Uri.parse('/staff/financial-adjustments'),
      ),
      isNull,
    );
    expect(
      authRedirect(
        session,
        CurrentAccountLoaded(clientAccount()),
        Uri.parse('/staff/financial-reversals/bad-id'),
      ),
      '/client',
    );
  });

  test(
    'repository sends only gateway fields and exact decimal strings',
    () async {
      final calls = <Map<String, dynamic>>[];
      final repository = FinancialCorrectionRepository(
        invokeFunction: (name, body) async {
          calls.add({'function': name, ...body});
          return {
            'data': {
              'sources': [sourceJson()],
              'reversal': mutationJson(),
              'adjustment': mutationJson(),
              'reversals': [reversalJson()],
              'adjustments': [adjustmentJson()],
            },
          };
        },
      );
      await repository.eligibleSources();
      await repository.createReversal(
        const ReversalDraft(
          originalTransactionId: 'tx-original',
          reversalDate: '2026-08-17',
          reason: 'mistake',
        ),
      );
      await repository.createAdjustment(
        const AdjustmentDraft(
          financialAccountId: 'account-1',
          direction: 'INCREASE',
          amount: '12.3400',
          adjustmentDate: '2026-08-17',
          reportingCurrencyCode: 'USD',
          reason: 'delta',
          adjustedTransactionId: 'tx-original',
        ),
      );
      await repository.submitReversal('event-1', 2);
      await repository.approveAdjustment('event-2', 3);
      expect(calls[1].keys, isNot(contains('p_verified_owner_auth_subject')));
      expect(calls[2]['amount'], '12.3400');
      expect(calls.map((c) => c['action']), [
        'eligible_sources',
        'create_reversal',
        'create_adjustment',
        'submit_reversal',
        'approve_adjustment',
      ]);
    },
  );

  testWidgets(
    'reversal list renders loading, empty, error, mobile and laptop',
    (tester) async {
      final repository = FakeCorrectionsRepository();
      await tester.binding.setSurfaceSize(const Size(390, 800));
      await tester.pumpWidget(
        correctionScope(repository, const FinancialReversalsScreen()),
      );
      expect(find.text('Loading reversals...'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Financial Reversals'), findsOneWidget);
      expect(find.textContaining('FE-000201'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);

      await tester.binding.setSurfaceSize(const Size(1100, 800));
      final emptyRepository = FakeCorrectionsRepository()..reversalRows = [];
      await tester.pumpWidget(
        correctionScope(emptyRepository, const FinancialReversalsScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('No reversals found.'), findsOneWidget);

      final errorRepository = FakeCorrectionsRepository()..throwList = true;
      await tester.pumpWidget(
        correctionScope(errorRepository, const FinancialReversalsScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reversals could not be loaded.'), findsOneWidget);
    },
  );

  testWidgets('reversal detail and create workflow expose immutable lineage', (
    tester,
  ) async {
    final repository = FakeCorrectionsRepository();
    await tester.pumpWidget(
      correctionScope(
        repository,
        const FinancialReversalDetailScreen(financialEventId: 'event-rev'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Original transaction'), findsOneWidget);
    expect(find.textContaining('tx-original'), findsOneWidget);
    expect(find.text('Another Owner Required'), findsNothing);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(repository.actions, contains('submit_reversal'));

    repository.currentReversal = reversal(status: 'SUBMITTED', version: 3);
    await tester.pumpWidget(
      correctionScope(
        repository,
        const FinancialReversalDetailScreen(financialEventId: 'event-rev'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Another Owner Required'), findsOneWidget);
    await tester.tap(find.text('Approve & Post'));
    await tester.pumpAndSettle();
    expect(repository.actions, contains('approve_reversal'));

    repository.currentReversal = reversal(status: 'SUBMITTED', version: 3);
    await tester.pumpWidget(
      correctionScope(
        repository,
        const FinancialReversalDetailScreen(financialEventId: 'event-rev'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not valid');
    await tester.tap(find.text('Reject').last);
    await tester.pumpAndSettle();
    expect(repository.actions, contains('reject_reversal:not valid'));

    repository.currentReversal = reversal(
      status: 'APPROVED',
      txStatus: 'POSTED',
    );
    await tester.pumpWidget(
      correctionScope(
        repository,
        const FinancialReversalDetailScreen(financialEventId: 'event-rev'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Submit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.textContaining('Original posted transactions'), findsOneWidget);
  });

  testWidgets(
    'adjustment list/detail/create shows delta semantics and actions',
    (tester) async {
      final repository = FakeCorrectionsRepository();
      await tester.pumpWidget(
        correctionScope(repository, const FinancialAdjustmentsScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Financial Adjustments'), findsOneWidget);
      expect(find.textContaining('USD 12.3400'), findsOneWidget);
      repository.currentAdjustment = adjustment(
        status: 'SUBMITTED',
        version: 3,
      );
      await tester.pumpWidget(
        correctionScope(
          repository,
          const FinancialAdjustmentDetailScreen(financialEventId: 'event-adj'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Adjustment Amount / Delta'), findsWidgets);
      expect(find.text('Original transaction'), findsOneWidget);
      expect(find.text('Another Owner Required'), findsOneWidget);
      await tester.tap(find.text('Approve & Post'));
      await tester.pumpAndSettle();
      expect(repository.actions, contains('approve_adjustment'));

      repository.currentAdjustment = adjustment(
        status: 'SUBMITTED',
        version: 3,
      );
      await tester.pumpWidget(
        correctionScope(
          repository,
          const FinancialAdjustmentDetailScreen(financialEventId: 'event-adj'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bad delta');
      await tester.tap(find.text('Reject').last);
      await tester.pumpAndSettle();
      expect(repository.actions, contains('reject_adjustment:bad delta'));

      repository.currentAdjustment = adjustment(
        status: 'APPROVED',
        txStatus: 'POSTED',
      );
      await tester.pumpWidget(
        correctionScope(
          repository,
          const FinancialAdjustmentDetailScreen(financialEventId: 'event-adj'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Submit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.textContaining('does not replace or edit'), findsOneWidget);
    },
  );

  testWidgets(
    'approval queue routes corrections and preserves existing targets',
    (tester) async {
      await tester.pumpWidget(queueApp());
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('FE-REV').first);
      await tester.pumpAndSettle();
      expect(find.text('reversal-detail'), findsOneWidget);
      await tester.tap(find.text('queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('FE-ADJ').first);
      await tester.pumpAndSettle();
      expect(find.text('adjustment-detail'), findsOneWidget);
      await tester.tap(find.text('queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('FE-OB').first);
      await tester.pumpAndSettle();
      expect(find.text('opening-detail'), findsOneWidget);
    },
  );

  test('correction list clears when protected session changes', () async {
    final completer = Completer<List<FinancialReversal>>();
    final repository = FakeCorrectionsRepository()
      ..pendingReversals = completer.future;
    final container = ProviderContainer(
      overrides: [
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.authenticated(authUserId: 'auth-1'),
        ),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(rpc: (_) async => [staffAccountJson()]),
        ),
        ownerFinancialCorrectionAccessProvider.overrideWithValue(true),
        financialCorrectionRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    unawaited(container.read(reversalListProvider.notifier).load());
    await Future<void>.delayed(Duration.zero);
    container.updateOverrides([
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.unauthenticated(),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        CurrentAccountRepository(rpc: (_) async => <Map<String, dynamic>>[]),
      ),
      ownerFinancialCorrectionAccessProvider.overrideWithValue(false),
      financialCorrectionRepositoryProvider.overrideWithValue(repository),
    ]);
    completer.complete([reversal()]);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(reversalListProvider).value,
      isNot(contains(reversal())),
    );
  });
}

Widget correctionScope(FakeCorrectionsRepository repository, Widget child) =>
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.authenticated(authUserId: 'auth-1'),
        ),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(rpc: (_) async => [staffAccountJson()]),
        ),
        ownerFinancialCorrectionAccessProvider.overrideWithValue(true),
        financialCorrectionRepositoryProvider.overrideWithValue(repository),
        financialAccountRepositoryProvider.overrideWithValue(
          FakeFinancialAccounts(),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

Widget queueApp() {
  final router = GoRouter(
    initialLocation: '/staff/financial-approval-queue',
    routes: [
      GoRoute(
        path: '/staff/financial-approval-queue',
        builder: (_, _) => const Scaffold(body: FinancialApprovalQueueScreen()),
      ),
      GoRoute(
        path: '/staff/financial-reversals/:id',
        builder: (context, _) => Scaffold(
          body: Column(
            children: [
              const Text('reversal-detail'),
              TextButton(
                onPressed: () => context.go('/staff/financial-approval-queue'),
                child: const Text('queue'),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/staff/financial-adjustments/:id',
        builder: (context, _) => Scaffold(
          body: Column(
            children: [
              const Text('adjustment-detail'),
              TextButton(
                onPressed: () => context.go('/staff/financial-approval-queue'),
                child: const Text('queue'),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/staff/opening-balances/:id',
        builder: (context, _) => Scaffold(
          body: Column(
            children: [
              const Text('opening-detail'),
              TextButton(
                onPressed: () => context.go('/staff/financial-approval-queue'),
                child: const Text('queue'),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/staff/client-payments/:id',
        builder: (_, _) => const Scaffold(body: Text('client-payment-detail')),
      ),
      GoRoute(
        path: '/staff/project-expenses/:id',
        builder: (_, _) => const Scaffold(body: Text('project-expense-detail')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      ownerOpeningBalanceAccessProvider.overrideWithValue(true),
      openingBalanceRepositoryProvider.overrideWithValue(FakeOpeningBalances()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Map<String, dynamic> sourceJson() => {
  'financial_event_id': 'source-event',
  'event_number': 'FE-SRC',
  'event_type': 'CLIENT_PAYMENT',
  'financial_transaction_id': 'tx-original',
  'transaction_number': 'FT-SRC',
  'amount': '20.0000',
  'currency_code': 'USD',
  'event_date': '2026-08-17',
  'label': 'Client Payment FE-SRC / FT-SRC',
  'can_reverse': true,
  'can_adjust': true,
  'reversal_recorded': false,
  'adjustment_recorded': false,
};

Map<String, dynamic> reversalJson({
  String status = 'DRAFT',
  String txStatus = 'DRAFT',
  int version = 2,
}) => {
  'financial_event_id': 'event-rev',
  'event_number': 'FE-000201',
  'financial_transaction_id': 'tx-rev',
  'transaction_number': 'FT-000201',
  'original_transaction_id': 'tx-original',
  'reversal_date': '2026-08-17',
  'event_status': status,
  'transaction_status': txStatus,
  'version_number': version,
  'reason': 'mistake',
  'description': 'reverse payment',
};

Map<String, dynamic> adjustmentJson({
  String status = 'DRAFT',
  String txStatus = 'DRAFT',
  int version = 2,
}) => {
  'financial_event_id': 'event-adj',
  'event_number': 'FE-000301',
  'financial_transaction_id': 'tx-adj',
  'transaction_number': 'FT-000301',
  'financial_account_id': 'account-1',
  'direction': 'INCREASE',
  'amount': '12.3400',
  'currency_code': 'USD',
  'adjustment_date': '2026-08-17',
  'event_status': status,
  'transaction_status': txStatus,
  'version_number': version,
  'adjusted_transaction_id': 'tx-original',
  'reason': 'delta',
};

Map<String, dynamic> mutationJson() => {
  'financial_event_id': 'event-1',
  'version_number': 2,
};

FinancialReversal reversal({
  String status = 'DRAFT',
  String txStatus = 'DRAFT',
  int version = 2,
}) => FinancialReversal.fromJson(
  reversalJson(status: status, txStatus: txStatus, version: version),
);

FinancialAdjustment adjustment({
  String status = 'DRAFT',
  String txStatus = 'DRAFT',
  int version = 2,
}) => FinancialAdjustment.fromJson(
  adjustmentJson(status: status, txStatus: txStatus, version: version),
);

class FakeCorrectionsRepository extends FinancialCorrectionRepository {
  var sources = [CorrectionSource.fromJson(sourceJson())];
  var reversalRows = [reversal()];
  var adjustmentRows = [adjustment()];
  var currentReversal = reversal();
  var currentAdjustment = adjustment();
  var actions = <String>[];
  var throwList = false;
  Future<List<FinancialReversal>>? pendingReversals;

  @override
  Future<List<CorrectionSource>> eligibleSources() async => sources;
  @override
  Future<List<FinancialReversal>> reversals() async {
    if (throwList) throw StateError('down');
    return pendingReversals ?? reversalRows;
  }

  @override
  Future<FinancialReversal> reversalDetail(String id) async => currentReversal;
  @override
  Future<CorrectionMutationResult> createReversal(ReversalDraft draft) async {
    actions.add('create_reversal:${draft.originalTransactionId}');
    return const CorrectionMutationResult(
      financialEventId: 'event-rev',
      versionNumber: 1,
    );
  }

  @override
  Future<CorrectionMutationResult> submitReversal(
    String id,
    int version,
  ) async {
    actions.add('submit_reversal');
    currentReversal = reversal(status: 'SUBMITTED', version: 3);
    return const CorrectionMutationResult(
      financialEventId: 'event-rev',
      versionNumber: 3,
    );
  }

  @override
  Future<CorrectionMutationResult> approveReversal(
    String id,
    int version,
  ) async {
    actions.add('approve_reversal');
    currentReversal = reversal(status: 'APPROVED', txStatus: 'POSTED');
    return const CorrectionMutationResult(
      financialEventId: 'event-rev',
      versionNumber: 4,
    );
  }

  @override
  Future<CorrectionMutationResult> rejectReversal(
    String id,
    int version,
    String reason,
  ) async {
    actions.add('reject_reversal:$reason');
    return const CorrectionMutationResult(
      financialEventId: 'event-rev',
      versionNumber: 4,
    );
  }

  @override
  Future<List<FinancialAdjustment>> adjustments() async => adjustmentRows;
  @override
  Future<FinancialAdjustment> adjustmentDetail(String id) async =>
      currentAdjustment;
  @override
  Future<CorrectionMutationResult> createAdjustment(
    AdjustmentDraft draft,
  ) async {
    actions.add('create_adjustment:${draft.amount}');
    return const CorrectionMutationResult(
      financialEventId: 'event-adj',
      versionNumber: 1,
    );
  }

  @override
  Future<CorrectionMutationResult> updateAdjustment(
    String id,
    int version,
    AdjustmentDraft draft,
  ) async {
    actions.add('update_adjustment:${draft.amount}');
    return const CorrectionMutationResult(
      financialEventId: 'event-adj',
      versionNumber: 3,
    );
  }

  @override
  Future<CorrectionMutationResult> submitAdjustment(
    String id,
    int version,
  ) async {
    actions.add('submit_adjustment');
    return const CorrectionMutationResult(
      financialEventId: 'event-adj',
      versionNumber: 3,
    );
  }

  @override
  Future<CorrectionMutationResult> approveAdjustment(
    String id,
    int version,
  ) async {
    actions.add('approve_adjustment');
    return const CorrectionMutationResult(
      financialEventId: 'event-adj',
      versionNumber: 4,
    );
  }

  @override
  Future<CorrectionMutationResult> rejectAdjustment(
    String id,
    int version,
    String reason,
  ) async {
    actions.add('reject_adjustment:$reason');
    return const CorrectionMutationResult(
      financialEventId: 'event-adj',
      versionNumber: 4,
    );
  }
}

class FakeOpeningBalances implements OpeningBalanceRepository {
  @override
  Future<List<FinancialApprovalQueueItem>> queue(String section) async => [
    queueItem('FE-REV', 'REVERSAL', 'event-rev'),
    queueItem('FE-ADJ', 'ADJUSTMENT', 'event-adj'),
    queueItem('FE-OB', 'OPENING_BALANCE', 'event-ob'),
    queueItem('FE-CP', 'CLIENT_PAYMENT', 'event-cp'),
    queueItem('FE-PE', 'PROJECT_EXPENSE', 'event-pe'),
    queueItem('FE-UNKNOWN', 'UNKNOWN', 'event-unknown'),
  ];
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

FinancialApprovalQueueItem queueItem(String number, String type, String id) =>
    FinancialApprovalQueueItem(
      financialEventId: id,
      eventNumber: number,
      eventType: type,
      relatedLabel: 'Related $type',
      amount: '1.0000',
      currencyCode: 'USD',
      eventDate: '2026-08-17',
      eventStatus: 'SUBMITTED',
      transactionStatus: 'SUBMITTED',
      createdByMe: false,
      eligibleForMyApproval: true,
      versionNumber: 2,
    );

class FakeFinancialAccounts implements FinancialAccountRepository {
  @override
  Future<List<FinancialAccount>> listAccounts() async => const [
    FinancialAccount(
      id: 'account-1',
      accountNumber: 'FA-1',
      name: 'Operating',
      type: FinancialAccountType.bank,
      currencyCode: 'USD',
      bankName: 'Demo Bank',
      maskedAccountIdentifier: '**1234',
      isActive: true,
      versionNumber: 1,
      balance: ExactMoney(currencyCode: 'USD', amount: '100.0000'),
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
      (await listAccounts()).first;
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
