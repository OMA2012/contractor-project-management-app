import 'dart:async';

import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/app.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/payments/payment_models.dart';
import 'package:contractor_project_management/src/payments/payment_providers.dart';
import 'package:contractor_project_management/src/payments/payment_repository.dart';
import 'package:contractor_project_management/src/projects/project_models.dart';
import 'package:contractor_project_management/src/projects/project_providers.dart';
import 'package:contractor_project_management/src/projects/project_repository.dart';
import 'package:contractor_project_management/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payment repository calls exact Client financial RPCs', () async {
    final calls = <Map<String, dynamic>>[];
    final repository = SupabasePaymentRepository(
      rpc: (functionName, {params}) async {
        calls.add({'function': functionName, ...?params});
        return switch (functionName) {
          'current_client_approved_payment_list' => [paymentRow()],
          'current_client_approved_payment_detail' => paymentRow(
            id: params!['p_client_payment_id'] as String,
          ),
          'current_client_payment_request_list' => [requestRow()],
          'current_client_view_payment_request_detail' => requestRow(
            id: params!['p_payment_request_id'] as String,
          ),
          'current_client_submit_payment' => {
            'financial_event_id': 'event-hidden',
            'event_number': 'FE-hidden',
            'financial_transaction_id': 'tx-hidden',
            'transaction_number': 'FT-hidden',
            'client_payment_id': 'pay-new',
          },
          _ => <Map<String, dynamic>>[],
        };
      },
    );

    await repository.listApprovedPayments(limit: 25, offset: 50);
    await repository.getApprovedPaymentDetail('pay-1');
    await repository.submitPayment(
      projectId: 'project-1',
      amount: ExactMoney.fromInput('1200.50'),
      currencyCode: 'SGD',
      receivedDate: DateTime(2026, 8, 12),
      paymentReference: ' ref ',
      payerName: ' payer ',
    );
    await repository.listPaymentRequests(limit: 10, offset: 20);
    await repository.viewPaymentRequestDetail('req-1');

    expect(calls[0], {
      'function': 'current_client_approved_payment_list',
      'p_limit': 25,
      'p_offset': 50,
    });
    expect(calls[1], {
      'function': 'current_client_approved_payment_detail',
      'p_client_payment_id': 'pay-1',
    });
    expect(calls[2], {
      'function': 'current_client_submit_payment',
      'p_project_id': 'project-1',
      'p_amount': '1200.50',
      'p_currency_code': 'SGD',
      'p_received_date': '2026-08-12',
      'p_payment_reference': 'ref',
      'p_payer_name': 'payer',
      'p_request_identifier': null,
      'p_correlation_identifier': null,
    });
    expect(calls[2].keys, isNot(contains('client_id')));
    expect(calls[2].keys, isNot(contains('auth_subject')));
    expect(calls[3], {
      'function': 'current_client_payment_request_list',
      'p_limit': 10,
      'p_offset': 20,
    });
    expect(calls[4], {
      'function': 'current_client_view_payment_request_detail',
      'p_payment_request_id': 'req-1',
      'p_request_identifier': null,
      'p_correlation_identifier': null,
    });
  });

  test('models map safe projections and exact money without double math', () {
    final payment = ClientApprovedPayment.fromJson({
      ...paymentRow(reference: null),
      'received_account_id': 'hidden-account',
      'ledger_entry_id': 'hidden-ledger',
      'exchange_rate_id': 'hidden-rate',
      'approved_by': 'hidden-owner',
      'notes': 'hidden-note',
    });
    final request = ClientPaymentRequest.fromJson({
      ...requestRow(description: null),
      'created_by': 'hidden-owner',
      'financial_event_id': 'hidden-event',
      'amount': '1000.10',
      'requested_amount': '9999.99',
    });
    final result = ClientPaymentSubmissionResult.fromJson({
      'client_payment_id': 'pay-new',
      'financial_event_id': 'event-hidden',
      'event_number': 'FE-hidden',
      'financial_transaction_id': 'tx-hidden',
      'transaction_number': 'FT-hidden',
    });

    expect(payment.paymentReference, isNull);
    expect(payment.amount.text, '1000.10');
    expect(payment.isReceived, isTrue);
    expect(payment.toString(), isNot(contains('hidden')));
    expect(request.description, isNull);
    expect(request.requestedAmount.text, '1000.10');
    expect(request.effectiveStatus, 'OVERDUE');
    expect(request.remainingAmount.text, '900.10');
    expect(result.clientPaymentId, 'pay-new');
    expect(result.toString(), isNot(contains('FE-hidden')));
    expect(() => ExactMoney.fromInput('0'), throwsA(isA<PaymentFailure>()));
    expect(() => ExactMoney.fromInput('-1'), throwsA(isA<PaymentFailure>()));
    expect(
      () => ExactMoney.fromInput('12.1234567'),
      throwsA(isA<PaymentFailure>()),
    );
    expect(
      () => ExactMoney.fromInput('1.10.2'),
      throwsA(isA<PaymentFailure>()),
    );
    expect(() => ExactMoney.fromInput('1e3'), throwsA(isA<PaymentFailure>()));
    expect(ExactMoney.fromInput('100').text, '100');
    expect(ExactMoney.fromInput('100.00').text, '100.00');
    expect(ExactMoney.fromInput('0.01').text, '0.01');
  });

  test('payment request backend money parses zero balances exactly', () {
    final unpaid = ClientPaymentRequest.fromJson({
      ...requestRow(),
      'paid_amount': '0',
      'remaining_amount': '1000.10',
    });
    final fullyPaid = ClientPaymentRequest.fromJson({
      ...requestRow(),
      'paid_amount': '1000.10',
      'remaining_amount': '0',
      'effective_status': 'PAID',
    });
    final bothZero = ClientPaymentRequest.fromJson({
      ...requestRow(),
      'requested_amount': '100.00',
      'paid_amount': '0.00',
      'remaining_amount': '0.00',
    });

    expect(unpaid.paidAmount.text, '0');
    expect(unpaid.remainingAmount.text, '1000.10');
    expect(fullyPaid.paidAmount.text, '1000.10');
    expect(fullyPaid.remainingAmount.text, '0');
    expect(bothZero.paidAmount.text, '0.00');
    expect(bothZero.remainingAmount.text, '0.00');
  });

  test('backend money rejects negative, malformed, and numeric values', () {
    expect(
      () =>
          ClientPaymentRequest.fromJson({...requestRow(), 'paid_amount': '-1'}),
      throwsA(isA<PaymentFailure>()),
    );
    expect(
      () => ClientPaymentRequest.fromJson({
        ...requestRow(),
        'remaining_amount': '-1',
      }),
      throwsA(isA<PaymentFailure>()),
    );
    expect(
      () => ClientPaymentRequest.fromJson({
        ...requestRow(),
        'paid_amount': '1.1234567',
      }),
      throwsA(isA<PaymentFailure>()),
    );
    expect(
      () =>
          ClientPaymentRequest.fromJson({...requestRow(), 'paid_amount': 1.25}),
      throwsA(isA<PaymentFailure>()),
    );
    expect(
      () => ClientPaymentRequest.fromJson({...requestRow(), 'paid_amount': 1}),
      throwsA(isA<PaymentFailure>()),
    );
  });

  test(
    'payment and request pagination are independent and dedupe rows',
    () async {
      final repository = FakePaymentRepository(
        paymentPages: [
          ClientPaymentPage(
            rawCount: 2,
            payments: [payment('pay-a'), payment('pay-a')],
          ),
          ClientPaymentPage(rawCount: 1, payments: [payment('pay-b')]),
        ],
        requestPages: [
          ClientPaymentRequestPage(
            rawCount: 2,
            requests: [request('req-a'), request('req-a')],
          ),
          ClientPaymentRequestPage(rawCount: 1, requests: [request('req-b')]),
        ],
      );
      final container = clientContainer(repository);
      addTearDown(container.dispose);
      await container.read(currentAccountProvider.notifier).load();

      await container
          .read(clientApprovedPaymentListProvider.notifier)
          .load(limit: 2);
      await container
          .read(clientPaymentRequestListProvider.notifier)
          .load(limit: 2);
      await container
          .read(clientApprovedPaymentListProvider.notifier)
          .loadMore();
      await container
          .read(clientPaymentRequestListProvider.notifier)
          .loadMore();

      expect(repository.paymentOffsets, [0, 2]);
      expect(repository.requestOffsets, [0, 2]);
      expect(
        container
            .read(clientApprovedPaymentListProvider)
            .payments
            .map((e) => e.clientPaymentId),
        ['pay-a', 'pay-b'],
      );
      expect(
        container
            .read(clientPaymentRequestListProvider)
            .requests
            .map((e) => e.paymentRequestId),
        ['req-a', 'req-b'],
      );
    },
  );

  test(
    'stale financial results and errors are discarded after account changes',
    () async {
      final account = MutableAccountRepository(clientRow('client-a'));
      final paymentList = Completer<ClientPaymentPage>();
      final requestDetail = Completer<ClientPaymentRequest?>();
      final repository = FakePaymentRepository(
        paymentListCompleters: [paymentList],
        requestDetailCompleters: [requestDetail],
      );
      final container = clientContainer(repository, accountRepository: account);
      addTearDown(container.dispose);
      container.listen(
        clientApprovedPaymentListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        clientPaymentRequestDetailProvider('req-a'),
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(currentAccountProvider.notifier).load();

      final listLoad = container
          .read(clientApprovedPaymentListProvider.notifier)
          .load();
      final detailLoad = container
          .read(clientPaymentRequestDetailProvider('req-a').notifier)
          .load();
      await pumpProvider();
      account.row = staffRow();
      await container.read(currentAccountProvider.notifier).load();
      await pumpProvider();

      paymentList.complete(
        ClientPaymentPage(rawCount: 1, payments: [payment('stale')]),
      );
      requestDetail.complete(request('stale'));
      await listLoad;
      await detailLoad;

      expect(
        container.read(clientApprovedPaymentListProvider).payments,
        isEmpty,
      );
      expect(
        container.read(clientPaymentRequestDetailProvider('req-a')).request,
        isNull,
      );
    },
  );

  test('request list does not call view-detail RPC', () async {
    final repository = FakePaymentRepository(
      requestPages: [
        ClientPaymentRequestPage(rawCount: 1, requests: [request('req-a')]),
      ],
    );
    final container = clientContainer(repository);
    addTearDown(container.dispose);
    await container.read(currentAccountProvider.notifier).load();

    await container.read(clientPaymentRequestListProvider.notifier).load();

    expect(repository.requestOffsets, [0]);
    expect(repository.requestDetailIds, isEmpty);
  });

  testWidgets('payment screens render safe data and no private fields', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    final repository = FakePaymentRepository(
      paymentPages: [
        ClientPaymentPage(rawCount: 1, payments: [payment('pay-uuid-1')]),
      ],
      paymentDetail: payment(
        'pay-uuid-1',
        status: 'SUBMITTED',
        transactionStatus: 'DRAFT',
      ),
      requestPages: [
        ClientPaymentRequestPage(
          rawCount: 1,
          requests: [request('req-uuid-1')],
        ),
      ],
      requestDetail: request('req-uuid-1'),
    );

    await tester.pumpWidget(appWithRepository(repository, '/client/payments'));
    await tester.pumpAndSettle();
    expect(find.text('1000.10 SGD'), findsOneWidget);
    expect(find.textContaining('pay-uuid'), findsNothing);
    expect(find.textContaining('ledger'), findsNothing);
    expect(find.textContaining('exchange'), findsNothing);

    await tester.tap(find.text('1000.10 SGD'));
    await tester.pumpAndSettle();
    expect(find.text('Status unavailable'), findsOneWidget);
    expect(find.text('Received and posted'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      appWithRepository(repository, '/client/payment-requests'),
    );
    await tester.pumpAndSettle();
    expect(find.text('REQ-001'), findsOneWidget);
    expect(find.textContaining('DRAFT'), findsNothing);

    await tester.tap(find.text('REQ-001'));
    await tester.pumpAndSettle();
    expect(repository.requestDetailIds, ['req-uuid-1']);
    await tester.pump();
    expect(repository.requestDetailIds, ['req-uuid-1']);
    expect(find.text('Remaining'), findsOneWidget);
    expect(find.textContaining('req-uuid'), findsNothing);
  });

  testWidgets(
    'submit form validates, sends exact values, and avoids receipt wording',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 800));
      final repository = FakePaymentRepository();
      await tester.pumpWidget(
        appWithRepository(repository, '/client/payments/submit'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Project'), findsOneWidget);
      expect(find.textContaining('project-1'), findsNothing);
      expect(find.textContaining('receiving account'), findsNothing);
      expect(find.textContaining('exchange rate'), findsNothing);

      await tester.tap(find.text('Submit for verification'));
      await tester.pump();
      expect(find.text('Select a payment date.'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<ClientProject>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PRJ-001 - Kitchen Renovation').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '1200.50',
      );
      await tester.tap(find.textContaining('Select payment date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('${DateTime.now().day}'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Payment reference optional'),
        ' ref ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Payer name optional'),
        ' payer ',
      );
      await tester.tap(find.text('Submit for verification'));
      await tester.pump();
      await tester.tap(find.text('Submitting'), warnIfMissed: false);
      repository.submitCompleter!.complete(
        const ClientPaymentSubmissionResult(clientPaymentId: 'new-id'),
      );
      await tester.pumpAndSettle();

      expect(repository.submitCalls.length, 1);
      expect(repository.submitCalls.single.amount.text, '1200.50');
      expect(repository.submitCalls.single.paymentReference, ' ref ');
      expect(repository.submitCalls.single.payerName, ' payer ');
      expect(find.textContaining('Submitted for verification'), findsOneWidget);
      expect(find.textContaining('does not confirm receipt'), findsOneWidget);
      expect(find.textContaining('Received'), findsNothing);
      expect(find.textContaining('Posted'), findsNothing);
      expect(find.textContaining('Confirmed'), findsNothing);
      expect(find.textContaining('event'), findsNothing);
      expect(find.textContaining('transaction'), findsNothing);
    },
  );

  testWidgets('payment request list suppresses draft rows safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      appWithRepository(
        FakePaymentRepository(
          requestPages: [
            ClientPaymentRequestPage(
              rawCount: 2,
              requests: [
                request('req-draft', status: 'DRAFT', effectiveStatus: 'DRAFT'),
                request('req-sent', status: 'SENT', effectiveStatus: 'SENT'),
              ],
            ),
          ],
        ),
        '/client/payment-requests',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('REQ-001'), findsOneWidget);
    expect(find.textContaining('DRAFT'), findsNothing);
    expect(find.textContaining('req-draft'), findsNothing);
  });

  test(
    'stale payment and request detail route results are discarded',
    () async {
      final paymentA = Completer<ClientApprovedPayment?>();
      final paymentB = Completer<ClientApprovedPayment?>();
      final requestA = Completer<ClientPaymentRequest?>();
      final requestB = Completer<ClientPaymentRequest?>();
      final repository = FakePaymentRepository(
        paymentDetailCompleters: [paymentA, paymentB],
        requestDetailCompleters: [requestA, requestB],
      );
      final container = clientContainer(repository);
      addTearDown(container.dispose);
      container.listen(
        clientApprovedPaymentDetailProvider('pay-a'),
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        clientApprovedPaymentDetailProvider('pay-b'),
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        clientPaymentRequestDetailProvider('req-a'),
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        clientPaymentRequestDetailProvider('req-b'),
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(currentAccountProvider.notifier).load();

      final payLoadA = container
          .read(clientApprovedPaymentDetailProvider('pay-a').notifier)
          .load();
      final payLoadB = container
          .read(clientApprovedPaymentDetailProvider('pay-b').notifier)
          .load();
      final reqLoadA = container
          .read(clientPaymentRequestDetailProvider('req-a').notifier)
          .load();
      final reqLoadB = container
          .read(clientPaymentRequestDetailProvider('req-b').notifier)
          .load();
      paymentA.complete(payment('pay-a'));
      requestA.complete(request('req-a'));
      await pumpProvider();
      expect(
        container.read(clientApprovedPaymentDetailProvider('pay-b')).payment,
        isNull,
      );
      expect(
        container.read(clientPaymentRequestDetailProvider('req-b')).request,
        isNull,
      );
      paymentB.complete(payment('pay-b'));
      requestB.complete(request('req-b'));
      await Future.wait([payLoadA, payLoadB, reqLoadA, reqLoadB]);

      expect(
        container
            .read(clientApprovedPaymentDetailProvider('pay-b'))
            .payment
            ?.clientPaymentId,
        'pay-b',
      );
      expect(
        container
            .read(clientPaymentRequestDetailProvider('req-b'))
            .request
            ?.paymentRequestId,
        'req-b',
      );
      expect(repository.paymentDetailIds, ['pay-a', 'pay-b']);
      expect(repository.requestDetailIds, ['req-a', 'req-b']);
    },
  );

  test(
    'stale payment request list errors are discarded after logout',
    () async {
      final requestList = Completer<ClientPaymentRequestPage>();
      final repository = FakePaymentRepository(
        requestListCompleters: [requestList],
      );
      final container = clientContainer(repository);
      addTearDown(container.dispose);
      container.listen(
        clientPaymentRequestListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(currentAccountProvider.notifier).load();

      final load = container
          .read(clientPaymentRequestListProvider.notifier)
          .load();
      await pumpProvider();
      container.read(authSessionProvider.notifier).signOut();
      requestList.completeError(StateError('SQL backend detail'));
      await load;

      expect(container.read(clientPaymentRequestListProvider).error, isNull);
      expect(
        container.read(clientPaymentRequestListProvider).requests,
        isEmpty,
      );
    },
  );

  testWidgets('direct Client financial routes are guarded', (tester) async {
    await tester.pumpWidget(
      appWithRepository(FakePaymentRepository(), '/client/payments/pay-1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Payment detail'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      appWithRepository(
        FakePaymentRepository(),
        '/client/payment-requests/req-1',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Payment request detail'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      appWithRepository(
        FakePaymentRepository(),
        '/client/payments/submit',
        row: staffRow(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Staff workspace'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(appWithoutSession('/client/payments'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      appWithRepository(
        FakePaymentRepository(),
        '/client/payments',
        row: inactiveRow(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Account suspended'), findsOneWidget);
  });
}

ClientApprovedPayment payment(
  String id, {
  String status = 'APPROVED',
  String transactionStatus = 'POSTED',
}) => ClientApprovedPayment.fromJson(
  paymentRow(id: id, status: status, transactionStatus: transactionStatus),
);

ClientPaymentRequest request(
  String id, {
  String status = 'SENT',
  String effectiveStatus = 'OVERDUE',
}) => ClientPaymentRequest.fromJson(
  requestRow(id: id, status: status, effectiveStatus: effectiveStatus),
);

Map<String, dynamic> paymentRow({
  String id = 'pay-1',
  String? reference = 'WIRE-1',
  String status = 'APPROVED',
  String transactionStatus = 'POSTED',
}) {
  return {
    'client_payment_id': id,
    'project_id': 'project-1',
    'project_number': 'PRJ-001',
    'amount': '1000.10',
    'currency_code': 'SGD',
    'received_date': '2026-08-10',
    'payment_reference': reference,
    'approved_at': '2026-08-11T00:00:00Z',
    'event_status': status,
    'transaction_status': transactionStatus,
  };
}

Map<String, dynamic> requestRow({
  String id = 'req-1',
  String status = 'SENT',
  String effectiveStatus = 'OVERDUE',
  String? description = 'Visible request description.',
}) {
  return {
    'payment_request_id': id,
    'request_number': 'REQ-001',
    'project_id': 'project-1',
    'project_number': 'PRJ-001',
    'requested_amount': '1000.10',
    'currency_code': 'SGD',
    'request_date': '2026-08-01',
    'due_date': '2026-08-10',
    'description': description,
    'sent_at': '2026-08-01T00:00:00Z',
    'viewed_at': null,
    'status': status,
    'effective_status': effectiveStatus,
    'paid_amount': '100.00',
    'remaining_amount': '900.10',
  };
}

class SubmitCall {
  const SubmitCall(
    this.projectId,
    this.amount,
    this.currencyCode,
    this.receivedDate,
    this.paymentReference,
    this.payerName,
  );

  final String projectId;
  final ExactMoney amount;
  final String currencyCode;
  final DateTime receivedDate;
  final String? paymentReference;
  final String? payerName;
}

class FakePaymentRepository implements PaymentRepository {
  FakePaymentRepository({
    this.paymentPages = const [],
    this.requestPages = const [],
    this.paymentDetail,
    this.requestDetail,
    this.paymentListCompleters = const [],
    this.paymentDetailCompleters = const [],
    this.requestListCompleters = const [],
    this.requestDetailCompleters = const [],
  });

  final List<ClientPaymentPage> paymentPages;
  final List<ClientPaymentRequestPage> requestPages;
  final ClientApprovedPayment? paymentDetail;
  final ClientPaymentRequest? requestDetail;
  final List<Completer<ClientPaymentPage>> paymentListCompleters;
  final List<Completer<ClientApprovedPayment?>> paymentDetailCompleters;
  final List<Completer<ClientPaymentRequestPage>> requestListCompleters;
  final List<Completer<ClientPaymentRequest?>> requestDetailCompleters;
  final paymentOffsets = <int>[];
  final requestOffsets = <int>[];
  final paymentDetailIds = <String>[];
  final requestDetailIds = <String>[];
  final submitCalls = <SubmitCall>[];
  Completer<ClientPaymentSubmissionResult>? submitCompleter;
  var _paymentPage = 0;
  var _requestPage = 0;
  var _paymentListCompleter = 0;
  var _paymentDetailCompleter = 0;
  var _requestListCompleter = 0;
  var _requestDetailCompleter = 0;

  @override
  Future<ClientPaymentPage> listApprovedPayments({
    int limit = 50,
    int offset = 0,
  }) async {
    paymentOffsets.add(offset);
    if (_paymentListCompleter < paymentListCompleters.length) {
      return paymentListCompleters[_paymentListCompleter++].future;
    }
    if (_paymentPage < paymentPages.length) return paymentPages[_paymentPage++];
    return const ClientPaymentPage(rawCount: 0, payments: []);
  }

  @override
  Future<ClientApprovedPayment?> getApprovedPaymentDetail(
    String clientPaymentId,
  ) async {
    paymentDetailIds.add(clientPaymentId);
    if (_paymentDetailCompleter < paymentDetailCompleters.length) {
      return paymentDetailCompleters[_paymentDetailCompleter++].future;
    }
    return paymentDetail ?? payment(clientPaymentId);
  }

  @override
  Future<ClientPaymentSubmissionResult> submitPayment({
    required String projectId,
    required ExactMoney amount,
    required String currencyCode,
    required DateTime receivedDate,
    String? paymentReference,
    String? payerName,
  }) {
    submitCalls.add(
      SubmitCall(
        projectId,
        amount,
        currencyCode,
        receivedDate,
        paymentReference,
        payerName,
      ),
    );
    submitCompleter = Completer<ClientPaymentSubmissionResult>();
    return submitCompleter!.future;
  }

  @override
  Future<ClientPaymentRequestPage> listPaymentRequests({
    int limit = 50,
    int offset = 0,
  }) async {
    requestOffsets.add(offset);
    if (_requestListCompleter < requestListCompleters.length) {
      return requestListCompleters[_requestListCompleter++].future;
    }
    if (_requestPage < requestPages.length) return requestPages[_requestPage++];
    return const ClientPaymentRequestPage(rawCount: 0, requests: []);
  }

  @override
  Future<ClientPaymentRequest?> viewPaymentRequestDetail(
    String paymentRequestId,
  ) async {
    requestDetailIds.add(paymentRequestId);
    if (_requestDetailCompleter < requestDetailCompleters.length) {
      return requestDetailCompleters[_requestDetailCompleter++].future;
    }
    return requestDetail ?? request(paymentRequestId);
  }
}

ProviderContainer clientContainer(
  PaymentRepository repository, {
  CurrentAccountRepository? accountRepository,
}) {
  return ProviderContainer(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'user-a'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        accountRepository ?? MutableAccountRepository(clientRow('client-a')),
      ),
      paymentRepositoryProvider.overrideWithValue(repository),
      projectRepositoryProvider.overrideWithValue(FakeProjectRepository()),
    ],
  );
}

Widget appWithRepository(
  PaymentRepository repository,
  String initialLocation, {
  dynamic row,
}) {
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'user-a'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        CurrentAccountRepository(
          rpc: (_) async => row ?? clientRow('client-a'),
        ),
      ),
      paymentRepositoryProvider.overrideWithValue(repository),
      projectRepositoryProvider.overrideWithValue(FakeProjectRepository()),
      routerInitialLocationProvider.overrideWithValue(initialLocation),
    ],
    child: const ContractorProjectManagementApp(),
  );
}

Widget appWithoutSession(String initialLocation) {
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.unauthenticated(),
      ),
      routerInitialLocationProvider.overrideWithValue(initialLocation),
    ],
    child: const ContractorProjectManagementApp(),
  );
}

