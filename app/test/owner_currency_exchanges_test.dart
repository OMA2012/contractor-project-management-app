import 'dart:async';

import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/currency_exchanges/currency_exchange_models.dart';
import 'package:contractor_project_management/src/currency_exchanges/currency_exchange_providers.dart';
import 'package:contractor_project_management/src/currency_exchanges/currency_exchange_repository.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_models.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_providers.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_repository.dart';
import 'package:contractor_project_management/src/routing/app_router.dart';
import 'package:contractor_project_management/src/screens/owner_currency_exchanges_screen.dart';
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
        Uri.parse('/staff/currency-exchanges'),
      ),
      isNull,
    );
    expect(
      authRedirect(
        session,
        CurrentAccountLoaded(clientAccount()),
        Uri.parse('/staff/currency-exchanges'),
      ),
      '/client',
    );
  });

  test(
    'repository preserves exact values and never sends Owner identity',
    () async {
      final calls = <Map<String, dynamic>>[];
      final repository = CurrencyExchangeRepository(
        invokeFunction: (name, body) async {
          calls.add({'function': name, ...body});
          return {
            'data': {
              'currency_exchange': mutationJson(),
              'currency_exchanges': [exchangeJson()],
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
      expect(calls[1]['source_amount'], '12500.0000');
      expect(calls[1]['exchange_rate_id'], 'rate-1');
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

  test('repository loads filtered exchange-rate selector options', () async {
    final calls = <Map<String, dynamic>>[];
    final repository = CurrencyExchangeRepository(
      invokeFunction: (name, body) async {
        calls.add({'function': name, ...body});
        return {
          'data': {
            'exchange_rates': [
              {
                'exchange_rate_id': 'rate-1',
                'rate_date': '2026-08-15',
                'base_currency_code': 'SAR',
                'quote_currency_code': 'USD',
                'rate_value': '0.264600',
                'source': 'MANUAL',
              },
            ],
          },
        };
      },
    );
    final rates = await repository.rateOptions(
      sourceCurrencyCode: 'SAR',
      destinationCurrencyCode: 'USD',
      exchangeDate: '2026-08-15',
    );
    expect(calls.single['action'], 'rate_lookup');
    expect(calls.single['source_currency_code'], 'SAR');
    expect(calls.single['destination_currency_code'], 'USD');
    expect(calls.single['exchange_date'], '2026-08-15');
    expect(rates.single.display, '2026-08-15 - 1 SAR = 0.264600 USD');
  });

  testWidgets('list renders mobile and laptop states', (tester) async {
    final repository = FakeCurrencyExchangeRepository();
    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pumpWidget(exchangeList(repository));
    expect(find.text('Loading currency exchanges...'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Currency Exchanges'), findsOneWidget);
    expect(find.textContaining('FE-000101'), findsOneWidget);
    expect(find.textContaining('12500.0000 SAR'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1000, 800));
    repository.items = [];
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('No currency exchanges found.'), findsOneWidget);
  });

  testWidgets(
    'detail shows rate direction, projections, Cash/Bank display, and immutability',
    (tester) async {
      final repository = FakeCurrencyExchangeRepository();
      await tester.pumpWidget(exchangeDetail(repository));
      await tester.pumpAndSettle();
      expect(find.text('Edit Draft'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Rate direction'), findsOneWidget);
      expect(find.textContaining('1 SAR = 0.264600 USD'), findsOneWidget);
      expect(find.text('Estimated conversion preview'), findsOneWidget);
      expect(find.text('Projected Balance Change'), findsOneWidget);
      expect(find.textContaining('Cash - SAR'), findsWidgets);
      expect(
        find.textContaining('Bank - USD - Demo Bank - **1234'),
        findsWidgets,
      );
      expect(find.textContaining('3409.6000'), findsOneWidget);

      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(repository.actions, contains('submit'));

      repository.current = exchange(status: 'SUBMITTED', version: 3);
      await tester.pumpWidget(exchangeDetail(repository));
      await tester.pumpAndSettle();
      expect(find.textContaining('Another Owner'), findsOneWidget);
      await tester.tap(find.text('Approve & Post'));
      await tester.pumpAndSettle();
      expect(repository.actions, contains('approve'));

      repository.current = exchange(
        status: 'APPROVED',
        txStatus: 'POSTED',
        version: 4,
      );
      await tester.pumpWidget(exchangeDetail(repository));
      await tester.pumpAndSettle();
      expect(find.text('Edit Draft'), findsNothing);
      expect(find.text('Final posted snapshot'), findsOneWidget);
      expect(
        find.textContaining(
          'Posted currency exchanges are immutable',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );

  test(
    'stale account/session protection does not apply stale list result',
    () async {
      final completer = Completer<List<CurrencyExchange>>();
      final repository = FakeCurrencyExchangeRepository()
        ..pendingList = completer.future;
      final container = ProviderContainer(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.authenticated(authUserId: 'auth-1'),
          ),
          currentAccountRepositoryProvider.overrideWithValue(
            CurrentAccountRepository(rpc: (_) async => [staffAccountJson()]),
          ),
          currencyExchangeRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      unawaited(container.read(currencyExchangeListProvider.notifier).load());
      await Future<void>.delayed(Duration.zero);
      container.updateOverrides([
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.unauthenticated(),
        ),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(rpc: (_) async => <Map<String, dynamic>>[]),
        ),
        currencyExchangeRepositoryProvider.overrideWithValue(repository),
      ]);
      completer.complete([exchange()]);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(currencyExchangeListProvider).value,
        isNot(contains(exchange())),
      );
    },
  );
}

Widget exchangeList(FakeCurrencyExchangeRepository repository) => ProviderScope(
  overrides: [
    initialAuthSessionProvider.overrideWithValue(
      const AuthSessionState.authenticated(authUserId: 'auth-1'),
    ),
    currentAccountRepositoryProvider.overrideWithValue(
      CurrentAccountRepository(rpc: (_) async => [staffAccountJson()]),
    ),
    ownerCurrencyExchangeAccessProvider.overrideWithValue(true),
    currencyExchangeRepositoryProvider.overrideWithValue(repository),
    financialAccountRepositoryProvider.overrideWithValue(
      FakeFinancialAccounts(),
    ),
  ],
  child: const MaterialApp(
    home: Scaffold(body: OwnerCurrencyExchangesScreen()),
  ),
);

Widget exchangeDetail(FakeCurrencyExchangeRepository repository) =>
    ProviderScope(
      overrides: [
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.authenticated(authUserId: 'auth-1'),
        ),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(rpc: (_) async => [staffAccountJson()]),
        ),
        ownerCurrencyExchangeAccessProvider.overrideWithValue(true),
        currencyExchangeRepositoryProvider.overrideWithValue(repository),
        financialAccountRepositoryProvider.overrideWithValue(
          FakeFinancialAccounts(),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: OwnerCurrencyExchangeDetailScreen(financialEventId: 'event-1'),
        ),
      ),
    );

CurrencyExchangeDraft draft() => const CurrencyExchangeDraft(
  sourceAccountId: 'cash-sar',
  destinationAccountId: 'bank-usd',
  sourceAmount: '12500.0000',
  exchangeRateId: 'rate-1',
  exchangeDate: '2026-08-15',
  feeAmount: '0',
  reference: 'owner-ref',
);

CurrencyExchange exchange({
  String status = 'DRAFT',
  String txStatus = 'DRAFT',
  int version = 2,
}) => CurrencyExchange.fromJson({
  ...exchangeJson(),
  'event_status': status,
  'transaction_status': txStatus,
  'version_number': version,
});

Map<String, dynamic> exchangeJson() => {
  'currency_exchange_id': 'exchange-1',
  'financial_event_id': 'event-1',
  'event_number': 'FE-000101',
  'financial_transaction_id': 'tx-1',
  'transaction_number': 'FT-000101',
  'source_account_id': 'cash-sar',
  'destination_account_id': 'bank-usd',
  'source_amount': '12500.0000',
  'source_currency_code': 'SAR',
  'destination_amount': '3307.5000',
  'destination_currency_code': 'USD',
  'exchange_rate_id': 'rate-1',
  'rate_base_currency_code': 'SAR',
  'rate_quote_currency_code': 'USD',
  'rate_value': '0.264600',
  'rate_source': 'MANUAL',
  'fee_amount': '0',
  'fee_currency_code': null,
  'exchange_date': '2026-08-15',
  'rounding_result': '0.0000',
  'reference': 'owner-ref',
  'reporting_currency_code': 'USD',
  'event_status': 'DRAFT',
  'transaction_status': 'DRAFT',
  'version_number': 2,
};

Map<String, dynamic> mutationJson() => {
  'financial_event_id': 'event-1',
  'version_number': 2,
};

class FakeCurrencyExchangeRepository extends CurrencyExchangeRepository {
  List<CurrencyExchange> items = [exchange()];
  CurrencyExchange current = exchange();
  Future<List<CurrencyExchange>>? pendingList;
  final actions = <String>[];

  @override
  Future<List<CurrencyExchange>> list() async => pendingList ?? items;
  @override
  Future<CurrencyExchange> detail(String financialEventId) async => current;
  @override
  Future<List<ExchangeRateOption>> rateOptions({
    required String sourceCurrencyCode,
    required String destinationCurrencyCode,
    required String exchangeDate,
  }) async => const [
    ExchangeRateOption(
      exchangeRateId: 'rate-1',
      rateDate: '2026-08-15',
      baseCurrencyCode: 'SAR',
      quoteCurrencyCode: 'USD',
      rateValue: '0.264600',
      source: 'MANUAL',
    ),
  ];
  @override
  Future<CurrencyExchangeMutationResult> create(
    CurrencyExchangeDraft draft,
  ) async => const CurrencyExchangeMutationResult(
    financialEventId: 'event-1',
    versionNumber: 1,
  );
  @override
  Future<CurrencyExchangeMutationResult> update({
    required String financialEventId,
    required int expectedVersionNumber,
    required CurrencyExchangeDraft draft,
  }) async => const CurrencyExchangeMutationResult(
    financialEventId: 'event-1',
    versionNumber: 3,
  );
  @override
  Future<CurrencyExchangeMutationResult> submit(String id, int version) async {
    actions.add('submit');
    current = exchange(status: 'SUBMITTED', version: 3);
    return const CurrencyExchangeMutationResult(
      financialEventId: 'event-1',
      versionNumber: 3,
    );
  }

  @override
  Future<CurrencyExchangeMutationResult> approve(String id, int version) async {
    actions.add('approve');
    current = exchange(status: 'APPROVED', txStatus: 'POSTED', version: 4);
    return const CurrencyExchangeMutationResult(
      financialEventId: 'event-1',
      versionNumber: 4,
    );
  }

  @override
  Future<CurrencyExchangeMutationResult> reject(
    String id,
    int version,
    String reason,
  ) async {
    actions.add('reject:$reason');
    current = exchange(status: 'REJECTED', txStatus: 'REJECTED', version: 4);
    return const CurrencyExchangeMutationResult(
      financialEventId: 'event-1',
      versionNumber: 4,
    );
  }
}

class FakeFinancialAccounts implements FinancialAccountRepository {
  @override
  Future<List<FinancialAccount>> listAccounts() async => [
    const FinancialAccount(
      id: 'cash-sar',
      accountNumber: 'FA-1',
      name: 'Riyadh Cash',
      type: FinancialAccountType.cash,
      currencyCode: 'SAR',
      isActive: true,
      versionNumber: 1,
      balance: ExactMoney(currencyCode: 'SAR', amount: '20000.0000'),
    ),
    const FinancialAccount(
      id: 'bank-usd',
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
