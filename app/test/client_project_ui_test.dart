import 'dart:async';

import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/app.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/projects/project_models.dart';
import 'package:contractor_project_management/src/projects/project_providers.dart';
import 'package:contractor_project_management/src/projects/project_repository.dart';
import 'package:contractor_project_management/src/routing/app_router.dart';
import 'package:contractor_project_management/src/screens/client_project_detail_screen.dart';
import 'package:contractor_project_management/src/screens/client_project_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repository calls exact Client project list and detail RPCs', () async {
    final calls = <Map<String, dynamic>>[];
    final repository = SupabaseProjectRepository(
      rpc: (functionName, {params}) async {
        calls.add({'function': functionName, ...?params});
        if (functionName == 'current_client_project_record') {
          return projectRow(id: params!['p_project_id'] as String);
        }
        return [projectRow()];
      },
    );

    final page = await repository.listClientProjects(limit: 25, offset: 50);
    final detail = await repository.getClientProject('project-1');
    final missing = await SupabaseProjectRepository(
      rpc: (_, {params}) async => <Map<String, dynamic>>[],
    ).getClientProject('missing');

    expect(calls[0], {
      'function': 'current_client_project_records',
      'p_limit': 25,
      'p_offset': 50,
    });
    expect(calls[1], {
      'function': 'current_client_project_record',
      'p_project_id': 'project-1',
    });
    expect(page.rawCount, 1);
    expect(page.projects.single.projectNumber, 'PRJ-2026-0001');
    expect(detail?.name, 'Kitchen Renovation');
    expect(missing, isNull);
  });

  test('project model maps only safe returned fields and fails closed', () {
    final project = ClientProject.fromJson({
      ...projectRow(),
      'client_id': 'hidden-client',
      'internal_notes': 'hidden notes',
      'ledger_account_id': 'hidden-ledger',
    });

    expect(project.id, 'project-1');
    expect(project.location, 'Singapore');
    expect(project.reportingCurrencyCode, 'SGD');
    expect(project.toString(), isNot(contains('hidden')));
    expect(
      () => ClientProject.fromJson({...projectRow(), 'status': 'DELETED'}),
      throwsA(isA<ProjectParseFailure>()),
    );
  });

  test(
    'list pagination uses raw row count and guards concurrent loadMore',
    () async {
      final repository = FakeProjectRepository(
        pages: [
          ClientProjectPage(
            rawCount: 3,
            projects: [project('a'), project('b'), project('a')],
          ),
          ClientProjectPage(rawCount: 1, projects: [project('c')]),
        ],
      );
      final container = clientContainer(repository);
      addTearDown(container.dispose);
      await container.read(currentAccountProvider.notifier).load();

      await container.read(clientProjectListProvider.notifier).load(limit: 3);
      final firstLoadMore = container
          .read(clientProjectListProvider.notifier)
          .loadMore();
      final secondLoadMore = container
          .read(clientProjectListProvider.notifier)
          .loadMore();
      await Future.wait([firstLoadMore, secondLoadMore]);

      expect(repository.listOffsets, [0, 3]);
      expect(
        container.read(clientProjectListProvider).projects.map((e) => e.id),
        ['a', 'b', 'c'],
      );
      expect(container.read(clientProjectListProvider).hasMore, isFalse);
    },
  );

  test(
    'stale list and detail results are discarded after account changes',
    () async {
      final account = MutableCurrentAccountRepository(
        clientRow(id: 'client-a'),
      );
      final list = Completer<ClientProjectPage>();
      final detail = Completer<ClientProject?>();
      final repository = FakeProjectRepository(
        listCompleters: [list],
        detailCompleters: [detail],
      );
      final container = clientContainer(repository, accountRepository: account);
      addTearDown(container.dispose);
      container.listen(
        clientProjectListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        clientProjectDetailProvider('project-a'),
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(currentAccountProvider.notifier).load();

      final listLoad = container
          .read(clientProjectListProvider.notifier)
          .load();
      final detailLoad = container
          .read(clientProjectDetailProvider('project-a').notifier)
          .load();
      await pumpProvider();
      account.row = staffRow();
      await container.read(currentAccountProvider.notifier).load();
      await pumpProvider();

      list.complete(
        ClientProjectPage(rawCount: 1, projects: [project('stale')]),
      );
      detail.complete(project('stale'));
      await listLoad;
      await detailLoad;

      expect(container.read(clientProjectListProvider).projects, isEmpty);
      expect(
        container.read(clientProjectDetailProvider('project-a')).project,
        isNull,
      );
    },
  );

  test('stale list and detail results are discarded after logout', () async {
    final list = Completer<ClientProjectPage>();
    final detail = Completer<ClientProject?>();
    final repository = FakeProjectRepository(
      listCompleters: [list],
      detailCompleters: [detail],
    );
    final container = clientContainer(repository);
    addTearDown(container.dispose);
    container.listen(
      clientProjectListProvider,
      (_, _) {},
      fireImmediately: true,
    );
    container.listen(
      clientProjectDetailProvider('project-a'),
      (_, _) {},
      fireImmediately: true,
    );
    await container.read(currentAccountProvider.notifier).load();

    final listLoad = container.read(clientProjectListProvider.notifier).load();
    final detailLoad = container
        .read(clientProjectDetailProvider('project-a').notifier)
        .load();
    await pumpProvider();
    container.read(authSessionProvider.notifier).signOut();
    await pumpProvider();

    list.complete(ClientProjectPage(rawCount: 1, projects: [project('stale')]));
    detail.complete(project('stale'));
    await listLoad;
    await detailLoad;

    expect(container.read(clientProjectListProvider).projects, isEmpty);
    expect(
      container.read(clientProjectDetailProvider('project-a')).project,
      isNull,
    );
  });

  test(
    'stale list and detail results are discarded after active Client changes',
    () async {
      final account = MutableCurrentAccountRepository(
        clientRow(id: 'client-a'),
      );
      final list = Completer<ClientProjectPage>();
      final detail = Completer<ClientProject?>();
      final repository = FakeProjectRepository(
        listCompleters: [list],
        detailCompleters: [detail],
      );
      final container = clientContainer(repository, accountRepository: account);
      addTearDown(container.dispose);
      container.listen(
        clientProjectListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        clientProjectDetailProvider('project-a'),
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(currentAccountProvider.notifier).load();

      final listLoad = container
          .read(clientProjectListProvider.notifier)
          .load();
      final detailLoad = container
          .read(clientProjectDetailProvider('project-a').notifier)
          .load();
      await pumpProvider();
      account.row = clientRow(id: 'client-b');
      await container.read(currentAccountProvider.notifier).load();
      await pumpProvider();

      list.complete(
        ClientProjectPage(rawCount: 1, projects: [project('client-a')]),
      );
      detail.complete(project('client-a'));
      await listLoad;
      await detailLoad;

      expect(container.read(clientProjectListProvider).projects, isEmpty);
      expect(
        container.read(clientProjectDetailProvider('project-a')).project,
        isNull,
      );
    },
  );

  testWidgets(
    'detail route reloads when projectId changes and ignores stale old result',
    (tester) async {
      final projectALoad = Completer<ClientProject?>();
      final projectBLoad = Completer<ClientProject?>();
      final repository = FakeProjectRepository(
        detailCompleters: [projectALoad, projectBLoad],
      );

      await tester.pumpWidget(detailScreen(repository, projectId: 'project-a'));
      await tester.pump();
      expect(repository.detailIds, ['project-a']);

      await tester.pumpWidget(detailScreen(repository, projectId: 'project-b'));
      await tester.pump();
      expect(repository.detailIds, ['project-a', 'project-b']);
      expect(find.text('Kitchen Renovation'), findsNothing);

      projectALoad.complete(project('project-a', name: 'Project A'));
      await tester.pump();
      expect(find.text('Project A'), findsNothing);

      projectBLoad.complete(project('project-b', name: 'Project B'));
      await tester.pumpAndSettle();
      expect(find.text('Project B'), findsOneWidget);
      expect(find.text('Project A'), findsNothing);
    },
  );

  testWidgets('client project routes are client-only', (tester) async {
    await tester.pumpWidget(appWithAccount(clientRow(), '/client/projects'));
    await tester.pumpAndSettle();
    expect(find.text('Projects'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      appWithAccount(clientRow(), '/client/projects/project-1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kitchen Renovation'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(appWithAccount(staffRow(), '/client/projects'));
    await tester.pumpAndSettle();
    expect(find.text('Staff workspace'), findsOneWidget);
    expect(find.text('Kitchen Renovation'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(appWithoutSession('/client/projects'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(appWithAccount(inactiveRow(), '/client/projects'));
    await tester.pumpAndSettle();
    expect(find.text('Account suspended'), findsOneWidget);
  });

  testWidgets(
    'list UI renders loading empty error data and pagination safely',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      final loadMoreCompleter = Completer<ClientProjectPage>();
      final repository = FakeProjectRepository(
        pages: [
          ClientProjectPage(rawCount: 50, projects: [project('project-1')]),
        ],
        listCompleters: [loadMoreCompleter],
      );
      await tester.pumpWidget(listScreen(repository));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.text('PRJ-2026-0001'), findsOneWidget);
      expect(find.text('Kitchen Renovation'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('Singapore'), findsOneWidget);
      expect(find.text('SGD'), findsOneWidget);
      expect(find.textContaining('project-1'), findsNothing);

      await tester.tap(find.text('Load more'));
      await tester.pump();
      loadMoreCompleter.complete(
        ClientProjectPage(rawCount: 1, projects: [project('project-2')]),
      );
      await tester.pumpAndSettle();
      expect(repository.listOffsets, [0, 50]);
      expect(find.text('All loaded'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        listScreen(FakeProjectRepository(pages: const [])),
      );
      await tester.pumpAndSettle();
      expect(find.text('No projects are available yet.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        listScreen(FakeProjectRepository(failList: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Projects could not be loaded.'), findsOneWidget);
      expect(find.textContaining('backend'), findsNothing);
    },
  );

  testWidgets('detail UI renders safe states and hides raw UUID', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 800));
    await tester.pumpWidget(detailScreen(FakeProjectRepository()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('PRJ-2026-0001'), findsOneWidget);
    expect(find.text('Kitchen Renovation'), findsOneWidget);
    expect(find.text('Reporting currency'), findsOneWidget);
    expect(find.text('SGD'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.textContaining('project-1'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      detailScreen(FakeProjectRepository(detailUnavailable: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Project is unavailable.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      detailScreen(FakeProjectRepository(failDetail: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Project could not be loaded.'), findsOneWidget);
    expect(find.textContaining('SQL'), findsNothing);
  });

  testWidgets(
    'project screens handle mobile and laptop widths without overflow',
    (tester) async {
      final longProject = project(
        'long-id',
        name:
            'Whole-home renovation with an unusually long descriptive project name',
      );
      for (final size in const [Size(360, 800), Size(1440, 900)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          listScreen(
            FakeProjectRepository(
              pages: [
                ClientProjectPage(rawCount: 1, projects: [longProject]),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          detailScreen(FakeProjectRepository(detailProject: longProject)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}

ProviderContainer clientContainer(
  ProjectRepository repository, {
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
      projectRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

Widget listScreen(ProjectRepository repository) {
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'user-a'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        MutableCurrentAccountRepository(clientRow()),
      ),
      projectRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(home: Scaffold(body: ClientProjectListScreen())),
  );
}

Widget detailScreen(
  ProjectRepository repository, {
  String projectId = 'project-1',
}) {
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'user-a'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        MutableCurrentAccountRepository(clientRow()),
      ),
      projectRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      home: Scaffold(body: ClientProjectDetailScreen(projectId: projectId)),
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
      projectRepositoryProvider.overrideWithValue(FakeProjectRepository()),
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

ClientProject project(String id, {String name = 'Kitchen Renovation'}) {
  return ClientProject.fromJson(projectRow(id: id, name: name));
}

Map<String, dynamic> projectRow({
  String id = 'project-1',
  String name = 'Kitchen Renovation',
}) {
  return {
    'id': id,
    'project_number': 'PRJ-2026-0001',
    'name': name,
    'project_type': 'Residential',
    'location': 'Singapore',
    'status': 'ACTIVE',
    'start_date': '2026-08-01',
    'end_date': '2026-12-15',
    'reporting_currency_code': 'SGD',
    'client_visible_summary': 'Cabinetry, tiling, and finishing work.',
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

class FakeProjectRepository implements ProjectRepository {
  FakeProjectRepository({
    this.pages = const [],
    this.listCompleters = const [],
    this.detailCompleters = const [],
    this.detailProject,
    this.detailUnavailable = false,
    this.failList = false,
    this.failDetail = false,
  });

  final List<ClientProjectPage> pages;
  final List<Completer<ClientProjectPage>> listCompleters;
  final List<Completer<ClientProject?>> detailCompleters;
  final ClientProject? detailProject;
  final bool detailUnavailable;
  final bool failList;
  final bool failDetail;
  final listOffsets = <int>[];
  final detailIds = <String>[];
  var _pageIndex = 0;
  var _listCompleterIndex = 0;
  var _detailCompleterIndex = 0;

  @override
  Future<ClientProjectPage> listClientProjects({
    int limit = 50,
    int offset = 0,
  }) async {
    listOffsets.add(offset);
    if (_pageIndex < pages.length) return pages[_pageIndex++];
    if (_listCompleterIndex < listCompleters.length) {
      return listCompleters[_listCompleterIndex++].future;
    }
    if (failList) throw StateError('backend SQL detail');
    return const ClientProjectPage(rawCount: 0, projects: []);
  }

  @override
  Future<ClientProject?> getClientProject(String projectId) async {
    detailIds.add(projectId);
    if (_detailCompleterIndex < detailCompleters.length) {
      return detailCompleters[_detailCompleterIndex++].future;
    }
    if (failDetail) throw StateError('SQL backend detail');
    if (detailUnavailable) return null;
    return detailProject ?? project(projectId);
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
