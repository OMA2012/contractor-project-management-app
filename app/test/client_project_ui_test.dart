import 'dart:async';
import 'dart:typed_data';

import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/app.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/documents/document_file_services.dart';
import 'package:contractor_project_management/src/documents/document_models.dart';
import 'package:contractor_project_management/src/documents/document_providers.dart';
import 'package:contractor_project_management/src/documents/document_repository.dart';
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
        if (functionName == 'current_client_project_completion') {
          return {
            'project_id': params!['p_project_id'],
            'calculated_completion_percent': 40,
            'official_completion_percent': 42,
            'is_overridden': false,
          };
        }
        if (functionName == 'current_client_progress_update_list') {
          return [
            {
              'id': 'update-1',
              'project_id': params!['p_project_id'],
              'milestone_id': 'milestone-1',
              'title': 'Week 1 update',
              'summary': 'Cabinets installed.',
              'reported_completion_percent': 42,
              'published_at': '2026-08-10T00:00:00Z',
            },
          ];
        }
        if (functionName == 'current_client_project_phases') {
          return [
            {
              'id': 'phase-2',
              'project_id': params!['p_project_id'],
              'name': 'Finishes',
              'description': 'Visible finish work.',
              'sequence_no': 2,
              'start_date': '2026-09-01',
              'end_date': null,
            },
          ];
        }
        if (functionName == 'current_client_project_phase_completion') {
          return {
            'project_id': 'project-1',
            'phase_id': params!['p_phase_id'],
            'calculated_completion_percent': '55',
          };
        }
        if (functionName == 'current_client_project_tasks') {
          return [
            {
              'id': 'task-1',
              'project_id': params!['p_project_id'],
              'phase_id': 'phase-2',
              'milestone_id': null,
              'task_number': 'T-001',
              'title': 'Install cabinetry',
              'client_summary': 'Visible task summary.',
              'status': 'IN_PROGRESS',
              'completion_percent': '45',
              'start_date': '2026-09-02',
              'due_date': null,
              'completed_at': null,
            },
          ];
        }
        return [projectRow()];
      },
    );

    final page = await repository.listClientProjects(limit: 25, offset: 50);
    final detail = await repository.getClientProject('project-1');
    final completion = await repository.getClientProjectCompletion('project-1');
    final updates = await repository.listClientProgressUpdates(
      'project-1',
      limit: 10,
      offset: 20,
    );
    final phases = await repository.getClientProjectPhases('project-1');
    final phaseCompletion = await repository.getClientProjectPhaseCompletion(
      'phase-2',
    );
    final tasks = await repository.getClientProjectTasks('project-1');
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
    expect(calls[2], {
      'function': 'current_client_project_completion',
      'p_project_id': 'project-1',
    });
    expect(calls[3], {
      'function': 'current_client_progress_update_list',
      'p_project_id': 'project-1',
      'p_limit': 10,
      'p_offset': 20,
    });
    expect(calls[4], {
      'function': 'current_client_project_phases',
      'p_project_id': 'project-1',
    });
    expect(calls[5], {
      'function': 'current_client_project_phase_completion',
      'p_phase_id': 'phase-2',
    });
    expect(calls[6], {
      'function': 'current_client_project_tasks',
      'p_project_id': 'project-1',
    });
    expect(page.rawCount, 1);
    expect(page.projects.single.projectNumber, 'PRJ-2026-0001');
    expect(detail?.name, 'Kitchen Renovation');
    expect(completion?.projectId, 'project-1');
    expect(updates.items.single.title, 'Week 1 update');
    expect(phases.single.name, 'Finishes');
    expect(phases.single.sequenceNo, 2);
    expect(phaseCompletion?.calculatedCompletionPercent, 55);
    expect(tasks.single.title, 'Install cabinetry');
    expect(tasks.single.completionPercent, 45);
    expect(tasks.single.dueDate, isNull);
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

  test('completion and progress update models map safe fields', () {
    final completion = ClientProjectCompletion.fromJson({
      'project_id': 'project-1',
      'calculated_completion_percent': '64',
      'official_completion_percent': 68,
      'is_overridden': true,
      'override_reason': 'hidden',
      'approved_by': 'hidden-user',
    });
    final update = ClientProgressUpdate.fromJson({
      'id': 'update-1',
      'project_id': 'project-1',
      'milestone_id': 'milestone-hidden',
      'title': 'Published update',
      'summary': 'Visible summary',
      'reported_completion_percent': 44,
      'published_at': '2026-08-10T00:00:00Z',
      'approved_by': 'hidden',
    });

    expect(completion.officialCompletionPercent, 68);
    expect(completion.calculatedCompletionPercent, 64);
    expect(completion.isOverridden, isTrue);
    expect(completion.toString(), isNot(contains('hidden')));
    expect(update.title, 'Published update');
    expect(update.summary, 'Visible summary');
    expect(update.reportedCompletionPercent, 44);
    expect(update.toString(), isNot(contains('approved_by')));
  });

  test('phase and task models map only approved fields', () {
    final phase = ClientProjectPhase.fromJson({
      'id': 'phase-hidden',
      'project_id': 'project-hidden',
      'name': 'Planning',
      'description': 'Visible phase summary',
      'sequence_no': '1',
      'start_date': null,
      'end_date': '2026-08-30',
      'private_notes': 'hidden',
    });
    final task = ClientProjectTask.fromJson({
      'id': 'task-hidden',
      'project_id': 'project-hidden',
      'phase_id': 'phase-hidden',
      'milestone_id': 'milestone-hidden',
      'task_number': 'T-100',
      'title': 'Long visible task',
      'client_summary': null,
      'status': 'BLOCKED',
      'completion_percent': 12,
      'start_date': null,
      'due_date': '2026-09-10',
      'completed_at': null,
      'task_weight': 99,
      'assignment_ids': ['hidden'],
      'staff_name': 'hidden',
      'private_notes': 'hidden',
    });

    expect(phase.name, 'Planning');
    expect(phase.sequenceNo, 1);
    expect(task.taskNumber, 'T-100');
    expect(task.clientSummary, isNull);
    expect(task.milestoneId, 'milestone-hidden');
    expect(task.toString(), isNot(contains('task_weight')));
    expect(task.toString(), isNot(contains('staff')));
    expect(task.toString(), isNot(contains('private_notes')));
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
      await tester.pump();
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
      await tester.pump();
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

  testWidgets('detail renders progress, documents and photographs safely', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final documents = FakeProjectDocumentRepository(
      documentPages: [
        DocumentPage(
          rawCount: 1,
          documents: [
            SafeDocument.fromJson({
              'id': 'doc-1',
              'document_number': 'DOC-001',
              'original_file_name': 'very-long-client-visible-file-name.pdf',
              'mime_type': 'application/pdf',
              'document_type_code': 'CONTRACT',
              'status': 'ACTIVE',
              'file_size_bytes': 2048,
              'uploaded_at': '2026-08-10T00:00:00Z',
            }),
          ],
        ),
      ],
      photographPages: [
        PhotographGalleryPage(
          rawCount: 1,
          items: [
            PhotographGalleryItem.fromClientJson({
              'id': 'photo-1',
              'document_number': 'IMG-001',
              'original_file_name': 'site-photo.jpg',
              'mime_type': 'image/jpeg',
              'document_type_code': 'PROGRESS_PHOTOGRAPH',
              'uploaded_at': '2026-08-10T00:00:00Z',
              'photograph_processing_status': 'READY',
              'thumbnail_available': false,
              'preview_available': true,
            }),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      detailScreen(
        FakeProjectRepository(
          completion: const ClientProjectCompletion(
            projectId: 'project-1',
            calculatedCompletionPercent: 64,
            officialCompletionPercent: 68,
            isOverridden: true,
          ),
          progressPages: [
            ClientProgressUpdatePage(
              rawCount: 1,
              items: [
                ClientProgressUpdate(
                  id: 'update-1',
                  projectId: 'project-1',
                  milestoneId: 'milestone-hidden',
                  title: 'A very long progress update title that wraps safely',
                  summary: 'Visible update summary.',
                  reportedCompletionPercent: 68,
                  publishedAt: DateTime.utc(2026, 8, 10),
                ),
              ],
            ),
          ],
        ),
        documentRepository: documents,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kitchen Renovation'), findsOneWidget);
    expect(find.text('68%'), findsOneWidget);
    expect(find.text('Calculated progress: 64%'), findsOneWidget);
    expect(find.textContaining('progress update title'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('DOC-001'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Project photographs'), findsOneWidget);
    expect(find.textContaining('milestone-hidden'), findsNothing);
    expect(find.textContaining('doc-1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section failures keep project metadata and other sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      detailScreen(
        FakeProjectRepository(failCompletion: true, failProgress: true),
        documentRepository: FakeProjectDocumentRepository(failDocuments: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kitchen Renovation'), findsOneWidget);
    expect(find.text('Project progress could not be loaded.'), findsOneWidget);
    expect(find.text('Progress updates could not be loaded.'), findsOneWidget);
    expect(find.text('Project documents could not be loaded.'), findsOneWidget);
    expect(
      find.text('No project photographs are available yet.'),
      findsOneWidget,
    );
    expect(find.textContaining('SQL'), findsNothing);
  });

  testWidgets(
    'project photograph thumbnail bytes are discarded after account and project changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      final account = MutableCurrentAccountRepository(
        clientRow(id: 'client-a'),
      );
      final firstThumbnail = Completer<SecureDocumentAccess>();
      final projectThumbnail = Completer<SecureDocumentAccess>();
      final documents = FakeProjectDocumentRepository(
        thumbnailCompleters: [firstThumbnail, projectThumbnail],
        photographPages: [
          PhotographGalleryPage(
            rawCount: 1,
            items: [projectPhoto('photo-1', thumbnailAvailable: true)],
          ),
          PhotographGalleryPage(
            rawCount: 1,
            items: [projectPhoto('photo-2', thumbnailAvailable: true)],
          ),
        ],
      );
      final container = detailContainer(
        FakeProjectRepository(),
        documentRepository: documents,
        accountRepository: account,
      );
      addTearDown(container.dispose);
      await container.read(currentAccountProvider.notifier).load();

      await tester.pumpWidget(detailScreenFromContainer(container));
      await tester.pump();
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();
      expect(documents.thumbnailRequests, ['photo-1']);

      account.row = clientRow(id: 'client-b');
      await container.read(currentAccountProvider.notifier).load();
      firstThumbnail.complete(
        SecureDocumentAccess(
          bytes: tinyPngBytes(),
          mimeType: 'image/png',
          safeFileName: 'old.png',
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsNothing);

      await tester.pumpWidget(
        detailScreenFromContainer(container, projectId: 'project-b'),
      );
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();
      await tester.pumpWidget(
        detailScreenFromContainer(container, projectId: 'project-c'),
      );
      await tester.pump();
      projectThumbnail.complete(
        SecureDocumentAccess(
          bytes: tinyPngBytes(),
          mimeType: 'image/png',
          safeFileName: 'project-a.png',
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets(
    'project photograph preview uses secure preview and rejects stale account context',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      final account = MutableCurrentAccountRepository(
        clientRow(id: 'client-a'),
      );
      final preview = Completer<SecureDocumentAccess>();
      final documents = FakeProjectDocumentRepository(
        previewCompleters: [preview],
        photographPages: [
          PhotographGalleryPage(
            rawCount: 1,
            items: [projectPhoto('photo-preview', thumbnailAvailable: false)],
          ),
        ],
      );
      final container = detailContainer(
        FakeProjectRepository(),
        documentRepository: documents,
        accountRepository: account,
      );
      addTearDown(container.dispose);
      await container.read(currentAccountProvider.notifier).load();

      await tester.pumpWidget(detailScreenFromContainer(container));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();
      await tester.tap(find.text('site-photo-photo-preview.jpg'));
      await tester.pump();
      expect(documents.previewRequests, ['photo-preview']);

      account.row = clientRow(id: 'client-b');
      await container.read(currentAccountProvider.notifier).load();
      preview.complete(
        SecureDocumentAccess(
          bytes: tinyPngBytes(),
          mimeType: 'image/png',
          safeFileName: 'preview.png',
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.text('Preview is unavailable.'), findsOneWidget);
    },
  );

  testWidgets(
    'project document Preview reuses secure access and rejects stale preview bytes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      final account = MutableCurrentAccountRepository(
        clientRow(id: 'client-a'),
      );
      final preview = Completer<SecureDocumentAccess>();
      final presenter = FakeDocumentPresenter();
      final documents = FakeProjectDocumentRepository(
        documentAccessCompleters: [preview],
        documentPages: [
          DocumentPage(rawCount: 1, documents: [projectDocument('doc-1')]),
          DocumentPage(rawCount: 1, documents: [projectDocument('doc-1')]),
        ],
      );
      final container = detailContainer(
        FakeProjectRepository(),
        documentRepository: documents,
        presenter: presenter,
        accountRepository: account,
      );
      addTearDown(container.dispose);
      await container.read(currentAccountProvider.notifier).load();

      await tester.pumpWidget(detailScreenFromContainer(container));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Preview'));
      await tester.pump();
      expect(documents.accessRequests, [
        ('doc-1', DocumentAccessPurpose.preview),
      ]);

      account.row = clientRow(id: 'client-b');
      await container.read(currentAccountProvider.notifier).load();
      preview.complete(
        SecureDocumentAccess(
          bytes: tinyPngBytes(),
          mimeType: 'application/pdf',
          safeFileName: 'doc-1.pdf',
        ),
      );
      await tester.pump();
      expect(presenter.previews, isEmpty);
    },
  );

  testWidgets('project document Download reuses secure access', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final presenter = FakeDocumentPresenter();
    final documents = FakeProjectDocumentRepository(
      documentPages: [
        DocumentPage(rawCount: 1, documents: [projectDocument('doc-1')]),
      ],
    );

    await tester.pumpWidget(
      detailScreen(
        FakeProjectRepository(),
        documentRepository: documents,
        presenter: presenter,
      ),
    );
    await tester.pumpAndSettle();
    final downloadButton = find.widgetWithText(OutlinedButton, 'Download');
    if (downloadButton.evaluate().isEmpty) {
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();
    }
    await tester.ensureVisible(downloadButton);
    await tester.pump();
    await tester.tap(downloadButton);
    await tester.pump();
    expect(documents.accessRequests.last, (
      'doc-1',
      DocumentAccessPurpose.download,
    ));
    expect(presenter.downloads.single.safeFileName, 'doc-1.pdf');
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

  testWidgets('detail renders phases tasks grouping and safe values', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      detailScreen(
        FakeProjectRepository(
          phases: [
            phase('phase-b', name: 'Second phase', sequenceNo: 2),
            phase(
              'phase-a',
              name:
                  'A very long first phase name that wraps without exposing ids',
              sequenceNo: 1,
            ),
          ],
          phaseCompletions: {
            'phase-a': const ClientProjectPhaseCompletion(
              projectId: 'project-1',
              phaseId: 'phase-a',
              calculatedCompletionPercent: 33,
            ),
            'phase-b': const ClientProjectPhaseCompletion(
              projectId: 'project-1',
              phaseId: 'phase-b',
              calculatedCompletionPercent: 120,
            ),
          },
          tasks: [
            task('task-a', phaseId: 'phase-a', title: 'Install tile'),
            task('task-b', phaseId: null, title: 'Unphased delivery'),
            task(
              'task-c',
              phaseId: 'phase-not-visible',
              title: 'Visible orphaned task',
              milestoneId: 'milestone-hidden',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Project phases'), findsOneWidget);
    expect(
      tester.getTopLeft(find.textContaining('A very long first phase')).dy,
      lessThan(tester.getTopLeft(find.text('Second phase')).dy),
    );
    expect(find.text('33%'), findsOneWidget);
    expect(find.text('120%'), findsOneWidget);
    expect(find.text('Install tile'), findsOneWidget);
    expect(find.text('Other tasks'), findsOneWidget);
    expect(find.text('Unphased delivery'), findsOneWidget);
    expect(find.text('Visible orphaned task'), findsOneWidget);
    expect(find.textContaining('phase-a'), findsNothing);
    expect(find.textContaining('phase-not-visible'), findsNothing);
    expect(find.textContaining('milestone-hidden'), findsNothing);
    expect(find.textContaining('task-a'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phase task states isolate errors and keep surrounding detail sections',
    (tester) async {
      await tester.pumpWidget(
        detailScreen(
          FakeProjectRepository(failPhases: true),
          documentRepository: FakeProjectDocumentRepository(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kitchen Renovation'), findsOneWidget);
      expect(find.text('Project progress'), findsOneWidget);
      expect(find.text('Project phases could not be loaded.'), findsOneWidget);
      expect(find.text('Recent progress updates'), findsOneWidget);
      expect(find.text('Project documents'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('Project photographs'), findsOneWidget);
      expect(find.textContaining('SQL'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        detailScreen(
          FakeProjectRepository(
            phases: [
              phase('phase-a', name: 'Phase A', sequenceNo: 1),
              phase('phase-b', name: 'Phase B', sequenceNo: 2),
            ],
            failPhaseCompletionIds: {'phase-a'},
            phaseCompletions: {
              'phase-b': const ClientProjectPhaseCompletion(
                projectId: 'project-1',
                phaseId: 'phase-b',
                calculatedCompletionPercent: 70,
              ),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Phase A'), findsOneWidget);
      expect(find.text('Completion unavailable'), findsOneWidget);
      expect(find.text('Phase B'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
    },
  );

  testWidgets('phase task section renders loading empty and null optional fields', (
    tester,
  ) async {
    final phases = Completer<List<ClientProjectPhase>>();
    final tasks = Completer<List<ClientProjectTask>>();
    await tester.pumpWidget(
      detailScreen(
        FakeProjectRepository(
          phaseCompleters: [phases],
          taskCompleters: [tasks],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    phases.complete(const []);
    tasks.complete(const []);
    await tester.pumpAndSettle();
    expect(
      find.text('No project phases or tasks are available yet.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      detailScreen(
        FakeProjectRepository(
          phases: [phase('phase-empty', name: 'Phase with no tasks')],
          tasks: [
            task(
              'task-null',
              phaseId: null,
              title:
                  'Very long task name that wraps cleanly on mobile and laptop layouts',
              clientSummary:
                  'Very long task summary that remains client visible and wraps without overflow.',
              status: null,
              completionPercent: null,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Phase with no tasks'), findsOneWidget);
    expect(find.text('Other tasks'), findsOneWidget);
    expect(find.text('Task completion'), findsOneWidget);
    expect(find.text('Not available'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('phase task stale results and errors are discarded', () async {
    final account = MutableCurrentAccountRepository(clientRow(id: 'client-a'));
    final phasesA = Completer<List<ClientProjectPhase>>();
    final tasksA = Completer<List<ClientProjectTask>>();
    final completionA = Completer<ClientProjectPhaseCompletion?>();
    final phasesB = Completer<List<ClientProjectPhase>>();
    final tasksB = Completer<List<ClientProjectTask>>();
    final repository = FakeProjectRepository(
      phaseCompleters: [phasesA, phasesB],
      taskCompleters: [tasksA, tasksB],
      phaseCompletionCompleters: [completionA],
    );
    final container = clientContainer(repository, accountRepository: account);
    addTearDown(container.dispose);
    container.listen(
      clientProjectPhaseTasksProvider('project-a'),
      (_, _) {},
      fireImmediately: true,
    );
    await container.read(currentAccountProvider.notifier).load();
    final loadA = container
        .read(clientProjectPhaseTasksProvider('project-a').notifier)
        .load();
    await pumpProvider();
    account.row = clientRow(id: 'client-b');
    await container.read(currentAccountProvider.notifier).load();
    await pumpProvider();
    phasesA.complete([phase('phase-stale', name: 'Stale phase')]);
    tasksA.complete([task('task-stale', phaseId: 'phase-stale')]);
    await loadA;
    expect(
      container.read(clientProjectPhaseTasksProvider('project-a')).phases,
      isEmpty,
    );

    final loadB = container
        .read(clientProjectPhaseTasksProvider('project-b').notifier)
        .load();
    phasesB.complete([phase('phase-b', projectId: 'project-b', name: 'Fresh')]);
    tasksB.complete([
      task('task-b', projectId: 'project-b', phaseId: 'phase-b'),
    ]);
    await pumpProvider();
    container.read(authSessionProvider.notifier).signOut();
    completionA.complete(
      const ClientProjectPhaseCompletion(
        projectId: 'project-b',
        phaseId: 'phase-b',
        calculatedCompletionPercent: 88,
      ),
    );
    await loadB;
    expect(
      container.read(clientProjectPhaseTasksProvider('project-b')).phases,
      isEmpty,
    );
    expect(
      container.read(clientProjectPhaseTasksProvider('project-b')).error,
      isNull,
    );
  });
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
      documentRepositoryProvider.overrideWithValue(
        FakeProjectDocumentRepository(),
      ),
      documentContentPresenterProvider.overrideWithValue(
        FakeDocumentPresenter(),
      ),
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
      documentRepositoryProvider.overrideWithValue(
        FakeProjectDocumentRepository(),
      ),
      documentContentPresenterProvider.overrideWithValue(
        FakeDocumentPresenter(),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: ClientProjectListScreen())),
  );
}

Widget detailScreen(
  ProjectRepository repository, {
  String projectId = 'project-1',
  DocumentRepository? documentRepository,
  DocumentContentPresenter? presenter,
  CurrentAccountRepository? accountRepository,
}) {
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'user-a'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        accountRepository ?? MutableCurrentAccountRepository(clientRow()),
      ),
      projectRepositoryProvider.overrideWithValue(repository),
      documentRepositoryProvider.overrideWithValue(
        documentRepository ?? FakeProjectDocumentRepository(),
      ),
      documentContentPresenterProvider.overrideWithValue(
        presenter ?? FakeDocumentPresenter(),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: ClientProjectDetailScreen(projectId: projectId)),
    ),
  );
}

ProviderContainer detailContainer(
  ProjectRepository repository, {
  DocumentRepository? documentRepository,
  DocumentContentPresenter? presenter,
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
      documentRepositoryProvider.overrideWithValue(
        documentRepository ?? FakeProjectDocumentRepository(),
      ),
      documentContentPresenterProvider.overrideWithValue(
        presenter ?? FakeDocumentPresenter(),
      ),
    ],
  );
}

Widget detailScreenFromContainer(
  ProviderContainer container, {
  String projectId = 'project-1',
}) {
  return UncontrolledProviderScope(
    container: container,
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

ClientProjectPhase phase(
  String id, {
  String projectId = 'project-1',
  String name = 'Planning',
  int? sequenceNo = 1,
}) {
  return ClientProjectPhase(
    id: id,
    projectId: projectId,
    name: name,
    description: 'Visible phase description.',
    sequenceNo: sequenceNo,
    startDate: DateTime.utc(2026, 8),
    endDate: DateTime.utc(2026, 9),
  );
}

ClientProjectTask task(
  String id, {
  String projectId = 'project-1',
  String? phaseId,
  String? milestoneId,
  String title = 'Client-visible task',
  String? clientSummary = 'Visible task summary.',
  String? status = 'IN_PROGRESS',
  num? completionPercent = 20,
}) {
  return ClientProjectTask(
    id: id,
    projectId: projectId,
    phaseId: phaseId,
    milestoneId: milestoneId,
    taskNumber: 'T-001',
    title: title,
    clientSummary: clientSummary,
    status: status,
    completionPercent: completionPercent,
    startDate: DateTime.utc(2026, 8, 2),
    dueDate: DateTime.utc(2026, 8, 20),
    completedAt: null,
  );
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

Uint8List tinyPngBytes() => Uint8List.fromList(const [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  248,
  15,
  4,
  0,
  9,
  251,
  3,
  253,
  167,
  180,
  129,
  193,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

SafeDocument projectDocument(String id) {
  return SafeDocument.fromJson({
    'id': id,
    'document_number': 'DOC-001',
    'original_file_name': 'client-file-$id.pdf',
    'mime_type': 'application/pdf',
    'document_type_code': 'CONTRACT',
    'status': 'ACTIVE',
    'file_size_bytes': 2048,
    'uploaded_at': '2026-08-10T00:00:00Z',
  });
}

PhotographGalleryItem projectPhoto(
  String id, {
  required bool thumbnailAvailable,
}) {
  return PhotographGalleryItem.fromClientJson({
    'id': id,
    'document_number': 'IMG-$id',
    'original_file_name': 'site-photo-$id.jpg',
    'mime_type': 'image/jpeg',
    'document_type_code': 'PROGRESS_PHOTOGRAPH',
    'uploaded_at': '2026-08-10T00:00:00Z',
    'photograph_processing_status': 'READY',
    'thumbnail_available': thumbnailAvailable,
    'preview_available': true,
  });
}

class FakeProjectRepository implements ProjectRepository {
  FakeProjectRepository({
    this.pages = const [],
    this.listCompleters = const [],
    this.detailCompleters = const [],
    this.detailProject,
    this.completion,
    this.phases = const [],
    this.tasks = const [],
    this.phaseCompletions = const {},
    this.phaseCompleters = const [],
    this.taskCompleters = const [],
    this.phaseCompletionCompleters = const [],
    this.progressPages = const [],
    this.detailUnavailable = false,
    this.failList = false,
    this.failDetail = false,
    this.failCompletion = false,
    this.failPhases = false,
    this.failTasks = false,
    this.failPhaseCompletionIds = const {},
    this.failProgress = false,
  });

  final List<ClientProjectPage> pages;
  final List<Completer<ClientProjectPage>> listCompleters;
  final List<Completer<ClientProject?>> detailCompleters;
  final ClientProject? detailProject;
  final ClientProjectCompletion? completion;
  final List<ClientProjectPhase> phases;
  final List<ClientProjectTask> tasks;
  final Map<String, ClientProjectPhaseCompletion?> phaseCompletions;
  final List<Completer<List<ClientProjectPhase>>> phaseCompleters;
  final List<Completer<List<ClientProjectTask>>> taskCompleters;
  final List<Completer<ClientProjectPhaseCompletion?>>
  phaseCompletionCompleters;
  final List<ClientProgressUpdatePage> progressPages;
  final bool detailUnavailable;
  final bool failList;
  final bool failDetail;
  final bool failCompletion;
  final bool failPhases;
  final bool failTasks;
  final Set<String> failPhaseCompletionIds;
  final bool failProgress;
  final listOffsets = <int>[];
  final detailIds = <String>[];
  final phaseProjectIds = <String>[];
  final taskProjectIds = <String>[];
  final phaseCompletionIds = <String>[];
  final progressOffsets = <int>[];
  var _pageIndex = 0;
  var _listCompleterIndex = 0;
  var _detailCompleterIndex = 0;
  var _phaseCompleterIndex = 0;
  var _taskCompleterIndex = 0;
  var _phaseCompletionCompleterIndex = 0;

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

  @override
  Future<ClientProjectCompletion?> getClientProjectCompletion(
    String projectId,
  ) async {
    if (failCompletion) throw StateError('SQL backend detail');
    return completion ?? ClientProjectCompletion(projectId: projectId);
  }

  @override
  Future<List<ClientProjectPhase>> getClientProjectPhases(
    String projectId,
  ) async {
    phaseProjectIds.add(projectId);
    if (_phaseCompleterIndex < phaseCompleters.length) {
      return phaseCompleters[_phaseCompleterIndex++].future;
    }
    if (failPhases) throw StateError('SQL backend detail');
    return phases;
  }

  @override
  Future<ClientProjectPhaseCompletion?> getClientProjectPhaseCompletion(
    String phaseId,
  ) async {
    phaseCompletionIds.add(phaseId);
    if (_phaseCompletionCompleterIndex < phaseCompletionCompleters.length) {
      return phaseCompletionCompleters[_phaseCompletionCompleterIndex++].future;
    }
    if (failPhaseCompletionIds.contains(phaseId)) {
      throw StateError('SQL backend detail');
    }
    if (phaseCompletions.containsKey(phaseId)) return phaseCompletions[phaseId];
    return ClientProjectPhaseCompletion(
      projectId: 'project-1',
      phaseId: phaseId,
    );
  }

  @override
  Future<List<ClientProjectTask>> getClientProjectTasks(
    String projectId,
  ) async {
    taskProjectIds.add(projectId);
    if (_taskCompleterIndex < taskCompleters.length) {
      return taskCompleters[_taskCompleterIndex++].future;
    }
    if (failTasks) throw StateError('SQL backend detail');
    return tasks;
  }

  @override
  Future<ClientProgressUpdatePage> listClientProgressUpdates(
    String projectId, {
    int limit = 50,
    int offset = 0,
  }) async {
    progressOffsets.add(offset);
    if (failProgress) throw StateError('SQL backend detail');
    if (progressOffsets.length <= progressPages.length) {
      return progressPages[progressOffsets.length - 1];
    }
    return const ClientProgressUpdatePage(rawCount: 0, items: []);
  }
}

class FakeProjectDocumentRepository implements DocumentRepository {
  FakeProjectDocumentRepository({
    this.documentPages = const [],
    this.photographPages = const [],
    this.documentAccessCompleters = const [],
    this.thumbnailCompleters = const [],
    this.previewCompleters = const [],
    this.failDocuments = false,
    this.failPhotographs = false,
  });

  final List<DocumentPage> documentPages;
  final List<PhotographGalleryPage> photographPages;
  final List<Completer<SecureDocumentAccess>> documentAccessCompleters;
  final List<Completer<SecureDocumentAccess>> thumbnailCompleters;
  final List<Completer<SecureDocumentAccess>> previewCompleters;
  final bool failDocuments;
  final bool failPhotographs;
  final documentOffsets = <int>[];
  final photographOffsets = <int>[];
  final accessRequests = <(String, DocumentAccessPurpose)>[];
  final thumbnailRequests = <String>[];
  final previewRequests = <String>[];
  var _documentPage = 0;
  var _photographPage = 0;
  var _documentAccessCall = 0;
  var _thumbnailCall = 0;
  var _previewCall = 0;

  @override
  Future<DocumentPage> listClientContextFiles({
    required String contextType,
    required String contextId,
    required String contentKind,
    int limit = 50,
    int offset = 0,
  }) {
    expect(contextType, 'PROJECT');
    if (contentKind == 'DOCUMENT') {
      return listClientProjectDocuments(
        contextId,
        limit: limit,
        offset: offset,
      );
    }
    return Future.error(const DocumentFailure('Unsupported context kind.'));
  }

  @override
  Future<DocumentPage> listClientProjectDocuments(
    String projectId, {
    int limit = 50,
    int offset = 0,
  }) async {
    documentOffsets.add(offset);
    if (failDocuments) throw StateError('SQL storage detail');
    if (_documentPage < documentPages.length) {
      return documentPages[_documentPage++];
    }
    return const DocumentPage(rawCount: 0, documents: []);
  }

  @override
  Future<PhotographGalleryPage> listClientProjectPhotographs(
    String projectId, {
    int limit = 50,
    int offset = 0,
  }) async {
    photographOffsets.add(offset);
    if (failPhotographs) throw StateError('SQL storage detail');
    if (_photographPage < photographPages.length) {
      return photographPages[_photographPage++];
    }
    return const PhotographGalleryPage(rawCount: 0, items: []);
  }

  @override
  Future<SecureDocumentAccess> requestDocumentAccess(
    String documentId,
    DocumentAccessPurpose purpose,
  ) async {
    accessRequests.add((documentId, purpose));
    if (_documentAccessCall < documentAccessCompleters.length) {
      return documentAccessCompleters[_documentAccessCall++].future;
    }
    return SecureDocumentAccess(
      bytes: tinyPngBytes(),
      mimeType: 'application/pdf',
      safeFileName: '$documentId.pdf',
    );
  }

  @override
  Future<SecureDocumentAccess> requestPhotographThumbnail(
    String documentId,
  ) async {
    thumbnailRequests.add(documentId);
    if (_thumbnailCall < thumbnailCompleters.length) {
      return thumbnailCompleters[_thumbnailCall++].future;
    }
    return SecureDocumentAccess(
      bytes: tinyPngBytes(),
      mimeType: 'image/png',
      safeFileName: '$documentId.png',
    );
  }

  @override
  Future<SecureDocumentAccess> requestPhotographPreview(
    String documentId,
  ) async {
    previewRequests.add(documentId);
    if (_previewCall < previewCompleters.length) {
      return previewCompleters[_previewCall++].future;
    }
    return SecureDocumentAccess(
      bytes: tinyPngBytes(),
      mimeType: 'image/png',
      safeFileName: '$documentId.png',
    );
  }

  @override
  Future<List<SafeDocument>> listClientDocuments({
    int limit = 50,
    int offset = 0,
  }) async => const [];

  @override
  Future<PhotographGalleryPage> listClientPhotographs({
    int limit = 50,
    int offset = 0,
  }) async => const PhotographGalleryPage(rawCount: 0, items: []);

  @override
  Future<List<SafeDocument>> listOwnerAdminDocuments({
    OwnerAdminDocumentFilters filters = const OwnerAdminDocumentFilters(),
    int limit = 50,
    int offset = 0,
  }) async => const [];

  @override
  Future<SafeDocument> getOwnerAdminDocumentDetail(String documentId) {
    throw const DocumentFailure('Owner/admin detail is unavailable.');
  }

  @override
  Future<DocumentLifecycleMutationResult> archiveOwnerAdminDocument(
    String documentId,
  ) {
    throw const DocumentFailure('Owner/admin mutation is unavailable.');
  }

  @override
  Future<DocumentLifecycleMutationResult> restoreOwnerAdminDocument(
    String documentId,
  ) {
    throw const DocumentFailure('Owner/admin mutation is unavailable.');
  }

  @override
  Future<DocumentLifecycleMutationResult> replaceOwnerAdminDocument({
    required String documentId,
    required String replacementDocumentId,
  }) {
    throw const DocumentFailure('Owner/admin mutation is unavailable.');
  }

  @override
  Future<PhotographGalleryPage> listOwnerAdminPhotographs({
    required OwnerAdminPhotographCategory category,
    int limit = 50,
    int offset = 0,
  }) async => const PhotographGalleryPage(rawCount: 0, items: []);

  @override
  Future<SecureDocumentAccess> requestOwnerAdminOriginalPhotograph(
    String documentId,
  ) => requestPhotographPreview(documentId);

  @override
  Future<DocumentUploadSession> authorizeUpload(DocumentUploadRequest request) {
    throw const DocumentFailure('Upload is unavailable.');
  }

  @override
  Future<void> uploadAuthorizedBytes(
    DocumentUploadSession session,
    Uint8List bytes,
  ) {
    throw const DocumentFailure('Upload is unavailable.');
  }

  @override
  Future<DocumentUploadResult> completeUpload(String uploadId) {
    throw const DocumentFailure('Upload is unavailable.');
  }

  @override
  Future<DocumentScanResult> finalizeScan(String uploadId) {
    throw const DocumentFailure('Upload is unavailable.');
  }

  @override
  Future<PhotographSummary> processPhotograph(String documentId) async {
    return const PhotographSummary(
      processingState: 'READY',
      thumbnailAvailable: true,
      previewAvailable: true,
    );
  }

  @override
  Future<DocumentUploadSession> authorizeClientTransferEvidenceUpload(
    DocumentUploadRequest request,
  ) {
    throw const DocumentFailure('Upload is unavailable.');
  }
}

class FakeDocumentPresenter implements DocumentContentPresenter {
  final previews = <DocumentPresentationContent>[];
  final downloads = <DocumentPresentationContent>[];

  @override
  Future<void> preview(DocumentPresentationContent content) async {
    previews.add(content);
  }

  @override
  Future<void> download(DocumentPresentationContent content) async {
    downloads.add(content);
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
