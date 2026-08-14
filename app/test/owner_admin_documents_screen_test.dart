import 'dart:async';
import 'dart:typed_data';

import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/app.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/documents/document_models.dart';
import 'package:contractor_project_management/src/documents/document_file_services.dart';
import 'package:contractor_project_management/src/documents/document_providers.dart';
import 'package:contractor_project_management/src/documents/document_repository.dart';
import 'package:contractor_project_management/src/routing/app_router.dart';
import 'package:contractor_project_management/src/screens/owner_admin_documents_screen.dart';
import 'package:contractor_project_management/src/screens/photograph_gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('owner admin list shows loaded metadata and mobile layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pumpWidget(screenWithRepository(FakeOwnerAdminRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Owner/Admin Documents'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.textContaining('DOC-001'), findsOneWidget);
    expect(find.text('Client visible'), findsOneWidget);
    expect(find.text('ACTIVE'), findsWidgets);
    expect(find.textContaining('storage'), findsNothing);
    expect(find.textContaining('hash'), findsNothing);
  });

  testWidgets('owner admin list shows filters and laptop metadata', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    await tester.pumpWidget(screenWithRepository(FakeOwnerAdminRepository()));
    await tester.pumpAndSettle();

    expect(find.text('All Type'), findsOneWidget);
    expect(find.text('All Visibility'), findsOneWidget);
    expect(find.text('All Status'), findsOneWidget);
    expect(find.textContaining('image/jpeg'), findsOneWidget);

    await tester.tap(find.text('All Visibility'));
    await tester.pump();
    await tester.tap(find.text('PRIVATE').last);
    await tester.pump();

    final repository = latestRepository;
    expect(repository?.lastFilters.clientVisible, isFalse);

    await tester.tap(find.text('All Context'));
    await tester.pump();
    await tester.tap(find.text('Progress update').last);
    await tester.pump();
    expect(repository?.lastFilters.contextType, 'progress_update');
  });

  testWidgets('owner admin list shows empty and error states', (tester) async {
    await tester.pumpWidget(
      screenWithRepository(FakeOwnerAdminRepository(rows: [])),
    );
    await tester.pumpAndSettle();
    expect(find.text('No documents found.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      screenWithRepository(FakeOwnerAdminRepository(failList: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Documents could not be loaded.'), findsOneWidget);
  });

  testWidgets('detail shows safe metadata photograph and access states', (
    tester,
  ) async {
    final repository = FakeOwnerAdminRepository(
      rows: [FakeOwnerAdminRepository.document(isSuperseded: true)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.authenticated(authUserId: 'user-1'),
          ),
          ownerAdminDocumentAccessProvider.overrideWithValue(true),
          documentRepositoryProvider.overrideWithValue(repository),
          documentContentPresenterProvider.overrideWithValue(
            repository.presenter,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: OwnerAdminDocumentDetailScreen(documentId: 'doc-1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('Photograph processing'), findsOneWidget);
    expect(find.text('Superseded'), findsOneWidget);
    expect(find.textContaining('doc-2'), findsNothing);

    await tester.tap(find.widgetWithText(ActionChip, 'Preview'));
    await tester.pumpAndSettle();
    expect(find.text('Preview opened.'), findsOneWidget);
    expect(repository.presenter.previews.single.safeFileName, 'photo.webp');
    expect(repository.presenter.previews.single.mimeType, 'image/webp');
    expect(repository.presenter.previews.single.bytes, Uint8List.fromList([1]));

    await tester.tap(find.widgetWithText(ActionChip, 'Download'));
    await tester.pumpAndSettle();
    expect(find.text('Download started.'), findsOneWidget);
    expect(repository.presenter.downloads.single.safeFileName, 'document.pdf');

    repository.failAccess = true;
    await tester.tap(find.widgetWithText(ActionChip, 'Download'));
    await tester.pumpAndSettle();
    expect(find.text('Document access failed.'), findsOneWidget);
  });

  testWidgets('archive requires confirmation cancel and success refreshes', (
    tester,
  ) async {
    final repository = FakeOwnerAdminRepository(
      rows: [FakeOwnerAdminRepository.document()],
    );
    await tester.pumpWidget(detailWithRepository(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not permanent deletion'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.archiveCalls, isEmpty);

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Archive document'));
    await tester.pumpAndSettle();

    expect(repository.archiveCalls, ['doc-1']);
    expect(repository.detailLoads, greaterThan(1));
    expect(repository.listLoads, greaterThan(0));
    expect(find.text('Document archived.'), findsOneWidget);
  });

  testWidgets('restore explains private state and safe superseded denial', (
    tester,
  ) async {
    final repository = FakeOwnerAdminRepository(
      rows: [FakeOwnerAdminRepository.document(status: 'ARCHIVED')],
    )..restoreError = const DocumentFailure('superseded restore denied');
    await tester.pumpWidget(detailWithRepository(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.textContaining('contractor-private'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore document'));
    await tester.pumpAndSettle();

    expect(repository.restoreCalls, ['doc-1']);
    expect(
      find.text('Superseded documents cannot be restored as current.'),
      findsWidgets,
    );
    expect(find.text('Client visible'), findsOneWidget);
  });

  testWidgets('superseded archived document hides restore affordance', (
    tester,
  ) async {
    final repository = FakeOwnerAdminRepository(
      rows: [
        FakeOwnerAdminRepository.document(
          status: 'ARCHIVED',
          isSuperseded: true,
        ),
      ],
    );
    await tester.pumpWidget(detailWithRepository(repository));
    await tester.pumpAndSettle();

    expect(find.text('Restore'), findsNothing);
    expect(find.text('Superseded'), findsOneWidget);
  });

  testWidgets('replace uses safe selector confirmation and internal ID', (
    tester,
  ) async {
    final repository = FakeOwnerAdminRepository(
      rows: [
        FakeOwnerAdminRepository.document(),
        FakeOwnerAdminRepository.document(
          id: 'doc-2',
          number: 'DOC-002',
          fileName: 'replacement.pdf',
          type: 'INVOICE',
          mime: 'application/pdf',
        ),
      ],
    );
    await tester.pumpWidget(detailWithRepository(repository));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Replace document'));
    await tester.pumpAndSettle();
    expect(find.text('replacement.pdf'), findsOneWidget);
    expect(find.textContaining('DOC-002'), findsOneWidget);
    expect(find.textContaining('doc-2'), findsNothing);
    expect(find.text('photo.jpg'), findsOneWidget);

    await tester.tap(find.text('replacement.pdf'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('will remain retained as historical'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.replaceCalls, isEmpty);

    await tester.tap(find.text('Replace document'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('replacement.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm replacement'));
    await tester.pumpAndSettle();

    expect(repository.replaceCalls.single, ('doc-1', 'doc-2'));
    expect(find.text('Replacement recorded.'), findsOneWidget);
  });

  testWidgets('replace maps context mismatch and cycle errors safely', (
    tester,
  ) async {
    for (final error in const [
      DocumentFailure('context mismatch: internal detail'),
      DocumentFailure('replacement cycle denied by backend'),
    ]) {
      final repository = FakeOwnerAdminRepository(
        rows: [
          FakeOwnerAdminRepository.document(),
          FakeOwnerAdminRepository.document(
            id: 'doc-2',
            number: 'DOC-002',
            fileName: 'replacement.pdf',
          ),
        ],
      )..replaceError = error;
      await tester.pumpWidget(detailWithRepository(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('replacement.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirm replacement'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('internal'), findsNothing);
      expect(
        find.text(
          error.message.contains('context')
              ? 'The replacement document must belong to the same document context.'
              : 'That replacement would create a replacement loop.',
        ),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('replace selector loads candidates outside current list page', (
    tester,
  ) async {
    final mainList = [FakeOwnerAdminRepository.document()];
    final candidateB = FakeOwnerAdminRepository.document(
      id: 'doc-2',
      number: 'DOC-002',
      fileName: 'replacement-b.pdf',
      type: 'INVOICE',
      mime: 'application/pdf',
    );
    final repository = FakeOwnerAdminRepository(
      rows: mainList,
      ownerAdminPages: [
        mainList,
        [candidateB],
      ],
    );
    await tester.pumpWidget(detailWithPreloadedList(repository));
    await tester.pumpAndSettle();
    expect(find.text('replacement-b.pdf'), findsNothing);

    await tester.tap(find.text('Replace document'));
    await tester.pumpAndSettle();

    expect(repository.listRequests.last.limit, 100);
    expect(repository.listRequests.last.offset, 0);
    expect(
      repository.listRequests.last.filters,
      const OwnerAdminDocumentFilters(),
    );
    expect(find.text('replacement-b.pdf'), findsOneWidget);
    expect(find.textContaining('DOC-002'), findsOneWidget);
    expect(find.textContaining('doc-2'), findsNothing);

    await tester.tap(find.text('replacement-b.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm replacement'));
    await tester.pumpAndSettle();

    expect(repository.replaceCalls.single, ('doc-1', 'doc-2'));
  });

  testWidgets('replace selector paginates deduplicates and selects page two', (
    tester,
  ) async {
    final firstPage = [
      for (var i = 0; i < 100; i++)
        FakeOwnerAdminRepository.document(
          id: 'candidate-$i',
          number: 'DOC-${(1000 + i).toString()}',
          fileName: 'candidate-$i.pdf',
          mime: 'application/pdf',
          type: 'GENERAL_DOCUMENT',
        ),
    ];
    final pageTwoCandidate = FakeOwnerAdminRepository.document(
      id: 'doc-page-2',
      number: 'DOC-2000',
      fileName: 'page-two.pdf',
      mime: 'application/pdf',
      type: 'INVOICE',
    );
    final repository = FakeOwnerAdminRepository(
      rows: [FakeOwnerAdminRepository.document()],
      ownerAdminPages: [
        firstPage,
        [firstPage.first, pageTwoCandidate],
      ],
    );
    await tester.pumpWidget(detailWithRepository(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replace document'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Load more documents'),
      600,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Load more documents'), findsOneWidget);
    await tester.tap(find.text('Load more documents'));
    await tester.pumpAndSettle();

    expect(repository.listRequests.last.limit, 100);
    expect(repository.listRequests.last.offset, 100);
    expect(find.text('page-two.pdf'), findsOneWidget);
    expect(find.text('Load more documents'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('candidate-0.pdf'),
      -600,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('candidate-0.pdf'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('page-two.pdf'),
      600,
      scrollable: find.byType(Scrollable).last,
    );

    await tester.tap(find.text('page-two.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm replacement'));
    await tester.pumpAndSettle();

    expect(repository.replaceCalls.single, ('doc-1', 'doc-page-2'));
  });

  testWidgets('upload selects real bytes and shows awaiting scan', (
    tester,
  ) async {
    final repository = FakeOwnerAdminRepository(
      completion: const DocumentUploadResult(
        uploadId: 'upload-1',
        status: 'AWAITING_SCAN',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(repository),
          ownerAdminDocumentAccessProvider.overrideWithValue(true),
          documentFilePickerProvider.overrideWithValue(
            FakeDocumentFilePicker(
              SelectedDocumentFile(
                safeFileName: 'plan.pdf',
                mimeType: 'application/pdf',
                bytes: Uint8List.fromList([7, 8, 9, 10]),
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OwnerAdminDocumentUploadScreen()),
        ),
      ),
    );

    expect(find.text('Project context'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );

    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text('plan.pdf'), findsOneWidget);
    expect(find.text('application/pdf'), findsOneWidget);
    expect(find.text('4 B'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump();
    await tester.tap(find.text('Invoice').last);
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile));
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(repository.lastUploadRequest?.documentTypeCode, 'INVOICE');
    expect(repository.lastUploadRequest?.originalFileName, 'plan.pdf');
    expect(repository.lastUploadRequest?.mimeType, 'application/pdf');
    expect(
      repository.lastUploadRequest?.bytes,
      Uint8List.fromList([7, 8, 9, 10]),
    );
    expect(repository.lastUploadedBytes, Uint8List.fromList([7, 8, 9, 10]));
    expect(repository.lastUploadRequest?.projectId, isNull);
    expect(repository.lastUploadRequest?.clientVisible, isTrue);
    expect(
      find.text('Uploaded - awaiting security verification'),
      findsOneWidget,
    );
  });

  testWidgets('upload clears selected file when replacement picker cancels', (
    tester,
  ) async {
    final repository = FakeOwnerAdminRepository();
    final picker = QueueDocumentFilePicker([
      SelectedDocumentFile(
        safeFileName: 'file-a.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      null,
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(repository),
          ownerAdminDocumentAccessProvider.overrideWithValue(true),
          documentFilePickerProvider.overrideWithValue(picker),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OwnerAdminDocumentUploadScreen()),
        ),
      ),
    );

    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text('file-a.pdf'), findsOneWidget);
    expect(find.text('No file selected.'), findsNothing);

    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text('file-a.pdf'), findsNothing);
    expect(find.text('No file selected.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(repository.uploadRequests, isEmpty);
  });

  testWidgets('upload uses B after A then cancel then B selection', (
    tester,
  ) async {
    final repository = FakeOwnerAdminRepository();
    final bytesA = Uint8List.fromList([1, 1, 1]);
    final bytesB = Uint8List.fromList([9, 8, 7, 6, 5]);
    final picker = QueueDocumentFilePicker([
      SelectedDocumentFile(
        safeFileName: 'file-a.pdf',
        mimeType: 'application/pdf',
        bytes: bytesA,
      ),
      null,
      SelectedDocumentFile(
        safeFileName: 'file-b.png',
        mimeType: 'image/png',
        bytes: bytesB,
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(repository),
          ownerAdminDocumentAccessProvider.overrideWithValue(true),
          documentFilePickerProvider.overrideWithValue(picker),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OwnerAdminDocumentUploadScreen()),
        ),
      ),
    );

    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text('file-a.pdf'), findsOneWidget);
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text('No file selected.'), findsOneWidget);
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text('file-b.png'), findsOneWidget);
    expect(find.text('5 B'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump();
    await tester.tap(find.text('Invoice').last);
    await tester.pump();
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(repository.uploadRequests, hasLength(1));
    expect(repository.lastUploadRequest?.originalFileName, 'file-b.png');
    expect(repository.lastUploadRequest?.mimeType, 'image/png');
    expect(repository.lastUploadRequest?.bytes, bytesB);
    expect(repository.lastUploadedBytes, bytesB);
    expect(repository.lastUploadRequest?.bytes, isNot(bytesA));
  });

  testWidgets('owner admin routes allow staff and deny client', (tester) async {
    await tester.pumpWidget(appWithAccount(activeStaffRow()));
    await tester.pumpAndSettle();
    expect(find.text('Staff workspace'), findsOneWidget);

    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();
    expect(find.text('Owner/Admin Documents'), findsOneWidget);
  });

  for (final route in [
    '/staff/documents',
    '/staff/documents/upload',
    '/staff/documents/doc-1',
  ]) {
    testWidgets('owner admin direct route allowed: $route', (tester) async {
      await tester.pumpWidget(appWithAccount(activeStaffRow(), route));
      await tester.pumpAndSettle();
      expect(
        find.text('Owner/Admin Documents'),
        route == '/staff/documents' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Upload Document'),
        route.endsWith('/upload') ? findsOneWidget : findsNothing,
      );
      if (route.endsWith('/doc-1')) {
        expect(find.text('Photograph processing'), findsOneWidget);
      }
    });

    testWidgets('client direct route denied: $route', (tester) async {
      await tester.pumpWidget(appWithAccount(activeClientRow(), route));
      await tester.pumpAndSettle();
      expect(find.text('Welcome, Client Person'), findsOneWidget);
      expect(find.text('Owner/Admin Documents'), findsNothing);
      expect(find.text('Upload Document'), findsNothing);
    });
  }

  testWidgets('reserved and inactive direct document routes are denied', (
    tester,
  ) async {
    for (final row in [
      reservedRoleRow('project_manager'),
      reservedRoleRow('accountant'),
      reservedRoleRow('site_supervisor'),
      inactiveRow(),
    ]) {
      await tester.pumpWidget(appWithAccount(row, '/staff/documents'));
      await tester.pumpAndSettle();
      expect(find.text('Owner/Admin Documents'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('unauthenticated direct document route goes to login', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.unauthenticated(),
          ),
          routerInitialLocationProvider.overrideWithValue('/staff/documents'),
        ],
        child: const ContractorProjectManagementApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Owner/Admin Documents'), findsNothing);
  });

  testWidgets('logout on owner admin document route redirects safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      appWithAccount(activeStaffRow(), '/staff/documents'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Owner/Admin Documents'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Owner/Admin Documents'), findsNothing);
  });

  testWidgets('photograph gallery renders responsive states and load more', (
    tester,
  ) async {
    final repository = FakeOwnerAdminRepository(
      ownerAdminPhotographPages: [
        PhotographGalleryPage(
          rawCount: 50,
          items: [
            galleryItem('progress-a', 'PROGRESS_PHOTOGRAPH'),
            galleryItem('progress-b', 'PROGRESS_PHOTOGRAPH'),
          ],
        ),
        PhotographGalleryPage(
          rawCount: 1,
          items: [galleryItem('progress-c', 'PROGRESS_PHOTOGRAPH')],
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(1024, 800));
    await tester.pumpWidget(galleryWithRepository(repository));
    await pumpGallery(tester);

    expect(find.text('Photograph Gallery'), findsOneWidget);
    expect(find.text('progress-a.jpg'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Load more'));
    await pumpGallery(tester);
    expect(repository.photographRequests.map((r) => r.offset), [0, 50]);
    expect(find.text('progress-c.jpg'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pumpWidget(galleryWithRepository(FakeOwnerAdminRepository()));
    await pumpGallery(tester);
    expect(find.text('Photograph Gallery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('photograph gallery category empty error and thumbnail states', (
    tester,
  ) async {
    final repository = FakeOwnerAdminRepository(
      ownerAdminPhotographPages: [
        const PhotographGalleryPage(rawCount: 0, items: []),
        PhotographGalleryPage(
          rawCount: 1,
          items: [
            galleryItem(
              'task-pdf',
              'TASK_ATTACHMENT',
              mime: 'application/pdf',
              thumbnail: false,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(galleryWithRepository(repository));
    await pumpGallery(tester);
    expect(find.text('No progress photographs yet.'), findsOneWidget);

    await tester.tap(find.text('Task images'));
    await pumpGallery(tester);
    expect(find.text('task-pdf.jpg'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      galleryWithRepository(FakeOwnerAdminRepository(failPhotographList: true)),
    );
    await pumpGallery(tester);
    expect(find.text('Photographs could not be loaded.'), findsOneWidget);
    expect(find.textContaining('offline'), findsNothing);
  });

  testWidgets('stale preview bytes do not render or enable download', (
    tester,
  ) async {
    final account = MutableCurrentAccountRepository(activeStaffRow());
    final preview = Completer<SecureDocumentAccess>();
    final repository = FakeOwnerAdminRepository(
      previewCompleters: [preview],
      ownerAdminPhotographPages: [
        PhotographGalleryPage(
          rawCount: 1,
          items: [galleryItem('preview-a', 'PROGRESS_PHOTOGRAPH')],
        ),
      ],
    );
    await tester.pumpWidget(
      galleryWithRepository(repository, currentAccountRepository: account),
    );
    await pumpGallery(tester);

    await tester.tap(find.text('preview-a.jpg'));
    await tester.pump();
    expect(repository.previewRequests, ['preview-a']);

    account.row = activeClientRow();
    await ProviderScope.containerOf(
      tester.element(find.byType(PhotographGalleryScreen)),
    ).read(currentAccountProvider.notifier).load();
    await tester.pump();
    preview.complete(
      SecureDocumentAccess(
        bytes: Uint8List.fromList([9, 9, 9]),
        mimeType: 'image/webp',
        safeFileName: 'stale.webp',
      ),
    );
    await pumpGallery(tester);

    expect(find.text('Preview is unavailable.'), findsOneWidget);
    final download = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Download'),
    );
    expect(download.enabled, isFalse);
    expect(repository.presenter.downloads, isEmpty);
  });

  testWidgets('photograph gallery route access is role scoped', (tester) async {
    await tester.pumpWidget(
      appWithAccount(activeStaffRow(), '/staff/photographs'),
    );
    await pumpGallery(tester);
    expect(find.text('Photograph Gallery'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      appWithAccount(activeClientRow(), '/staff/photographs'),
    );
    await pumpGallery(tester);
    expect(find.text('Welcome, Client Person'), findsOneWidget);
    expect(find.text('Photograph Gallery'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      appWithAccount(activeClientRow(), '/client/photographs'),
    );
    await pumpGallery(tester);
    expect(find.text('Photographs'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      appWithAccount(activeStaffRow(), '/client/photographs'),
    );
    await pumpGallery(tester);
    expect(find.text('Staff workspace'), findsOneWidget);
    expect(find.text('Photographs'), findsNothing);
  });
}

FakeOwnerAdminRepository? latestRepository;

Widget screenWithRepository(FakeOwnerAdminRepository repository) {
  latestRepository = repository;
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'user-1'),
      ),
      documentRepositoryProvider.overrideWithValue(repository),
      ownerAdminDocumentAccessProvider.overrideWithValue(true),
      documentContentPresenterProvider.overrideWithValue(repository.presenter),
    ],
    child: const MaterialApp(home: Scaffold(body: OwnerAdminDocumentsScreen())),
  );
}

Widget detailWithRepository(FakeOwnerAdminRepository repository) {
  latestRepository = repository;
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'user-1'),
      ),
      documentRepositoryProvider.overrideWithValue(repository),
      ownerAdminDocumentAccessProvider.overrideWithValue(true),
      documentContentPresenterProvider.overrideWithValue(repository.presenter),
    ],
    child: const MaterialApp(
      home: Scaffold(body: OwnerAdminDocumentDetailScreen(documentId: 'doc-1')),
    ),
  );
}

Widget detailWithPreloadedList(FakeOwnerAdminRepository repository) {
  latestRepository = repository;
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'user-1'),
      ),
      documentRepositoryProvider.overrideWithValue(repository),
      ownerAdminDocumentAccessProvider.overrideWithValue(true),
      documentContentPresenterProvider.overrideWithValue(repository.presenter),
    ],
    child: const MaterialApp(
      home: Scaffold(body: _PreloadedListDetailHarness()),
    ),
  );
}

Widget galleryWithRepository(
  FakeOwnerAdminRepository repository, {
  CurrentAccountRepository? currentAccountRepository,
}) {
  latestRepository = repository;
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(authUserId: 'user-1'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        currentAccountRepository ??
            MutableCurrentAccountRepository(activeStaffRow()),
      ),
      ownerAdminDocumentAccessProvider.overrideWithValue(true),
      documentRepositoryProvider.overrideWithValue(repository),
      documentContentPresenterProvider.overrideWithValue(repository.presenter),
    ],
    child: const MaterialApp(
      home: Scaffold(body: PhotographGalleryScreen.ownerAdmin()),
    ),
  );
}

Future<void> pumpGallery(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

class _PreloadedListDetailHarness extends ConsumerStatefulWidget {
  const _PreloadedListDetailHarness();

  @override
  ConsumerState<_PreloadedListDetailHarness> createState() =>
      _PreloadedListDetailHarnessState();
}

class _PreloadedListDetailHarnessState
    extends ConsumerState<_PreloadedListDetailHarness> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(ownerAdminDocumentListProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const OwnerAdminDocumentDetailScreen(documentId: 'doc-1');
  }
}

ProviderScope appWithAccount(dynamic row, [String initialLocation = '/']) {
  return ProviderScope(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(email: 'person@example.com'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        CurrentAccountRepository(rpc: (_) async => row),
      ),
      documentRepositoryProvider.overrideWithValue(FakeOwnerAdminRepository()),
      routerInitialLocationProvider.overrideWithValue(initialLocation),
    ],
    child: const ContractorProjectManagementApp(),
  );
}

List<Map<String, dynamic>> activeStaffRow() => [
  {
    'application_user_id': '10000000-0000-0000-0000-000000000201',
    'account_status': 'ACTIVE',
    'is_active': true,
    'access_allowed': true,
    'user_type': 'STAFF',
    'full_name': 'Staff Person',
    'job_title': 'Owner',
    'active_role_codes': ['owner_admin'],
  },
];

List<Map<String, dynamic>> reservedRoleRow(String roleCode) => [
  {
    'application_user_id': '10000000-0000-0000-0000-000000000203',
    'account_status': 'ACTIVE',
    'is_active': true,
    'access_allowed': false,
    'user_type': 'STAFF',
    'full_name': 'Reserved Person',
    'job_title': 'Reserved',
    'active_role_codes': [roleCode],
  },
];

List<Map<String, dynamic>> inactiveRow() => [
  {
    'application_user_id': '10000000-0000-0000-0000-000000000204',
    'account_status': 'SUSPENDED',
    'is_active': false,
    'access_allowed': false,
    'user_type': 'STAFF',
    'full_name': null,
    'job_title': null,
    'active_role_codes': ['owner_admin'],
  },
];

List<Map<String, dynamic>> activeClientRow() => [
  {
    'application_user_id': '10000000-0000-0000-0000-000000000202',
    'account_status': 'ACTIVE',
    'is_active': true,
    'access_allowed': true,
    'user_type': 'CLIENT',
    'full_name': 'Client Person',
    'job_title': null,
    'active_role_codes': ['client'],
  },
];

class FakeOwnerAdminRepository implements DocumentRepository {
  FakeOwnerAdminRepository({
    List<SafeDocument>? rows,
    List<List<SafeDocument>>? ownerAdminPages,
    List<PhotographGalleryPage>? ownerAdminPhotographPages,
    List<Completer<SecureDocumentAccess>>? previewCompleters,
    this.failList = false,
    this.failPhotographList = false,
    this.completion = const DocumentUploadResult(
      uploadId: 'upload-1',
      status: 'FINALIZED',
      reservedDocumentId: 'doc-1',
    ),
  }) : rows = rows ?? [document(isSuperseded: true)],
       ownerAdminPages = ownerAdminPages ?? const [],
       ownerAdminPhotographPages = ownerAdminPhotographPages ?? const [],
       previewCompleters = previewCompleters ?? const [];

  final List<SafeDocument> rows;
  final List<List<SafeDocument>> ownerAdminPages;
  final List<PhotographGalleryPage> ownerAdminPhotographPages;
  final List<Completer<SecureDocumentAccess>> previewCompleters;
  final bool failList;
  final bool failPhotographList;
  final DocumentUploadResult completion;
  final presenter = FakeDocumentContentPresenter();
  var failAccess = false;
  var lastFilters = const OwnerAdminDocumentFilters();
  DocumentUploadRequest? lastUploadRequest;
  Uint8List? lastUploadedBytes;
  final uploadRequests = <DocumentUploadRequest>[];

  Object? archiveError;
  Object? restoreError;
  Object? replaceError;
  var detailLoads = 0;
  var listLoads = 0;
  final archiveCalls = <String>[];
  final restoreCalls = <String>[];
  final replaceCalls = <(String, String)>[];
  final listRequests = <OwnerAdminListRequest>[];
  final photographRequests = <PhotographListRequest>[];
  final previewRequests = <String>[];
  var _ownerAdminPageIndex = 0;
  var _ownerAdminPhotographPageIndex = 0;
  var _previewIndex = 0;

  static SafeDocument document({
    String id = 'doc-1',
    String number = 'DOC-001',
    String fileName = 'photo.jpg',
    String mime = 'image/jpeg',
    String type = 'PROGRESS_PHOTOGRAPH',
    String status = 'ACTIVE',
    bool isSuperseded = false,
  }) => SafeDocument.fromJson({
    'id': id,
    'document_number': number,
    'original_file_name': fileName,
    'mime_type': mime,
    'document_type_code': type,
    'status': status,
    'file_size_bytes': 2048,
    'uploaded_at': '2026-08-10T01:00:00Z',
    'client_visible': true,
    'project_id': 'project-1',
    'processing_status': 'READY',
    'thumbnail_available': true,
    'preview_available': true,
    'is_superseded': isSuperseded,
    if (isSuperseded) 'superseded_by_document_id': 'doc-2',
  });

  @override
  Future<List<SafeDocument>> listOwnerAdminDocuments({
    OwnerAdminDocumentFilters filters = const OwnerAdminDocumentFilters(),
    int limit = 50,
    int offset = 0,
  }) async {
    lastFilters = filters;
    listRequests.add(
      OwnerAdminListRequest(filters: filters, limit: limit, offset: offset),
    );
    listLoads++;
    if (_ownerAdminPageIndex < ownerAdminPages.length) {
      return ownerAdminPages[_ownerAdminPageIndex++];
    }
    if (failList) throw StateError('offline');
    return rows;
  }

  @override
  Future<PhotographGalleryPage> listOwnerAdminPhotographs({
    required OwnerAdminPhotographCategory category,
    int limit = 50,
    int offset = 0,
  }) async {
    photographRequests.add(
      PhotographListRequest(category: category, limit: limit, offset: offset),
    );
    if (_ownerAdminPhotographPageIndex < ownerAdminPhotographPages.length) {
      return ownerAdminPhotographPages[_ownerAdminPhotographPageIndex++];
    }
    if (failPhotographList) throw StateError('offline backend detail');
    return PhotographGalleryPage(
      rawCount: rows.length,
      items: rows
          .map(PhotographGalleryItem.fromOwnerAdminDocument)
          .toList(growable: false),
    );
  }

  @override
  Future<SafeDocument> getOwnerAdminDocumentDetail(String documentId) async {
    detailLoads++;
    return rows.first;
  }

  @override
  Future<DocumentLifecycleMutationResult> archiveOwnerAdminDocument(
    String documentId,
  ) async {
    archiveCalls.add(documentId);
    if (archiveError != null) throw archiveError!;
    return DocumentLifecycleMutationResult(
      documentId: documentId,
      status: 'ARCHIVED',
    );
  }

  @override
  Future<DocumentLifecycleMutationResult> restoreOwnerAdminDocument(
    String documentId,
  ) async {
    restoreCalls.add(documentId);
    if (restoreError != null) throw restoreError!;
    return DocumentLifecycleMutationResult(
      documentId: documentId,
      status: 'ACTIVE',
    );
  }

  @override
  Future<DocumentLifecycleMutationResult> replaceOwnerAdminDocument({
    required String documentId,
    required String replacementDocumentId,
  }) async {
    replaceCalls.add((documentId, replacementDocumentId));
    if (replaceError != null) throw replaceError!;
    return DocumentLifecycleMutationResult(
      documentId: documentId,
      replacementDocumentId: replacementDocumentId,
      status: 'ACTIVE',
    );
  }

  @override
  Future<SecureDocumentAccess> requestDocumentAccess(
    String documentId,
    DocumentAccessPurpose purpose,
  ) async {
    if (failAccess) throw const DocumentFailure('Access denied');
    return SecureDocumentAccess(
      bytes: Uint8List.fromList([1]),
      mimeType: 'application/pdf',
      safeFileName: 'document.pdf',
    );
  }

  @override
  Future<SecureDocumentAccess> requestPhotographPreview(
    String documentId,
  ) async {
    previewRequests.add(documentId);
    if (_previewIndex < previewCompleters.length) {
      return previewCompleters[_previewIndex++].future;
    }
    if (failAccess) throw const DocumentFailure('Access denied');
    return SecureDocumentAccess(
      bytes: Uint8List.fromList([1]),
      mimeType: 'image/webp',
      safeFileName: 'photo.webp',
    );
  }

  @override
  Future<DocumentUploadSession> authorizeUpload(
    DocumentUploadRequest request,
  ) async {
    lastUploadRequest = request;
    uploadRequests.add(request);
    return DocumentUploadSession(
      uploadId: 'upload-1',
      expiresAt: DateTime.utc(2026, 8, 10),
      maxFileSizeBytes: 100,
      allowedMimeTypes: const ['application/pdf'],
    );
  }

  @override
  Future<void> uploadAuthorizedBytes(
    DocumentUploadSession session,
    Uint8List bytes,
  ) async {
    lastUploadedBytes = bytes;
  }

  @override
  Future<DocumentUploadResult> completeUpload(String uploadId) async =>
      completion;

  @override
  Future<DocumentUploadSession> authorizeClientTransferEvidenceUpload(
    DocumentUploadRequest request,
  ) {
    throw const DocumentFailure('No generic Client upload path.');
  }

  @override
  Future<List<SafeDocument>> listClientDocuments({
    int limit = 50,
    int offset = 0,
  }) {
    throw const DocumentFailure('No generic Client upload path.');
  }

  @override
  Future<DocumentPage> listClientContextFiles({
    required String contextType,
    required String contextId,
    required String contentKind,
    int limit = 50,
    int offset = 0,
  }) {
    throw const DocumentFailure('No Client context path.');
  }

  @override
  Future<DocumentPage> listClientProjectDocuments(
    String projectId, {
    int limit = 50,
    int offset = 0,
  }) {
    throw const DocumentFailure('No Client project document path.');
  }

  @override
  Future<PhotographGalleryPage> listClientPhotographs({
    int limit = 50,
    int offset = 0,
  }) {
    throw const DocumentFailure('No Client photograph path.');
  }

  @override
  Future<PhotographGalleryPage> listClientProjectPhotographs(
    String projectId, {
    int limit = 50,
    int offset = 0,
  }) {
    throw const DocumentFailure('No Client project photograph path.');
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
  Future<SecureDocumentAccess> requestOwnerAdminOriginalPhotograph(
    String documentId,
  ) => requestPhotographPreview(documentId);

  @override
  Future<SecureDocumentAccess> requestPhotographThumbnail(String documentId) =>
      Future.value(
        SecureDocumentAccess(
          bytes: tinyPngBytes(),
          mimeType: 'image/png',
          safeFileName: 'photo.png',
        ),
      );
}

class OwnerAdminListRequest {
  const OwnerAdminListRequest({
    required this.filters,
    required this.limit,
    required this.offset,
  });

  final OwnerAdminDocumentFilters filters;
  final int limit;
  final int offset;
}

class PhotographListRequest {
  const PhotographListRequest({
    required this.category,
    required this.limit,
    required this.offset,
  });

  final OwnerAdminPhotographCategory category;
  final int limit;
  final int offset;
}

PhotographGalleryItem galleryItem(
  String id,
  String type, {
  String mime = 'image/jpeg',
  bool thumbnail = true,
  bool preview = true,
}) {
  return PhotographGalleryItem.fromOwnerAdminJson({
    'id': id,
    'document_number': 'PHOTO-$id',
    'original_file_name': '$id.jpg',
    'mime_type': mime,
    'file_size_bytes': 2048,
    'document_type_code': type,
    'uploaded_at': '2026-08-10T01:00:00Z',
    'client_visible': true,
    'photograph_processing_status': thumbnail || preview ? 'READY' : 'PENDING',
    'thumbnail_available': thumbnail,
    'preview_available': preview,
  });
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

class FakeDocumentFilePicker implements DocumentFilePicker {
  const FakeDocumentFilePicker(this.file);

  final SelectedDocumentFile? file;

  @override
  Future<SelectedDocumentFile?> pickDocumentFile() async => file;
}

class QueueDocumentFilePicker implements DocumentFilePicker {
  QueueDocumentFilePicker(this.files);

  final List<SelectedDocumentFile?> files;
  var _index = 0;

  @override
  Future<SelectedDocumentFile?> pickDocumentFile() async {
    return files[_index++];
  }
}

class FakeDocumentContentPresenter implements DocumentContentPresenter {
  final previews = <DocumentPresentationContent>[];
  final downloads = <DocumentPresentationContent>[];
  var fail = false;

  @override
  Future<void> preview(DocumentPresentationContent content) async {
    if (fail) throw StateError('present failed');
    previews.add(content);
  }

  @override
  Future<void> download(DocumentPresentationContent content) async {
    if (fail) throw StateError('present failed');
    downloads.add(content);
  }
}

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
