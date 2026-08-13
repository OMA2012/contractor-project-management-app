import 'dart:async';

import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/app.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/notifications/notification_models.dart';
import 'package:contractor_project_management/src/notifications/notification_providers.dart';
import 'package:contractor_project_management/src/notifications/notification_repository.dart';
import 'package:contractor_project_management/src/routing/app_router.dart';
import 'package:contractor_project_management/src/screens/client_notification_detail_screen.dart';
import 'package:contractor_project_management/src/screens/client_notification_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'repository uses exact notification RPC contracts and safe params',
    () async {
      final calls = <Map<String, dynamic>>[];
      final repository = SupabaseNotificationRepository(
        rpc: (functionName, {params}) async {
          calls.add({'function': functionName, ...?params});
          return notificationRow(
            id: params?['p_notification_id'] as String? ?? 'notification-1',
          );
        },
      );

      await repository.listClientNotifications(
        status: ClientNotificationStatus.unread,
        includeArchived: false,
        limit: 25,
        offset: 50,
      );
      await repository.listClientNotifications(
        status: ClientNotificationStatus.archived,
        includeArchived: true,
      );
      await repository.getClientNotification('notification-1');
      await repository.markClientNotificationRead('notification-1');
      await repository.markClientNotificationUnread('notification-1');
      await repository.archiveClientNotification('notification-1');

      expect(calls[0], {
        'function': 'current_notification_list',
        'p_status': 'UNREAD',
        'p_include_archived': false,
        'p_limit': 25,
        'p_offset': 50,
      });
      expect(calls[1]['p_status'], 'ARCHIVED');
      expect(calls[1]['p_include_archived'], isTrue);
      expect(calls[2], {
        'function': 'current_notification_detail',
        'p_notification_id': 'notification-1',
      });
      expect(calls[3]['function'], 'current_mark_notification_read');
      expect(calls[4]['function'], 'current_mark_notification_unread');
      expect(calls[5]['function'], 'current_archive_notification');
      for (final call in calls) {
        expect(call.keys, isNot(contains('recipient_user_id')));
        expect(call.keys, isNot(contains('client_id')));
        expect(call.keys, isNot(contains('application_user_id')));
        expect(call.keys, isNot(contains('auth_user_id')));
      }
    },
  );

  test('model maps safe projection, nullable fields, and exact statuses', () {
    final notification = ClientNotification.fromJson({
      ...notificationRow(
        projectId: null,
        relatedEntityType: null,
        relatedEntityId: null,
        readAt: null,
        archivedAt: null,
      ),
      'recipient_user_id': 'private',
      'payload': {'secret': true},
      'metadata': {'secret': true},
      'audit_user_id': 'private',
    });

    expect(notification.projectId, isNull);
    expect(notification.relatedEntityType, isNull);
    expect(notification.relatedEntityId, isNull);
    expect(notification.readAt, isNull);
    expect(notification.archivedAt, isNull);
    expect(notification.status, ClientNotificationStatus.unread);
    expect(notification.toString(), isNot(contains('private')));
    expect(notification.toString(), isNot(contains('payload')));
    expect(
      () => ClientNotification.fromJson({
        ...notificationRow(),
        'status': 'SNOOZED',
      }),
      throwsA(isA<NotificationParseFailure>()),
    );
  });

  test(
    'list pagination dedupes, advances by raw count, and rejects stale filter',
    () async {
      final unread = Completer<ClientNotificationPage>();
      final repository = FakeNotificationRepository(
        pages: [
          ClientNotificationPage(
            rawCount: 3,
            items: [notice('a'), notice('b'), notice('a')],
          ),
          ClientNotificationPage(rawCount: 1, items: [notice('c')]),
        ],
        listCompleters: [unread],
      );
      final container = notificationContainer(repository);
      addTearDown(container.dispose);
      await container.read(currentAccountProvider.notifier).load();

      await container
          .read(clientNotificationListProvider.notifier)
          .load(limit: 3);
      final first = container
          .read(clientNotificationListProvider.notifier)
          .loadMore();
      final second = container
          .read(clientNotificationListProvider.notifier)
          .loadMore();
      await Future.wait([first, second]);

      expect(repository.offsets, [0, 3]);
      expect(
        container.read(clientNotificationListProvider).items.map((e) => e.id),
        ['a', 'b', 'c'],
      );
      expect(container.read(clientNotificationListProvider).hasMore, isFalse);

      final staleLoad = container
          .read(clientNotificationListProvider.notifier)
          .setFilter(ClientNotificationListFilter.unread);
      await pumpProvider();
      final newLoad = container
          .read(clientNotificationListProvider.notifier)
          .setFilter(ClientNotificationListFilter.archived);
      unread.complete(
        ClientNotificationPage(rawCount: 1, items: [notice('old')]),
      );
      await Future.wait([staleLoad, newLoad]);

      final state = container.read(clientNotificationListProvider);
      expect(state.filter, ClientNotificationListFilter.archived);
      expect(state.items.map((e) => e.id), isNot(contains('old')));
      expect(repository.filters.last, ClientNotificationListFilter.archived);
    },
  );

  test(
    'detail intentional open and mutations use authoritative returned rows',
    () async {
      final repository = FakeNotificationRepository(
        detail: notice('n1', status: ClientNotificationStatus.unread),
        markReadResult: notice('n1', status: ClientNotificationStatus.read),
        markUnreadResult: notice('n1', status: ClientNotificationStatus.unread),
        archiveResult: notice('n1', status: ClientNotificationStatus.archived),
      );
      final container = notificationContainer(repository);
      addTearDown(container.dispose);
      await container.read(currentAccountProvider.notifier).load();

      final controller = container.read(
        clientNotificationDetailProvider('n1').notifier,
      );
      await controller.load();
      await controller.load();
      expect(repository.detailIds, ['n1']);
      expect(repository.markReadIds, ['n1']);
      expect(
        container
            .read(clientNotificationDetailProvider('n1'))
            .notification
            ?.status,
        ClientNotificationStatus.read,
      );

      await controller.markUnread();
      expect(
        container
            .read(clientNotificationDetailProvider('n1'))
            .notification
            ?.status,
        ClientNotificationStatus.unread,
      );
      await controller.archive();
      expect(
        container
            .read(clientNotificationDetailProvider('n1'))
            .notification
            ?.status,
        ClientNotificationStatus.archived,
      );

      final readRepository = FakeNotificationRepository(
        detail: notice('read', status: ClientNotificationStatus.read),
      );
      final readContainer = notificationContainer(readRepository);
      addTearDown(readContainer.dispose);
      await readContainer.read(currentAccountProvider.notifier).load();
      await readContainer
          .read(clientNotificationDetailProvider('read').notifier)
          .load();
      expect(readRepository.markReadIds, isEmpty);

      final archivedRepository = FakeNotificationRepository(
        detail: notice('archived', status: ClientNotificationStatus.archived),
      );
      final archivedContainer = notificationContainer(archivedRepository);
      addTearDown(archivedContainer.dispose);
      await archivedContainer.read(currentAccountProvider.notifier).load();
      await archivedContainer
          .read(clientNotificationDetailProvider('archived').notifier)
          .load();
      expect(archivedRepository.markReadIds, isEmpty);
    },
  );

  test(
    'stale account, route, read result, mutation error, and list error are rejected',
    () async {
      final account = MutableCurrentAccountRepository(
        clientRow(id: 'client-a'),
      );
      final list = Completer<ClientNotificationPage>();
      final detailA = Completer<ClientNotification?>();
      final readA = Completer<ClientNotification>();
      final mutationFailure = Completer<ClientNotification>();
      final repository = FakeNotificationRepository(
        listCompleters: [list],
        detailCompleters: [detailA],
        markReadCompleters: [readA],
        markUnreadCompleters: [mutationFailure],
      );
      final container = notificationContainer(
        repository,
        accountRepository: account,
      );
      addTearDown(container.dispose);
      container.listen(
        clientNotificationListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        clientNotificationDetailProvider('a'),
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(currentAccountProvider.notifier).load();

      final listLoad = container
          .read(clientNotificationListProvider.notifier)
          .load();
      final detailLoad = container
          .read(clientNotificationDetailProvider('a').notifier)
          .load();
      await pumpProvider();
      account.row = clientRow(id: 'client-b');
      await container.read(currentAccountProvider.notifier).load();
      list.completeError(StateError('SQL backend private'));
      detailA.complete(notice('a', title: 'Old title'));
      readA.complete(
        notice('a', title: 'Old title', status: ClientNotificationStatus.read),
      );
      await Future.wait([listLoad, detailLoad]);

      expect(container.read(clientNotificationListProvider).error, isNull);
      expect(
        container.read(clientNotificationDetailProvider('a')).notification,
        isNull,
      );

      final routeRepository = FakeNotificationRepository(
        detailCompleters: [
          Completer<ClientNotification?>(),
          Completer<ClientNotification?>(),
        ],
      );
      final routeContainer = notificationContainer(routeRepository);
      addTearDown(routeContainer.dispose);
      await routeContainer.read(currentAccountProvider.notifier).load();
      final loadA = routeContainer
          .read(clientNotificationDetailProvider('a').notifier)
          .load();
      final loadB = routeContainer
          .read(clientNotificationDetailProvider('b').notifier)
          .load();
      routeRepository.detailCompleters[0].complete(
        notice('a', title: 'A title', status: ClientNotificationStatus.read),
      );
      routeRepository.detailCompleters[1].complete(
        notice('b', title: 'B title', status: ClientNotificationStatus.read),
      );
      await Future.wait([loadA, loadB]);
      expect(
        routeContainer
            .read(clientNotificationDetailProvider('b'))
            .notification
            ?.title,
        'B title',
      );
    },
  );

  testWidgets(
    'list UI renders states, filters, statuses, privacy, and responsiveness',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      await tester.pumpWidget(
        listScreen(
          FakeNotificationRepository(
            pages: [
              ClientNotificationPage(
                rawCount: 1,
                items: [
                  notice(
                    '10000000-0000-0000-0000-000000000001',
                    title:
                        'A very long notification title that wraps safely on mobile',
                    body:
                        'Body preview that remains readable without showing raw identifiers.',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('UNREAD'), findsOneWidget);
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
      expect(find.textContaining('00000000-0000'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(listScreen(FakeNotificationRepository()));
      await tester.pumpAndSettle();
      expect(find.text('No notifications are available.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        listScreen(FakeNotificationRepository(failList: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notifications could not be loaded.'), findsOneWidget);
      expect(find.textContaining('SQL'), findsNothing);
    },
  );

  testWidgets(
    'detail UI actions, project navigation, and direct route guards are safe',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 800));
      final repository = FakeNotificationRepository(
        detail: notice(
          'n1',
          status: ClientNotificationStatus.archived,
          projectId: '10000000-0000-0000-0000-000000000010',
        ),
      );
      await tester.pumpWidget(detailScreen(repository));
      await tester.pumpAndSettle();
      expect(find.text('ARCHIVED'), findsOneWidget);
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Mark unread'), findsNothing);
      expect(find.text('View project'), findsOneWidget);
      expect(find.textContaining('00000000-0000'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        detailScreen(
          FakeNotificationRepository(
            detail: notice(
              'n2',
              status: ClientNotificationStatus.read,
              notificationType: 'PAYMENT',
              relatedEntityType: 'progress_update',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('View project'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        appWithAccount(clientRow(), '/client/notifications'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        appWithAccount(staffRow(), '/client/notifications'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Staff workspace'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(appWithoutSession('/client/notifications/n1'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        appWithAccount(inactiveRow(), '/client/notifications/n1'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Account suspended'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        detailScreen(FakeNotificationRepository(detailUnavailable: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notification is unavailable.'), findsOneWidget);
      expect(find.textContaining('n1'), findsNothing);
    },
  );
}

ProviderContainer notificationContainer(
  NotificationRepository repository, {
  CurrentAccountRepository? accountRepository,
}) {
  return ProviderContainer(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'user-a'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        accountRepository ?? MutableCurrentAccountRepository(clientRow()),
      ),
      notificationRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

Widget listScreen(NotificationRepository repository) {
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'user-a'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        MutableCurrentAccountRepository(clientRow()),
      ),
      notificationRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(
      home: Scaffold(body: ClientNotificationListScreen()),
    ),
  );
}

Widget detailScreen(NotificationRepository repository) {
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'user-a'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        MutableCurrentAccountRepository(clientRow()),
      ),
      notificationRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: ClientNotificationDetailScreen(notificationId: 'n1'),
      ),
    ),
  );
}

ProviderScope appWithAccount(dynamic row, String initialLocation) {
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(email: 'person@example.com'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        CurrentAccountRepository(rpc: (_) async => row),
      ),
      notificationRepositoryProvider.overrideWithValue(
        FakeNotificationRepository(),
      ),
      routerInitialLocationProvider.overrideWithValue(initialLocation),
    ],
    child: const ContractorProjectManagementApp(),
  );
}

ProviderScope appWithoutSession(String initialLocation) {
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

ClientNotification notice(
  String id, {
  ClientNotificationStatus status = ClientNotificationStatus.unread,
  String title = 'Progress update published',
  String body = 'A new progress update is available.',
  String? projectId = 'project-1',
  String notificationType = 'PROGRESS_UPDATE_PUBLISHED',
  String? relatedEntityType = 'progress_update',
}) {
  return ClientNotification.fromJson(
    notificationRow(
      id: id,
      status: status.value,
      title: title,
      body: body,
      projectId: projectId,
      notificationType: notificationType,
      relatedEntityType: relatedEntityType,
    ),
  );
}

Map<String, dynamic> notificationRow({
  String id = 'notification-1',
  String? projectId = 'project-1',
  String notificationType = 'PROGRESS_UPDATE_PUBLISHED',
  String title = 'Progress update published',
  String body = 'A new progress update is available.',
  String status = 'UNREAD',
  String? relatedEntityType = 'progress_update',
  String? relatedEntityId = 'progress-update-1',
  String? createdAt = '2026-08-10T00:00:00Z',
  String? readAt = '2026-08-11T00:00:00Z',
  String? archivedAt,
}) {
  return {
    'id': id,
    'project_id': projectId,
    'notification_type': notificationType,
    'title': title,
    'body': body,
    'status': status,
    'related_entity_type': relatedEntityType,
    'related_entity_id': relatedEntityId,
    'created_at': createdAt,
    'read_at': readAt,
    'archived_at': archivedAt,
  };
}

List<Map<String, dynamic>> clientRow({String id = 'client-person'}) => [
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

class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository({
    this.pages = const [],
    this.listCompleters = const [],
    this.detailCompleters = const [],
    this.markReadCompleters = const [],
    this.markUnreadCompleters = const [],
    this.detail,
    this.markReadResult,
    this.markUnreadResult,
    this.archiveResult,
    this.detailUnavailable = false,
    this.failList = false,
  });

  final List<ClientNotificationPage> pages;
  final List<Completer<ClientNotificationPage>> listCompleters;
  final List<Completer<ClientNotification?>> detailCompleters;
  final List<Completer<ClientNotification>> markReadCompleters;
  final List<Completer<ClientNotification>> markUnreadCompleters;
  final ClientNotification? detail;
  final ClientNotification? markReadResult;
  final ClientNotification? markUnreadResult;
  final ClientNotification? archiveResult;
  final bool detailUnavailable;
  final bool failList;
  final offsets = <int>[];
  final filters = <ClientNotificationListFilter>[];
  final detailIds = <String>[];
  final markReadIds = <String>[];
  final markUnreadIds = <String>[];
  final archiveIds = <String>[];
  var _page = 0;
  var _listCompleter = 0;
  var _detailCompleter = 0;
  var _markReadCompleter = 0;
  var _markUnreadCompleter = 0;

  @override
  Future<ClientNotificationPage> listClientNotifications({
    ClientNotificationStatus? status,
    bool includeArchived = false,
    int limit = 50,
    int offset = 0,
  }) async {
    offsets.add(offset);
    filters.add(
      includeArchived
          ? ClientNotificationListFilter.archived
          : status == ClientNotificationStatus.unread
          ? ClientNotificationListFilter.unread
          : status == ClientNotificationStatus.read
          ? ClientNotificationListFilter.read
          : ClientNotificationListFilter.inbox,
    );
    if (failList) throw StateError('SQL backend private');
    if (_page < pages.length) return pages[_page++];
    if (_listCompleter < listCompleters.length) {
      return listCompleters[_listCompleter++].future;
    }
    return const ClientNotificationPage(rawCount: 0, items: []);
  }

  @override
  Future<ClientNotification?> getClientNotification(String notificationId) {
    detailIds.add(notificationId);
    if (_detailCompleter < detailCompleters.length) {
      return detailCompleters[_detailCompleter++].future;
    }
    if (detailUnavailable) return Future.value(null);
    return Future.value(detail ?? notice(notificationId));
  }

  @override
  Future<ClientNotification> markClientNotificationRead(String notificationId) {
    markReadIds.add(notificationId);
    if (_markReadCompleter < markReadCompleters.length) {
      return markReadCompleters[_markReadCompleter++].future;
    }
    return Future.value(
      markReadResult ??
          notice(notificationId, status: ClientNotificationStatus.read),
    );
  }

  @override
  Future<ClientNotification> markClientNotificationUnread(
    String notificationId,
  ) {
    markUnreadIds.add(notificationId);
    if (_markUnreadCompleter < markUnreadCompleters.length) {
      return markUnreadCompleters[_markUnreadCompleter++].future;
    }
    return Future.value(markUnreadResult ?? notice(notificationId));
  }

  @override
  Future<ClientNotification> archiveClientNotification(String notificationId) {
    archiveIds.add(notificationId);
    return Future.value(
      archiveResult ??
          notice(notificationId, status: ClientNotificationStatus.archived),
    );
  }
}

class MutableCurrentAccountRepository extends CurrentAccountRepository {
  MutableCurrentAccountRepository(this.row);

  List<Map<String, dynamic>> row;

  @override
  Future<CurrentAccount?> loadCurrentAccount() async {
    if (row.isEmpty) return null;
    return CurrentAccount.fromJson(row.single);
  }
}

Future<void> pumpProvider() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