class FakeProjectRepository implements ProjectRepository {
  @override
  Future<ClientProjectPage> listClientProjects({
    int limit = 50,
    int offset = 0,
  }) async {
    return ClientProjectPage(rawCount: 1, projects: [project()]);
  }

  @override
  Future<ClientProject?> getClientProject(String projectId) async => project();

  @override
  Future<ClientProjectCompletion?> getClientProjectCompletion(
    String projectId,
  ) async => null;

  @override
  Future<List<ClientProjectPhase>> getClientProjectPhases(
    String projectId,
  ) async => const [];

  @override
  Future<ClientProjectPhaseCompletion?> getClientProjectPhaseCompletion(
    String phaseId,
  ) async => null;

  @override
  Future<List<ClientProjectTask>> getClientProjectTasks(
    String projectId,
  ) async => const [];

  @override
  Future<ClientProgressUpdatePage> listClientProgressUpdates(
    String projectId, {
    int limit = 50,
    int offset = 0,
  }) async {
    return const ClientProgressUpdatePage(rawCount: 0, items: []);
  }
}

ClientProject project() => ClientProject.fromJson({
  'id': 'project-1',
  'project_number': 'PRJ-001',
  'name': 'Kitchen Renovation',
  'status': 'ACTIVE',
  'reporting_currency_code': 'SGD',
});

