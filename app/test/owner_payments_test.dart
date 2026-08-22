import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_models.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_providers.dart';
import 'package:contractor_project_management/src/financial_accounts/financial_account_repository.dart';
import 'package:contractor_project_management/src/payments/owner_payment_models.dart';
import 'package:contractor_project_management/src/payments/owner_payment_providers.dart';
import 'package:contractor_project_management/src/payments/owner_payment_repository.dart';
import 'package:contractor_project_management/src/screens/owner_client_payments_screen.dart';
import 'package:contractor_project_management/src/screens/owner_payment_requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Client Payment list and detail render business labels', (
    tester,
  ) async {
    final repository = FakeOwnerPaymentRepository();
    await tester.pumpWidget(paymentList(repository));
    await tester.pumpAndSettle();
    expect(find.textContaining('PRJ-2026-0001 - Villa'), findsOneWidget);
    expect(find.textContaining('project-uuid-1'), findsNothing);

    await tester.pumpWidget(paymentDetail(repository));
    await tester.pumpAndSettle();
    expect(find.text('PRJ-2026-0001 - Villa'), findsOneWidget);
    expect(find.text('CL-000001 - Acme Client'), findsOneWidget);
    expect(find.textContaining('project-uuid-1'), findsNothing);
    expect(find.textContaining('client-uuid-1'), findsNothing);
  });

  testWidgets('Payment Request list and detail render business labels', (
    tester,
  ) async {
    final repository = FakeOwnerPaymentRepository();
    await tester.pumpWidget(requestList(repository));
    await tester.pumpAndSettle();
    expect(find.textContaining('PRJ-2026-0001 - Villa'), findsOneWidget);
    expect(find.textContaining('project-uuid-1'), findsNothing);

    await tester.pumpWidget(requestDetail(repository));
    await tester.pumpAndSettle();
    expect(find.text('PRJ-2026-0001 - Villa'), findsOneWidget);
    expect(find.text('CL-000001 - Acme Client'), findsOneWidget);
    expect(find.textContaining('project-uuid-1'), findsNothing);
    expect(find.textContaining('client-uuid-1'), findsNothing);
  });

  testWidgets('missing payment metadata never renders raw UUIDs', (
    tester,
  ) async {
    final repository = FakeOwnerPaymentRepository()
      ..currentPayment = payment(metadata: false)
      ..currentRequest = request(metadata: false);
    await tester.pumpWidget(paymentDetail(repository));
    await tester.pumpAndSettle();
    expect(find.text('Project unavailable'), findsOneWidget);
    expect(find.text('Client unavailable'), findsOneWidget);
    expect(find.textContaining('project-uuid-1'), findsNothing);
    expect(find.textContaining('client-uuid-1'), findsNothing);

    await tester.pumpWidget(requestDetail(repository));
    await tester.pumpAndSettle();
    expect(find.text('Project unavailable'), findsOneWidget);
    expect(find.text('Client unavailable'), findsOneWidget);
    expect(find.textContaining('project-uuid-1'), findsNothing);
    expect(find.textContaining('client-uuid-1'), findsNothing);
  });

  testWidgets('Project pickers submit their hidden UUIDs internally', (
    tester,
  ) async {
    final repository = FakeOwnerPaymentRepository();
    await tester.binding.setSurfaceSize(const Size(900, 900));
    await tester.pumpWidget(paymentList(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(DropdownButtonFormField<OwnerPaymentProjectOption>),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('PRJ-2026-0001 - Villa - CL-000001 - Acme Client').last,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '25.00',
    );
    await tester.ensureVisible(find.text('Save Draft'));
    await tester.tap(find.text('Save Draft'));
    await tester.pumpAndSettle();
    expect(repository.createdPayment?.projectId, 'project-uuid-1');
    expect(find.textContaining('project-uuid-1'), findsNothing);

    await tester.pumpWidget(requestList(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(DropdownButtonFormField<OwnerPaymentProjectOption>),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('PRJ-2026-0001 - Villa - CL-000001 - Acme Client').last,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '50.00',
    );
    await tester.ensureVisible(find.text('Save Draft'));
    await tester.tap(find.text('Save Draft'));
    await tester.pumpAndSettle();
    expect(repository.createdRequest?.projectId, 'project-uuid-1');
    expect(find.textContaining('project-uuid-1'), findsNothing);
  });

  testWidgets('client-context payment picker isolates Client A and Client B', (
    tester,
  ) async {
    final repository = FakeOwnerPaymentRepository();
    await tester.binding.setSurfaceSize(const Size(900, 900));

    await tester.pumpWidget(paymentList(repository, clientId: 'client-a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(DropdownButtonFormField<OwnerPaymentProjectOption>),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('PRJ-A - Client A Project'), findsWidgets);
    expect(find.textContaining('PRJ-B - Client B Project'), findsNothing);
    expect(find.textContaining('project-a-uuid'), findsNothing);
    expect(repository.lookupClientIds.last, 'client-a');
    await tester.tap(find.textContaining('PRJ-A - Client A Project').last);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Create client payment'))).pop();
    await tester.pumpAndSettle();

    await tester.pumpWidget(paymentList(repository, clientId: 'client-b'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(DropdownButtonFormField<OwnerPaymentProjectOption>),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('PRJ-B - Client B Project'), findsWidgets);
    expect(find.textContaining('PRJ-A - Client A Project'), findsNothing);
    expect(find.textContaining('project-b-uuid'), findsNothing);
    expect(repository.lookupClientIds.last, 'client-b');
  });

  testWidgets('global payment picker retains projects across clients', (
    tester,
  ) async {
    final repository = FakeOwnerPaymentRepository();
    await tester.binding.setSurfaceSize(const Size(900, 900));
    await tester.pumpWidget(paymentList(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(DropdownButtonFormField<OwnerPaymentProjectOption>),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('PRJ-A - Client A Project'), findsWidgets);
    expect(find.textContaining('PRJ-B - Client B Project'), findsWidgets);
    expect(repository.lookupClientIds.last, isNull);
  });

  testWidgets('client payment shows an empty state and disables save', (
    tester,
  ) async {
    final repository = FakeOwnerPaymentRepository()..projectOptions = const [];
    await tester.binding.setSurfaceSize(const Size(900, 900));
    await tester.pumpWidget(paymentList(repository, clientId: 'client-empty'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('No projects available for this client.'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save Draft'),
    );
    expect(save.onPressed, isNull);
  });
}

Widget paymentList(FakeOwnerPaymentRepository repository, {String? clientId}) =>
    scoped(
      repository,
      Scaffold(body: OwnerClientPaymentsScreen(clientId: clientId)),
    );

Widget paymentDetail(FakeOwnerPaymentRepository repository) => scoped(
  repository,
  const Scaffold(
    body: OwnerClientPaymentDetailScreen(financialEventId: 'event-1'),
  ),
);

Widget requestList(FakeOwnerPaymentRepository repository) =>
    scoped(repository, const Scaffold(body: OwnerPaymentRequestsScreen()));

Widget requestDetail(FakeOwnerPaymentRepository repository) => scoped(
  repository,
  const Scaffold(
    body: OwnerPaymentRequestDetailScreen(paymentRequestId: 'request-1'),
  ),
);

Widget scoped(FakeOwnerPaymentRepository repository, Widget child) =>
    ProviderScope(
      overrides: [
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.authenticated(authUserId: 'owner-1'),
        ),
        ownerPaymentAccessProvider.overrideWithValue(true),
        ownerPaymentRepositoryProvider.overrideWithValue(repository),
        ownerFinancialAccountAccessProvider.overrideWithValue(true),
        financialAccountRepositoryProvider.overrideWithValue(
          FakeFinancialAccountRepository(),
        ),
      ],
      child: MaterialApp(home: child),
    );

OwnerClientPayment payment({bool metadata = true}) =>
    OwnerClientPayment.fromJson({
      'client_payment_id': 'payment-1',
      'financial_event_id': 'event-1',
      'event_number': 'FE-000001',
      'financial_transaction_id': null,
      'transaction_number': null,
      'project_id': 'project-uuid-1',
      'client_id': 'client-uuid-1',
      'project_number': metadata ? 'PRJ-2026-0001' : null,
      'project_name': metadata ? 'Villa' : null,
      'client_number': metadata ? 'CL-000001' : null,
      'client_name': metadata ? 'Acme Client' : null,
      'amount': '100.00',
      'currency_code': 'USD',
      'received_date': '2026-08-20',
      'event_status': 'DRAFT',
      'transaction_status': 'DRAFT',
      'is_client_submitted': false,
      'version_number': 1,
    });

OwnerPaymentRequest request({bool metadata = true}) =>
    OwnerPaymentRequest.fromJson({
      'payment_request_id': 'request-1',
      'request_number': 'REQ-000001',
      'project_id': 'project-uuid-1',
      'client_id': 'client-uuid-1',
      'project_number': metadata ? 'PRJ-2026-0001' : null,
      'project_name': metadata ? 'Villa' : null,
      'client_number': metadata ? 'CL-000001' : null,
      'client_name': metadata ? 'Acme Client' : null,
      'requested_amount': '150.00',
      'currency_code': 'USD',
      'request_date': '2026-08-20',
      'due_date': '2026-08-30',
      'status': 'DRAFT',
      'effective_status': 'DRAFT',
      'version_number': 1,
    });

class FakeOwnerPaymentRepository implements OwnerPaymentRepository {
  OwnerClientPayment currentPayment = payment();
  OwnerPaymentRequest currentRequest = request();
  OwnerClientPaymentDraft? createdPayment;
  OwnerPaymentRequestDraft? createdRequest;
  List<String?> lookupClientIds = [];
  List<OwnerPaymentProjectOption> projectOptions = const [
    OwnerPaymentProjectOption(
      projectId: 'project-uuid-1',
      clientId: 'client-uuid-1',
      projectNumber: 'PRJ-2026-0001',
      name: 'Villa',
      clientNumber: 'CL-000001',
      clientName: 'Acme Client',
    ),
    OwnerPaymentProjectOption(
      projectId: 'project-a-uuid',
      clientId: 'client-a',
      projectNumber: 'PRJ-A',
      name: 'Client A Project',
    ),
    OwnerPaymentProjectOption(
      projectId: 'project-b-uuid',
      clientId: 'client-b',
      projectNumber: 'PRJ-B',
      name: 'Client B Project',
    ),
  ];

  @override
  Future<List<OwnerClientPayment>> listPayments() async => [currentPayment];

  @override
  Future<OwnerClientPayment> paymentDetail(String financialEventId) async =>
      currentPayment;

  @override
  Future<List<OwnerPaymentRequest>> listRequests() async => [currentRequest];

  @override
  Future<OwnerPaymentRequest> requestDetail(String paymentRequestId) async =>
      currentRequest;

  @override
  Future<List<OwnerPaymentProjectOption>> projectLookups({
    String? clientId,
  }) async {
    lookupClientIds.add(clientId);
    return projectOptions;
  }

  @override
  Future<OwnerPaymentMutationResult> createPayment(
    OwnerClientPaymentDraft draft,
  ) async {
    createdPayment = draft;
    return const OwnerPaymentMutationResult();
  }

  @override
  Future<OwnerPaymentMutationResult> createRequest(
    OwnerPaymentRequestDraft draft,
  ) async {
    createdRequest = draft;
    return const OwnerPaymentMutationResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFinancialAccountRepository implements FinancialAccountRepository {
  @override
  Future<List<FinancialAccount>> listAccounts() async => const [];

  @override
  Future<List<ExactMoney>> bankTotalsByCurrency() async => const [];

  @override
  Future<List<ExactMoney>> cashTotalsByCurrency() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
