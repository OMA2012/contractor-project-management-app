import 'dart:typed_data';

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
      expect(find.text('Client workspace'), findsOneWidget);
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
    this.failList = false,
    this.completion = const DocumentUploadResult(
      uploadId: 'upload-1',
      status: 'FINALIZED',
      reservedDocumentId: 'doc-1',
    ),
  }) : rows = rows ?? [document(isSuperseded: true)],
       ownerAdminPages = ownerAdminPages ?? const [];

  final List<SafeDocument> rows;
  final List<List<SafeDocument>> ownerAdminPages;
  final bool failList;
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
  var _ownerAdminPageIndex = 0;

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
      requestPhotographPreview(documentId);
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