class MutableAccountRepository extends CurrentAccountRepository {
  MutableAccountRepository(this.row);

  List<Map<String, dynamic>> row;

  @override
  Future<CurrentAccount?> loadCurrentAccount() async {
    if (row.isEmpty) return null;
    return CurrentAccount.fromJson(row.single);
  }
}

List<Map<String, dynamic>> clientRow(String id) => [
  {
    'application_user_id': id,
    'account_status': 'ACTIVE',
    'is_active': true,
    'access_allowed': true,
    'user_type': 'CLIENT',
    'full_name': 'Client Person',
    'job_title': null,
    'active_role_codes': ['client'],
  },
];

List<Map<String, dynamic>> staffRow() => [
  {
    'application_user_id': 'staff-person',
    'account_status': 'ACTIVE',
    'is_active': true,
    'access_allowed': true,
    'user_type': 'STAFF',
    'full_name': 'Staff Person',
    'job_title': 'Owner',
    'active_role_codes': ['owner_admin'],
  },
];

List<Map<String, dynamic>> inactiveRow() => [
  {
    'application_user_id': 'inactive-person',
    'account_status': 'SUSPENDED',
    'is_active': false,
    'access_allowed': false,
    'user_type': 'CLIENT',
    'full_name': null,
    'job_title': null,
    'active_role_codes': ['client'],
  },
];

Future<void> pumpProvider() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
