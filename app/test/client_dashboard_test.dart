import 'dart:async';

import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/app.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/dashboard/client_dashboard_models.dart';
import 'package:contractor_project_management/src/dashboard/client_dashboard_providers.dart';
import 'package:contractor_project_management/src/dashboard/client_dashboard_repository.dart';
import 'package:contractor_project_management/src/notifications/notification_models.dart';
import 'package:contractor_project_management/src/notifications/notification_providers.dart';
import 'package:contractor_project_management/src/notifications/notification_repository.dart';
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
import 'package:go_router/go_router.dart';

const projectIdA = '21000000-0000-4000-8000-000000020001';
const updateIdA = '21000000-0000-4000-8000-000000020002';
const requestIdA = '21000000-0000-4000-8000-000000020003';
const paymentIdA = '21000000-0000-4000-8000-000000020004';
const documentIdA = '21000000-0000-4000-8000-000000020005';
const notificationIdA = '21000000-0000-4000-8000-000000020006';
const relatedIdA = '21000000-0000-4000-8000-000000020007';

void main() {
  test('repository calls exact dashboard RPC contracts', () async {
    final calls = <Map<String, dynamic>>[];
    final repository = SupabaseClientDashboardRepository(
      rpc: (functionName, {params}) async {
        calls.add({'function': functionName, ...?params});
        return switch (functionName) {
          'current_client_dashboard_project_summary' => [projectSummaryRow()],
          'current_client_dashboard_recent_progress' => [progressRow()],
          'current_client_recent_activity' => [activityRow()],
          _ => <Map<String, dynamic>>[],
        };
      },
    );

    await repository.listProjectSummaries(limit: 6);
    await repository.listRecentUpdates(limit: 5);
    await repository.listRecentActivity(limit: 8);

    expect(calls, [
      {
        'function': 'current_client_dashboard_project_summary',
        'p_limit': 6,
        'p_offset': 0,
      },
      {
        'function': 'current_client_dashboard_recent_progress',
        'p_limit': 5,
        'p_offset': 0,
      },
      {
        'function': 'current_client_recent_activity',
        'p_limit': 8,
        'p_offset': 0,
      },
    ]);
  });

  testWidgets('/client renders Client Dashboard for a valid Client', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome, Client Person'), findsOneWidget);
    expect(find.text('Client workspace'), findsNothing);
    expect(find.text('Staff workspace'), findsNothing);
    expect(find.text('Owner'), findsNothing);
  });

  testWidgets('welcome falls back safely when full name is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(accountRows: [clientAccountRow(name: null)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.textContaining('Welcome,'), findsNothing);
  });

  testWidgets('project summary renders and navigates', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.text('PRJ-001'), findsWidgets);
    expect(find.text('Kitchen Renovation'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('42.25% complete'), findsOneWidget);
    expect(find.text('SGD'), findsOneWidget);

    await tester.tap(find.text('Kitchen Renovation'));
    await tester.pumpAndSettle();
    expect(currentUri(tester), '/client/projects/$projectIdA');
  });

  testWidgets('project view-all navigates to /client/projects', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('View all').first);
    await tester.pumpAndSettle();

    expect(currentUri(tester), '/client/projects');
  });

  testWidgets('recent progress renders backend data and navigates to project', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.text('Cabinets installed'), findsOneWidget);
    expect(find.text('PRJ-001 - Kitchen Renovation'), findsOneWidget);
    expect(find.textContaining('55% complete'), findsOneWidget);

    await tester.tap(find.text('Cabinets installed'));
    await tester.pumpAndSettle();
    expect(currentUri(tester), '/client/projects/$projectIdA');
  });

  testWidgets('payments preserve currencies and navigation without totals', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('900.10 SGD'), findsOneWidget);
    expect(find.textContaining('100 USD'), findsOneWidget);
    expect(find.textContaining('1000.10 SGD'), findsOneWidget);
    expect(find.textContaining('50 USD'), findsOneWidget);
    expect(find.textContaining('total', findRichText: true), findsNothing);

    await tester.ensureVisible(find.text('1000.10 SGD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1000.10 SGD'));
    await tester.pumpAndSettle();
    expect(currentUri(tester), '/client/payments/$paymentIdA');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('REQ-001'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('REQ-001'));
    await tester.pumpAndSettle();
    expect(currentUri(tester), '/client/payment-requests/$requestIdA');
  });

  testWidgets(
    'all activity types render and navigate through existing routes',
    (tester) async {
      await tester.pumpWidget(testApp());
      await tester.pumpAndSettle();

      for (final label in [
        'Project update',
        'Document available',
        'Photograph available',
        'Payment request',
        'Payment received',
      ]) {
        expect(find.text(label), findsOneWidget);
      }

      for (final entry in [
        ('Project update', '/client/projects/$projectIdA'),
        ('Document available', '/client/projects/$projectIdA'),
        ('Photograph available', '/client/photographs'),
        ('Payment request', '/client/payment-requests/$requestIdA'),
        ('Payment received', '/client/payments/$paymentIdA'),
      ]) {
        await tester.ensureVisible(find.text(entry.$1));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.$1));
        await tester.pumpAndSettle();
        expect(currentUri(tester), entry.$2);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(testApp());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('files/media actions avoid client document route', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.text('Project documents'), findsOneWidget);
    expect(find.text('Photographs'), findsWidgets);

    await tester.ensureVisible(find.text('Project documents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project documents'));
    await tester.pumpAndSettle();
    expect(currentUri(tester), '/client/projects');
  });

  testWidgets('notifications render without marking read', (tester) async {
    final notifications = FakeNotificationRepository();
    await tester.pumpWidget(testApp(notificationRepository: notifications));
    await tester.pumpAndSettle();

    expect(find.text('Permit uploaded'), findsOneWidget);
    expect(notifications.markReadIds, isEmpty);

    await tester.ensureVisible(find.text('Permit uploaded'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Permit uploaded'));
    await tester.pumpAndSettle();
    expect(currentUri(tester), '/client/notifications/$notificationIdA');
  });

  testWidgets('loading, error, and empty states render', (tester) async {
    final loading = Completer<List<ClientDashboardProjectSummary>>();
    await tester.pumpWidget(
      testApp(
        dashboardRepository: FakeDashboardRepository(
          projectsCompleter: loading,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Welcome, Client Person'), findsOneWidget);
    expect(find.text('Loading...'), findsWidgets);
    loading.complete([projectSummary()]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      testApp(
        dashboardRepository: FakeDashboardRepository(error: StateError('down')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dashboard failed to load.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      testApp(dashboardRepository: FakeDashboardRepository.empty()),
    );
    await tester.pumpAndSettle();
    expect(find.text('No projects are currently available.'), findsOneWidget);
    expect(find.text('No recent updates are available yet.'), findsOneWidget);
    expect(find.text('No recent activity is available yet.'), findsOneWidget);
  });

  testWidgets('mobile and laptop sizes render without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test(
    'stale dashboard result, stale error, and logout are suppressed',
    () async {
      final account = MutableAccountRepository([
        clientAccountRow(id: 'client-a'),
      ]);
      final staleProjects = Completer<List<ClientDashboardProjectSummary>>();
      final staleError = Completer<List<ClientDashboardRecentUpdate>>();
      final repository = FakeDashboardRepository(
        projectsCompleter: staleProjects,
        updatesCompleter: staleError,
        activity: [activity()],
      );
      final container = ProviderContainer(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.authenticated(
              email: 'client@example.test',
              authUserId: 'auth-a',
            ),
          ),
          currentAccountRepositoryProvider.overrideWithValue(account),
          clientDashboardRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(currentAccountProvider.notifier).load();
      container.read(clientDashboardProvider);
      await pumpProvider();

      account.rows = [clientAccountRow(id: 'client-b')];
      await container.read(currentAccountProvider.notifier).load();
      staleProjects.complete([projectSummary(name: 'Old Client Project')]);
      staleError.completeError(StateError('old error'));
      await pumpProvider();

      expect(
        container
            .read(clientDashboardProvider)
            .projects
            .map((project) => project.projectName),
        isNot(contains('Old Client Project')),
      );
      expect(container.read(clientDashboardProvider).error, isNull);

      container.read(authSessionProvider.notifier).signOut();
      await pumpProvider();
      expect(container.read(clientDashboardProvider).projects, isEmpty);
    },
  );

  test('dashboard models reject malformed required UUID fields', () {
    expect(
      () => ClientDashboardProjectSummary.fromJson({
        ...projectSummaryRow(),
        'project_id': 'project-a',
      }),
      throwsA(isA<ClientDashboardParseFailure>()),
    );
    expect(
      () => ClientDashboardRecentUpdate.fromJson({
        ...progressRow(),
        'project_id': 'project-a',
      }),
      throwsA(isA<ClientDashboardParseFailure>()),
    );
    expect(
      () => ClientDashboardRecentUpdate.fromJson({
        ...progressRow(),
        'progress_update_id': 'progress-a',
      }),
      throwsA(isA<ClientDashboardParseFailure>()),
    );
  });

  test('dashboard activity rejects malformed nullable UUID fields', () {
    expect(
      () => ClientDashboardRecentActivity.fromJson({
        ...activityRow(),
        'project_id': 'project-a',
      }),
      throwsA(isA<ClientDashboardParseFailure>()),
    );
    expect(
      () => ClientDashboardRecentActivity.fromJson({
        ...activityRow(type: 'PAYMENT_REQUEST_SENT', relatedId: requestIdA),
        'related_entity_id': 'request-a',
      }),
      throwsA(isA<ClientDashboardParseFailure>()),
    );
    expect(
      () => ClientDashboardRecentActivity.fromJson({
        ...activityRow(type: 'CLIENT_PAYMENT_POSTED', relatedId: paymentIdA),
        'related_entity_id': 'payment-a',
      }),
      throwsA(isA<ClientDashboardParseFailure>()),
    );

    final activity = ClientDashboardRecentActivity.fromJson({
      ...activityRow(),
      'project_id': null,
      'related_entity_id': null,
    });
    expect(activity.projectId, isNull);
    expect(activity.relatedEntityId, isNull);
  });
}

ProviderScope testApp({
  List<Map<String, dynamic>>? accountRows,
  ClientDashboardRepository? dashboardRepository,
  PaymentRepository? paymentRepository,
  NotificationRepository? notificationRepository,
}) {
  return ProviderScope(
    overrides: [
      routerInitialLocationProvider.overrideWithValue('/client'),
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(
          email: 'client@example.test',
          authUserId: 'auth-a',
        ),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        CurrentAccountRepository(
          rpc: (_) async => accountRows ?? [clientAccountRow()],
        ),
      ),
      clientDashboardRepositoryProvider.overrideWithValue(
        dashboardRepository ?? FakeDashboardRepository(),
      ),
      paymentRepositoryProvider.overrideWithValue(
        paymentRepository ?? FakePaymentRepository(),
      ),
      notificationRepositoryProvider.overrideWithValue(
        notificationRepository ?? FakeNotificationRepository(),
      ),
      projectRepositoryProvider.overrideWithValue(FakeProjectRepository()),
    ],
    child: const ContractorProjectManagementApp(),
  );
}

Map<String, dynamic> clientAccountRow({
  String id = 'client-a',
  String? name = 'Client Person',
}) {
  return {
    'application_user_id': id,
    'account_status': 'ACTIVE',
    'is_active': true,
    'access_allowed': true,
    'user_type': 'CLIENT',
    'full_name': name,
    'job_title': null,
    'active_role_codes': ['client'],
  };
}

class MutableAccountRepository extends CurrentAccountRepository {
  MutableAccountRepository(this.rows);

  List<Map<String, dynamic>> rows;

  @override
  Future<CurrentAccount?> loadCurrentAccount() async {
    if (rows.isEmpty) return null;
    return CurrentAccount.fromJson(rows.single);
  }
}

class FakeDashboardRepository implements ClientDashboardRepository {
  FakeDashboardRepository({
    this.error,
    this.projects = const [],
    this.updates = const [],
    this.activity = const [],
    this.projectsCompleter,
    this.updatesCompleter,
  }) {
    if (projects.isEmpty &&
        updates.isEmpty &&
        activity.isEmpty &&
        error == null &&
        projectsCompleter == null &&
        updatesCompleter == null) {
      projects = [projectSummary()];
      updates = [recentUpdate()];
      activity = activities();
    }
  }

  FakeDashboardRepository.empty()
    : projects = const [],
      updates = const [],
      activity = const [],
      error = null,
      projectsCompleter = null,
      updatesCompleter = null;

  final Object? error;
  List<ClientDashboardProjectSummary> projects;
  List<ClientDashboardRecentUpdate> updates;
  List<ClientDashboardRecentActivity> activity;
  final Completer<List<ClientDashboardProjectSummary>>? projectsCompleter;
  final Completer<List<ClientDashboardRecentUpdate>>? updatesCompleter;

  @override
  Future<List<ClientDashboardProjectSummary>> listProjectSummaries({
    int limit = 6,
    int offset = 0,
  }) async {
    if (error != null) throw error!;
    return projectsCompleter?.future ?? projects;
  }

  @override
  Future<List<ClientDashboardRecentUpdate>> listRecentUpdates({
    int limit = 5,
    int offset = 0,
  }) async {
    if (error != null) throw error!;
    return updatesCompleter?.future ?? updates;
  }

  @override
  Future<List<ClientDashboardRecentActivity>> listRecentActivity({
    int limit = 8,
    int offset = 0,
  }) async {
    if (error != null) throw error!;
    return activity;
  }
}

class FakePaymentRepository implements PaymentRepository {
  @override
  Future<ClientPaymentPage> listApprovedPayments({
    int limit = 50,
    int offset = 0,
  }) async {
    return ClientPaymentPage(
      rawCount: 2,
      payments: [
        payment(paymentIdA, 'SGD', '1000.10'),
        payment('21000000-0000-4000-8000-000000020104', 'USD', '50'),
      ],
    );
  }

  @override
  Future<ClientApprovedPayment?> getApprovedPaymentDetail(
    String paymentId,
  ) async => payment(paymentId, 'SGD', '1000.10');

  @override
  Future<ClientPaymentSubmissionResult> submitPayment({
    required String projectId,
    required ExactMoney amount,
    required String currencyCode,
    required DateTime receivedDate,
    String? paymentReference,
    String? payerName,
    String? requestIdentifier,
    String? correlationIdentifier,
  }) async {
    return const ClientPaymentSubmissionResult(clientPaymentId: 'new-payment');
  }

  @override
  Future<ClientPaymentRequestPage> listPaymentRequests({
    int limit = 50,
    int offset = 0,
  }) async {
    return ClientPaymentRequestPage(
      rawCount: 2,
      requests: [
        request(requestIdA, 'SGD', '900.10'),
        request('21000000-0000-4000-8000-000000020103', 'USD', '100'),
      ],
    );
  }

  @override
  Future<ClientPaymentRequest?> viewPaymentRequestDetail(
    String requestId,
  ) async => request(requestId, 'SGD', '900.10');
}

class FakeNotificationRepository implements NotificationRepository {
  final markReadIds = <String>[];

  @override
  Future<ClientNotificationPage> listClientNotifications({
    ClientNotificationStatus? status,
    bool includeArchived = false,
    int limit = 50,
    int offset = 0,
  }) async {
    return ClientNotificationPage(rawCount: 1, items: [notification()]);
  }

  @override
  Future<ClientNotification?> getClientNotification(
    String notificationId,
  ) async => notification();

  @override
  Future<ClientNotification> markClientNotificationRead(
    String notificationId,
  ) async {
    markReadIds.add(notificationId);
    return notification(status: ClientNotificationStatus.read);
  }

  @override
  Future<ClientNotification> markClientNotificationUnread(
    String notificationId,
  ) async => notification();

  @override
  Future<ClientNotification> archiveClientNotification(
    String notificationId,
  ) async => notification(status: ClientNotificationStatus.archived);
}

class FakeProjectRepository implements ProjectRepository {
  @override
  Future<ClientProjectPage> listClientProjects({
    int limit = 50,
    int offset = 0,
  }) async => ClientProjectPage(rawCount: 1, projects: [project()]);

  @override
  Future<ClientProject?> getClientProject(String projectId) async =>
      project(id: projectId);

  @override
  Future<ClientProjectCompletion?> getClientProjectCompletion(
    String projectId,
  ) async => ClientProjectCompletion(
    projectId: projectId,
    officialCompletionPercent: 42,
  );

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
  }) async => const ClientProgressUpdatePage(rawCount: 0, items: []);
}

ClientProject project({String id = projectIdA}) {
  return ClientProject.fromJson({
    'id': id,
    'project_number': 'PRJ-001',
    'name': 'Kitchen Renovation',
    'project_type': 'Renovation',
    'location': 'Singapore',
    'status': 'IN_PROGRESS',
    'start_date': '2026-08-01',
    'end_date': null,
    'reporting_currency_code': 'SGD',
    'client_visible_summary': 'Safe summary',
  });
}

ClientDashboardProjectSummary projectSummary({
  String name = 'Kitchen Renovation',
}) {
  return ClientDashboardProjectSummary(
    projectId: projectIdA,
    projectNumber: 'PRJ-001',
    projectName: name,
    lifecycleStatus: 'IN_PROGRESS',
    officialPercent: 42.25,
    reportingCurrencyCode: 'SGD',
  );
}

ClientDashboardRecentUpdate recentUpdate() {
  return const ClientDashboardRecentUpdate(
    updateId: updateIdA,
    projectId: projectIdA,
    projectNumber: 'PRJ-001',
    projectName: 'Kitchen Renovation',
    title: 'Cabinets installed',
    summary: 'Visible progress summary',
    reportedPercent: 55,
    publishedAt: null,
  );
}

List<ClientDashboardRecentActivity> activities() => [
  activity(type: 'PROGRESS_UPDATE_PUBLISHED', title: 'Published'),
  activity(type: 'DOCUMENT_AVAILABLE', title: 'Contract'),
  activity(type: 'PHOTOGRAPH_AVAILABLE', title: 'Site photo'),
  activity(
    type: 'PAYMENT_REQUEST_SENT',
    title: 'REQ-001',
    relatedId: requestIdA,
  ),
  activity(
    type: 'CLIENT_PAYMENT_POSTED',
    title: 'Payment received',
    relatedId: paymentIdA,
  ),
];

ClientDashboardRecentActivity activity({
  String type = 'PROGRESS_UPDATE_PUBLISHED',
  String title = 'Activity',
  String? relatedId = relatedIdA,
}) {
  return ClientDashboardRecentActivity(
    activityType: type,
    projectId: projectIdA,
    projectNumber: 'PRJ-001',
    title: title,
    message: 'Safe message',
    occurredAt: DateTime.utc(2026, 8, 10),
    relatedEntityType: 'ENTITY',
    relatedEntityId: relatedId,
  );
}

ClientApprovedPayment payment(String id, String currency, String amount) {
  return ClientApprovedPayment.fromJson({
    'client_payment_id': id,
    'project_id': projectIdA,
    'project_number': 'PRJ-001',
    'amount': amount,
    'currency_code': currency,
    'received_date': '2026-08-10',
    'payment_reference': 'Transfer',
    'approved_at': '2026-08-11T00:00:00Z',
    'event_status': 'APPROVED',
    'transaction_status': 'POSTED',
  });
}

ClientPaymentRequest request(String id, String currency, String remaining) {
  return ClientPaymentRequest.fromJson({
    'payment_request_id': id,
    'request_number': id == requestIdA ? 'REQ-001' : 'REQ-002',
    'project_id': projectIdA,
    'project_number': 'PRJ-001',
    'requested_amount': remaining,
    'currency_code': currency,
    'request_date': '2026-08-01',
    'due_date': '2026-08-20',
    'description': 'Milestone request',
    'sent_at': '2026-08-02T00:00:00Z',
    'viewed_at': null,
    'status': 'SENT',
    'effective_status': 'SENT',
    'paid_amount': '0',
    'remaining_amount': remaining,
  });
}

ClientNotification notification({
  ClientNotificationStatus status = ClientNotificationStatus.unread,
}) {
  return ClientNotification(
    id: notificationIdA,
    notificationType: 'DOCUMENT_AVAILABLE',
    title: 'Permit uploaded',
    body: 'A permit document is available.',
    status: status,
    projectId: projectIdA,
    relatedEntityType: 'document',
    relatedEntityId: documentIdA,
    createdAt: DateTime.utc(2026, 8, 10),
  );
}

Map<String, dynamic> projectSummaryRow() => {
  'project_id': projectIdA,
  'project_number': 'PRJ-001',
  'project_name': 'Kitchen Renovation',
  'lifecycle_status': 'IN_PROGRESS',
  'official_completion_percent': '42.25',
  'reporting_currency_code': 'SGD',
};

Map<String, dynamic> progressRow() => {
  'progress_update_id': updateIdA,
  'project_id': projectIdA,
  'project_number': 'PRJ-001',
  'project_name': 'Kitchen Renovation',
  'title': 'Cabinets installed',
  'summary': 'Visible progress summary',
  'reported_completion_percent': '55',
  'published_at': '2026-08-10T00:00:00Z',
};

Map<String, dynamic> activityRow({
  String type = 'PROGRESS_UPDATE_PUBLISHED',
  String? projectId = projectIdA,
  String? relatedId = updateIdA,
}) => {
  'activity_type': type,
  'project_id': projectId,
  'project_number': 'PRJ-001',
  'title': 'Published',
  'message': 'Safe message',
  'occurred_at': '2026-08-10T00:00:00Z',
  'related_entity_type': 'PROGRESS_UPDATE',
  'related_entity_id': relatedId,
};

Future<void> pumpProvider() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

String currentUri(WidgetTester tester) {
  final context = tester.element(find.byType(Scaffold).first);
  return GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
}
