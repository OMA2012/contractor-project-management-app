import 'dart:async';
import 'dart:typed_data';

import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:contractor_project_management/src/documents/document_models.dart';
import 'package:contractor_project_management/src/documents/document_providers.dart';
import 'package:contractor_project_management/src/documents/document_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('DTO mapping exposes only safe document and photograph fields', () {
    final document = SafeDocument.fromJson({
      'id': 'doc-1',
      'document_number': 'DOC-001',
      'original_file_name': 'bad/name"..jpg',
      'mime_type': 'image/jpeg',
      'document_type_code': 'PROGRESS_PHOTOGRAPH',
      'status': 'ACTIVE',
      'uploaded_at': '2026-08-10T01:00:00Z',
      'processing_status': 'READY',
      'thumbnail_available': true,
      'storage_bucket': 'documents-private',
      'storage_object_key': 'objects/private',
      'sha256_hash': 'secret',
      'scanner_result': 'internal',
    });

    expect(document.id, 'doc-1');
    expect(document.safeDisplayFileName, 'bad_name_.jpg');
    expect(document.photograph?.thumbnailAvailable, isTrue);
    expect(document.photograph?.previewAvailable, isTrue);
    expect(document.toString(), isNot(contains('documents-private')));
    expect(document.toString(), isNot(contains('objects/private')));
    expect(document.toString(), isNot(contains('secret')));
  });

  test('malformed required document data fails closed', () {
    expect(
      () => SafeDocument.fromJson({
        'document_number': 'DOC-001',
        'original_file_name': 'invoice.pdf',
        'mime_type': 'application/pdf',
        'document_type_code': 'INVOICE',
        'status': 'ACTIVE',
      }),
      throwsA(isA<DocumentParseFailure>()),
    );
    expect(
      () => SafeDocument.fromJson(validDocumentRow(status: 'DELETED')),
      throwsA(isA<DocumentParseFailure>()),
    );
  });

  test('malformed required upload result data fails closed', () {
    expect(
      () => DocumentUploadResult.fromJson({'upload_id': 'upload-1'}),
      throwsA(isA<DocumentParseFailure>()),
    );
    expect(
      () => DocumentUploadResult.fromJson({
        'upload_id': 'upload-1',
        'status': 'UPLOADED',
      }),
      throwsA(isA<DocumentParseFailure>()),
    );
  });

  test('client document list calls authenticated client-safe RPC', () async {
    final calls = <String>[];
    final repository = SupabaseDocumentRepository(
      rpc: (functionName, {params}) async {
        calls.add(functionName);
        return [validDocumentRow()];
      },
    );

    final documents = await repository.listClientDocuments();

    expect(calls, ['current_client_document_list']);
    expect(documents.single.safeDisplayFileName, 'invoice.pdf');
  });

  test('owner admin list maps filters and pagination to safe RPC', () async {
    final calls = <Map<String, dynamic>>[];
    final repository = SupabaseDocumentRepository(
      rpc: (functionName, {params}) async {
        calls.add({'function': functionName, ...?params});
        return [validDocumentRow()];
      },
    );

    final documents = await repository.listOwnerAdminDocuments(
      filters: const OwnerAdminDocumentFilters(
        projectId: 'project-1',
        documentTypeCode: 'INVOICE',
        clientVisible: true,
        status: 'ACTIVE',
        contextType: 'project',
      ),
      limit: 25,
      offset: 50,
    );

    expect(documents.single.documentNumber, 'DOC-001');
    expect(calls.single, {
      'function': 'owner_admin_document_list',
      'p_limit': 25,
      'p_offset': 50,
      'p_project_id': 'project-1',
      'p_document_type_code': 'INVOICE',
      'p_client_visible': true,
      'p_status': 'ACTIVE',
      'p_context_type': 'project',
    });
  });

  test('owner admin context filters use migration 1177 backend values', () {
    for (final value in const [
      'client',
      'project',
      'task',
      'progress_update',
      'client_payment',
    ]) {
      expect(
        OwnerAdminDocumentFilters(
          contextType: value,
        ).toRpcParams(limit: 50, offset: 0)['p_context_type'],
        value,
      );
    }
  });

  test(
    'owner admin detail maps safe RPC and rejects malformed response',
    () async {
      final calls = <Map<String, dynamic>>[];
      final repository = SupabaseDocumentRepository(
        rpc: (functionName, {params}) async {
          calls.add({'function': functionName, ...?params});
          return validDocumentRow();
        },
      );

      final document = await repository.getOwnerAdminDocumentDetail('doc-1');

      expect(document.safeDisplayFileName, 'invoice.pdf');
      expect(calls.single, {
        'function': 'owner_admin_document_detail',
        'p_document_id': 'doc-1',
      });

      final malformed = SupabaseDocumentRepository(
        rpc: (_, {params}) async => {'id': 'doc-1'},
      );
      expect(
        malformed.getOwnerAdminDocumentDetail('doc-1'),
        throwsA(isA<DocumentParseFailure>()),
      );
    },
  );

  test('owner admin lifecycle mutations call approved RPCs safely', () async {
    final calls = <Map<String, dynamic>>[];
    final repository = SupabaseDocumentRepository(
      rpc: (functionName, {params}) async {
        calls.add({'function': functionName, ...?params});
        return {
          'document_id':
              params?['p_document_id'] ??
              params?['p_superseded_document_id'] ??
              'doc-1',
          'replacement_document_id': params?['p_replacement_document_id'],
          'request_id': params?['p_request_identifier'],
          'status': functionName == 'owner_admin_archive_document'
              ? 'ARCHIVED'
              : 'ACTIVE',
        };
      },
    );

    final archive = await repository.archiveOwnerAdminDocument('doc-1');
    final restore = await repository.restoreOwnerAdminDocument('doc-1');
    final replace = await repository.replaceOwnerAdminDocument(
      documentId: 'doc-1',
      replacementDocumentId: 'doc-2',
    );

    expect(archive.status, 'ARCHIVED');
    expect(restore.requestId, isNotEmpty);
    expect(replace.replacementDocumentId, 'doc-2');
    expect(calls[0], {
      'function': 'owner_admin_archive_document',
      'p_document_id': 'doc-1',
    });
    expect(calls[1]['function'], 'owner_admin_restore_document');
    expect(calls[1]['p_document_id'], 'doc-1');
    expect(calls[1]['p_request_identifier'], isA<String>());
    expect(calls[1].containsKey('p_request_id'), isFalse);
    expect(calls[2]['function'], 'owner_admin_replace_document');
    expect(calls[2]['p_superseded_document_id'], 'doc-1');
    expect(calls[2]['p_replacement_document_id'], 'doc-2');
    expect(calls[2]['p_request_identifier'], isA<String>());
    expect(calls[2].containsKey('p_document_id'), isFalse);
    expect(calls[2].containsKey('p_request_id'), isFalse);
  });

  test('malformed lifecycle mutation response fails closed', () async {
    final repository = SupabaseDocumentRepository(
      rpc: (_, {params}) async => {'document_id': 'doc-1'},
    );

    expect(
      repository.archiveOwnerAdminDocument('doc-1'),
      throwsA(isA<DocumentParseFailure>()),
    );
  });

  test('owner admin safe models do not expose technical fields', () {
    final document = SafeDocument.fromJson({
      ...validDocumentRow(),
      'storage_bucket': 'bucket',
      'storage_key': 'key',
      'sha256_hash': 'hash',
      'signed_url': 'token',
      'service_role': 'service-role',
    });

    expect(document.toString(), isNot(contains('bucket')));
    expect(document.toString(), isNot(contains('key')));
    expect(document.toString(), isNot(contains('hash')));
    expect(document.toString(), isNot(contains('token')));
    expect(document.toString(), isNot(contains('service-role')));
  });

  test(
    'binary document access preserves bytes MIME and safe filename',
    () async {
      final bytes = Uint8List.fromList([0, 159, 146, 150, 255]);
      final accessClient = FakeAccessClient(
        response: DocumentAccessResponse(
          statusCode: 200,
          bytes: bytes,
          headers: {
            'content-type': 'image/webp; charset=binary',
            'content-disposition': 'inline; filename="bad/name.webp"',
          },
        ),
      );
      final repository = SupabaseDocumentRepository(accessClient: accessClient);

      final access = await repository.requestPhotographPreview('doc-1');

      expect(access.bytes, bytes);
      expect(access.mimeType, 'image/webp');
      expect(access.safeFileName, 'bad_name.webp');
      expect(access.toString(), isNot(contains('content-disposition')));
    },
  );

  test('binary document access safely handles missing filename', () async {
    final repository = SupabaseDocumentRepository(
      accessClient: FakeAccessClient(
        response: DocumentAccessResponse(
          statusCode: 200,
          bytes: Uint8List.fromList([1]),
          headers: {'content-type': 'application/pdf'},
        ),
      ),
    );

    final access = await repository.requestDocumentAccess(
      'doc-1',
      DocumentAccessPurpose.download,
    );

    expect(access.safeFileName, 'doc-1');
  });

  test('binary document access fails closed for errors and malformed data', () {
    expect(
      SupabaseDocumentRepository(
        accessClient: FakeAccessClient(
          response: DocumentAccessResponse(
            statusCode: 403,
            bytes: Uint8List.fromList([1]),
            headers: {'content-type': 'application/json'},
          ),
        ),
      ).requestPhotographThumbnail('doc-1'),
      throwsA(isA<DocumentFailure>()),
    );
    expect(
      SupabaseDocumentRepository(
        accessClient: FakeAccessClient(
          response: DocumentAccessResponse(
            statusCode: 200,
            bytes: Uint8List(0),
            headers: {'content-type': 'image/webp'},
          ),
        ),
      ).requestPhotographThumbnail('doc-1'),
      throwsA(isA<DocumentFailure>()),
    );
    expect(
      SupabaseDocumentRepository(
        accessClient: FakeAccessClient(
          response: DocumentAccessResponse(
            statusCode: 200,
            bytes: Uint8List.fromList([1]),
            headers: const {},
          ),
        ),
      ).requestPhotographThumbnail('doc-1'),
      throwsA(isA<DocumentFailure>()),
    );
  });

  test('binary transport sends current authenticated token', () async {
    var token = 'token-A';
    late http.Request captured;
    final client = SupabaseBinaryDocumentAccessClient(
      functionsUrl: 'https://example.supabase.co/functions/v1',
      anonKey: 'anon-key',
      accessTokenProvider: () async => token,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'application/pdf'},
        );
      }),
    );

    await client.post('document-access', {'document_id': 'doc-1'});

    expect(captured.url.toString(), endsWith('/document-access'));
    expect(captured.headers['apikey'], 'anon-key');
    expect(captured.headers['Authorization'], 'Bearer token-A');
  });

  test('binary transport resolves token on every request', () async {
    var token = 'token-A';
    final authorizations = <String?>[];
    final client = SupabaseBinaryDocumentAccessClient(
      functionsUrl: 'https://example.supabase.co/functions/v1',
      anonKey: 'anon-key',
      accessTokenProvider: () async => token,
      httpClient: MockClient((request) async {
        authorizations.add(request.headers['Authorization']);
        return http.Response.bytes(
          [1],
          200,
          headers: {'content-type': 'image/webp'},
        );
      }),
    );

    await client.post('document-access', {'document_id': 'doc-a'});
    token = 'token-B';
    await client.post('document-access', {'document_id': 'doc-b'});
    token = 'refreshed-token';
    await client.post('document-access', {'document_id': 'doc-b'});

    expect(authorizations, [
      'Bearer token-A',
      'Bearer token-B',
      'Bearer refreshed-token',
    ]);
  });

  test(
    'binary transport fails after logout without reusing old token',
    () async {
      String? token = 'token-A';
      var callCount = 0;
      final client = SupabaseBinaryDocumentAccessClient(
        functionsUrl: 'https://example.supabase.co/functions/v1',
        anonKey: 'anon-key',
        accessTokenProvider: () async => token,
        httpClient: MockClient((request) async {
          callCount++;
          return http.Response.bytes(
            [1],
            200,
            headers: {'content-type': 'image/webp'},
          );
        }),
      );

      await client.post('document-access', {'document_id': 'doc-a'});
      token = null;

      await expectLater(
        client.post('document-access', {'document_id': 'doc-b'}),
        throwsA(
          isA<DocumentFailure>().having(
            (failure) => failure.toString(),
            'message',
            isNot(contains('token-A')),
          ),
        ),
      );
      expect(callCount, 1);
    },
  );

  test(
    'Client original photograph request is impossible through client API',
    () {
      expect(PhotographDerivativeKind.values, isNot(contains('original')));
    },
  );

  test(
    'Client transfer evidence remains separate from generic upload',
    () async {
      final calls = <Map<String, dynamic>>[];
      final repository = SupabaseDocumentRepository(
        invokeFunction: (functionName, body) async {
          calls.add({'function': functionName, ...body});
          return {'data': uploadAuthorizationJson()};
        },
        uploadBytes: (_, _) async {},
      );

      await repository.authorizeClientTransferEvidenceUpload(
        DocumentUploadRequest(
          originalFileName: 'receipt.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List(1),
          clientPaymentId: 'payment-1',
        ),
      );

      expect(calls.single['function'], 'document-upload-authorize');
      expect(calls.single['client_payment_id'], 'payment-1');
      expect(calls.single.containsKey('document_type_code'), isFalse);
    },
  );

  test('public upload state contains no URL token or storage key fields', () {
    const state = DocumentUploadState(
      phase: DocumentUploadPhase.uploading,
      uploadId: 'upload-1',
    );

    expect(state.toString(), isNot(contains('https://')));
    expect(state.toString(), isNot(contains('token')));
    expect(state.toString(), isNot(contains('storage_object_key')));
  });

  test('malformed upload authorization response fails', () async {
    final repository = SupabaseDocumentRepository(
      invokeFunction: (_, _) async => {
        'data': {
          'upload_id': 'upload-1',
          'method': 'PUT',
          'expires_at': 'not-a-date',
          'max_file_size_bytes': '10',
          'allowed_mime_types': ['application/pdf'],
        },
      },
    );

    expect(
      repository.authorizeUpload(uploadRequest()),
      throwsA(isA<DocumentParseFailure>()),
    );
  });

  test('upload state stops at awaiting scan after completion result', () async {
    final repository = FakeDocumentRepository(
      completion: const DocumentUploadResult(
        uploadId: 'upload-1',
        status: 'AWAITING_SCAN',
        reservedDocumentId: 'doc-1',
      ),
    );
    final container = containerWith(repository: repository);
    addTearDown(container.dispose);

    await container
        .read(documentUploadProvider.notifier)
        .start(uploadRequest());

    expect(
      container.read(documentUploadProvider).phase,
      DocumentUploadPhase.awaitingScan,
    );
    expect(repository.uploaded, isTrue);
  });

  test(
    'upload complete is reached only after finalized backend result',
    () async {
      final repository = FakeDocumentRepository(
        completion: const DocumentUploadResult(
          uploadId: 'upload-1',
          status: 'FINALIZED',
          reservedDocumentId: 'doc-1',
        ),
      );
      final container = containerWith(repository: repository);
      addTearDown(container.dispose);

      await container
          .read(documentUploadProvider.notifier)
          .start(uploadRequest());

      expect(
        container.read(documentUploadProvider).phase,
        DocumentUploadPhase.complete,
      );
    },
  );

  test('upload failure handling moves to failed state', () async {
    final container = containerWith(
      repository: FakeDocumentRepository(failUpload: true),
    );
    addTearDown(container.dispose);

    await container
        .read(documentUploadProvider.notifier)
        .start(uploadRequest());

    final state = container.read(documentUploadProvider);
    expect(state.phase, DocumentUploadPhase.failed);
    expect(state.error, isNotNull);
  });

  test('older upload cannot overwrite newer upload state', () async {
    final first = Completer<void>();
    final second = Completer<void>();
    final repository = FakeDocumentRepository(
      uploadCompleters: [first, second],
    );
    final container = containerWith(repository: repository);
    addTearDown(container.dispose);

    final firstRun = container
        .read(documentUploadProvider.notifier)
        .start(uploadRequest());
    await pumpProvider();
    final secondRun = container
        .read(documentUploadProvider.notifier)
        .start(uploadRequest());
    await pumpProvider();
    first.complete();
    await firstRun;
    second.complete();
    await secondRun;

    expect(container.read(documentUploadProvider).uploadId, 'upload-2');
    expect(
      container.read(documentUploadProvider).phase,
      DocumentUploadPhase.complete,
    );
  });

  test(
    'Riverpod client list reports loading success empty and error',
    () async {
      final success = containerWith(repository: FakeDocumentRepository());
      addTearDown(success.dispose);

      expect(success.read(clientDocumentListProvider).isLoading, isTrue);
      await success.read(clientDocumentListProvider.notifier).load();
      expect(success.read(clientDocumentListProvider).isEmpty, isTrue);

      final failure = containerWith(
        repository: FakeDocumentRepository(failList: true),
      );
      addTearDown(failure.dispose);

      await failure.read(clientDocumentListProvider.notifier).load();
      expect(failure.read(clientDocumentListProvider).error, isNotNull);
    },
  );

  test(
    'Client documents clear on sign-out and ignore stale user result',
    () async {
      final firstLoad = Completer<List<SafeDocument>>();
      final repository = FakeDocumentRepository(listCompleters: [firstLoad]);
      final container = ProviderContainer(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.authenticated(
              authUserId: 'user-a',
              email: 'a@example.test',
            ),
          ),
          documentRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        clientDocumentListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await pumpProvider();
      final first = container.read(clientDocumentListProvider.notifier).load();
      container.read(authSessionProvider.notifier).signOut();
      await pumpProvider();
      expect(container.read(clientDocumentListProvider).documents, isEmpty);

      firstLoad.complete([
        SafeDocument.fromJson(validDocumentRow(id: 'doc-a')),
      ]);
      await first;
      expect(container.read(clientDocumentListProvider).documents, isEmpty);
    },
  );

  test('Client document list loads for trusted client route target', () async {
    final account = ControlledCurrentAccountRepository(
      accountRow(roleCode: 'client', userType: 'CLIENT'),
    );
    final repository = FakeDocumentRepository(
      clientFallbackRows: [
        SafeDocument.fromJson(validDocumentRow(id: 'client-doc')),
      ],
    );
    final container = containerWith(
      repository: repository,
      currentAccountRepository: account,
      overrideOwnerAdminAccess: false,
    );
    addTearDown(container.dispose);

    container.read(currentAccountProvider);
    await pumpProvider();
    expect(
      container.read(currentAccountProvider).routeTarget,
      TrustedAccountRouteTarget.client,
    );
    expect(container.read(ownerAdminDocumentAccessProvider), isFalse);

    await container.read(clientDocumentListProvider.notifier).load();

    expect(
      container.read(clientDocumentListProvider).documents.single.id,
      'client-doc',
    );
  });

  test('Owner/Admin load more appends unique backend rows in order', () async {
    final repository = FakeDocumentRepository(
      ownerAdminPages: [
        [
          SafeDocument.fromJson(validDocumentRow(id: 'doc-a')),
          SafeDocument.fromJson(validDocumentRow(id: 'doc-b')),
        ],
        [
          SafeDocument.fromJson(validDocumentRow(id: 'doc-b')),
          SafeDocument.fromJson(validDocumentRow(id: 'doc-c')),
        ],
      ],
    );
    final container = containerWith(repository: repository);
    addTearDown(container.dispose);

    await container.read(ownerAdminDocumentListProvider.notifier).load();
    await container.read(ownerAdminDocumentListProvider.notifier).loadMore();

    expect(
      container
          .read(ownerAdminDocumentListProvider)
          .documents
          .map((document) => document.id),
      ['doc-a', 'doc-b', 'doc-c'],
    );
    expect(repository.ownerAdminOffsets, [0, 2]);
  });

  test(
    'Owner/Admin stale load-more result cannot overwrite new filter',
    () async {
      final stalePage = Completer<List<SafeDocument>>();
      final filteredPage = Completer<List<SafeDocument>>();
      final repository = FakeDocumentRepository(
        ownerAdminPages: [
          [SafeDocument.fromJson(validDocumentRow(id: 'doc-a'))],
        ],
        ownerAdminCompleters: [stalePage, filteredPage],
      );
      final container = containerWith(repository: repository);
      addTearDown(container.dispose);

      await container.read(ownerAdminDocumentListProvider.notifier).load();
      final loadMore = container
          .read(ownerAdminDocumentListProvider.notifier)
          .loadMore();
      await pumpProvider();
      final filteredLoad = container
          .read(ownerAdminDocumentListProvider.notifier)
          .applyFilters(
            const OwnerAdminDocumentFilters(contextType: 'project'),
          );

      stalePage.complete([
        SafeDocument.fromJson(validDocumentRow(id: 'stale')),
      ]);
      filteredPage.complete([
        SafeDocument.fromJson(validDocumentRow(id: 'filtered')),
      ]);
      await loadMore;
      await filteredLoad;

      expect(
        container.read(ownerAdminDocumentListProvider).documents.single.id,
        'filtered',
      );
    },
  );

  test('Owner/Admin documents clear on logout and account switch', () async {
    final source = ControlledAuthSessionSource(
      const AuthSessionSnapshot(authUserId: 'owner-a'),
    );
    final first = Completer<List<SafeDocument>>();
    final second = Completer<List<SafeDocument>>();
    final repository = FakeDocumentRepository(
      ownerAdminCompleters: [first, second],
    );
    final container = ProviderContainer(
      overrides: [
        authSessionSourceProvider.overrideWithValue(source),
        documentRepositoryProvider.overrideWithValue(repository),
        ownerAdminDocumentAccessProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    container.listen(
      ownerAdminDocumentListProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await pumpProvider();
    final firstLoad = container
        .read(ownerAdminDocumentListProvider.notifier)
        .load();
    source.emitSignedOut();
    await pumpProvider();
    expect(container.read(ownerAdminDocumentListProvider).documents, isEmpty);

    source.emitSignedIn(const AuthSessionSnapshot(authUserId: 'owner-b'));
    await pumpProvider();
    final secondLoad = container
        .read(ownerAdminDocumentListProvider.notifier)
        .load();
    first.complete([SafeDocument.fromJson(validDocumentRow(id: 'owner-a'))]);
    await firstLoad;
    expect(container.read(ownerAdminDocumentListProvider).documents, isEmpty);
    second.complete([SafeDocument.fromJson(validDocumentRow(id: 'owner-b'))]);
    await secondLoad;

    expect(
      container.read(ownerAdminDocumentListProvider).documents.single.id,
      'owner-b',
    );
  });

  test('Owner/Admin list clears on trusted current-account denial', () async {
    for (final row in [
      accountRow(roleCode: 'project_manager', accessAllowed: false),
      accountRow(roleCode: 'accountant', accessAllowed: false),
      accountRow(roleCode: 'site_supervisor', accessAllowed: false),
      accountRow(
        roleCode: 'owner_admin',
        accountStatus: 'SUSPENDED',
        isActive: false,
        accessAllowed: false,
      ),
    ]) {
      final account = ControlledCurrentAccountRepository(accountRow());
      final repository = FakeDocumentRepository(
        ownerAdminPages: [
          [SafeDocument.fromJson(validDocumentRow(id: 'allowed'))],
          [SafeDocument.fromJson(validDocumentRow(id: 'fresh'))],
        ],
      );
      final container = containerWith(
        repository: repository,
        currentAccountRepository: account,
        overrideOwnerAdminAccess: false,
      );
      addTearDown(container.dispose);

      container.listen(
        ownerAdminDocumentListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      container.read(currentAccountProvider);
      await pumpProvider();
      await container.read(ownerAdminDocumentListProvider.notifier).load();
      expect(
        container.read(ownerAdminDocumentListProvider).documents.single.id,
        'allowed',
      );

      account.row = row;
      await container.read(currentAccountProvider.notifier).load();
      await pumpUntil(() {
        return container.read(currentAccountProvider).routeTarget !=
            TrustedAccountRouteTarget.staff;
      });
      expect(
        container.read(currentAccountProvider).routeTarget,
        isNot(TrustedAccountRouteTarget.staff),
      );
      container.read(ownerAdminDocumentListProvider);
      expect(container.read(ownerAdminDocumentListProvider).documents, isEmpty);

      account.row = accountRow();
      await container.read(currentAccountProvider.notifier).load();
      await pumpUntil(() {
        return container.read(currentAccountProvider).routeTarget ==
            TrustedAccountRouteTarget.staff;
      });
      expect(
        container.read(currentAccountProvider).routeTarget,
        TrustedAccountRouteTarget.staff,
      );
      await container.read(ownerAdminDocumentListProvider.notifier).load();
      expect(
        container.read(ownerAdminDocumentListProvider).documents.single.id,
        'fresh',
      );
    }
  });

  test(
    'Owner/Admin stale list detail and upload results cannot restore after denial',
    () async {
      final account = ControlledCurrentAccountRepository(accountRow());
      final list = Completer<List<SafeDocument>>();
      final detail = Completer<SafeDocument>();
      final upload = Completer<void>();
      final repository = FakeDocumentRepository(
        ownerAdminCompleters: [list],
        ownerAdminDetailCompleters: [detail],
        uploadCompleters: [upload],
      );
      final container = containerWith(
        repository: repository,
        currentAccountRepository: account,
        overrideOwnerAdminAccess: false,
      );
      addTearDown(container.dispose);

      container.listen(
        ownerAdminDocumentListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        ownerAdminDocumentDetailProvider('doc-1'),
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        documentUploadProvider,
        (_, _) {},
        fireImmediately: true,
      );
      container.read(currentAccountProvider);
      await pumpProvider();

      final listLoad = container
          .read(ownerAdminDocumentListProvider.notifier)
          .load();
      final detailLoad = container
          .read(ownerAdminDocumentDetailProvider('doc-1').notifier)
          .load();
      final uploadStart = container
          .read(documentUploadProvider.notifier)
          .start(uploadRequest());
      await pumpProvider();

      account.row = accountRow(
        roleCode: 'project_manager',
        accessAllowed: false,
      );
      await container.read(currentAccountProvider.notifier).load();
      await pumpProvider();

      expect(container.read(ownerAdminDocumentListProvider).documents, isEmpty);
      expect(
        container.read(ownerAdminDocumentDetailProvider('doc-1')).document,
        isNull,
      );
      expect(
        container.read(documentUploadProvider).phase,
        DocumentUploadPhase.idle,
      );

      list.complete([SafeDocument.fromJson(validDocumentRow(id: 'stale'))]);
      detail.complete(SafeDocument.fromJson(validDocumentRow(id: 'stale')));
      upload.complete();
      await listLoad;
      await detailLoad;
      await uploadStart;

      expect(container.read(ownerAdminDocumentListProvider).documents, isEmpty);
      expect(
        container.read(ownerAdminDocumentDetailProvider('doc-1')).document,
        isNull,
      );
      expect(
        container.read(documentUploadProvider).phase,
        DocumentUploadPhase.idle,
      );
    },
  );

  test(
    'Owner/Admin stale lifecycle mutation cannot restore after denial',
    () async {
      final account = ControlledCurrentAccountRepository(accountRow());
      final mutation = Completer<DocumentLifecycleMutationResult>();
      final repository = FakeDocumentRepository(mutationCompleter: mutation);
      final container = containerWith(
        repository: repository,
        currentAccountRepository: account,
        overrideOwnerAdminAccess: false,
      );
      addTearDown(container.dispose);

      container.listen(
        ownerAdminDocumentDetailProvider('doc-1'),
        (_, _) {},
        fireImmediately: true,
      );
      container.read(currentAccountProvider);
      await pumpProvider();
      await container
          .read(ownerAdminDocumentDetailProvider('doc-1').notifier)
          .load();

      final run = container
          .read(ownerAdminDocumentDetailProvider('doc-1').notifier)
          .archive();
      await pumpProvider();
      account.row = accountRow(
        roleCode: 'project_manager',
        accessAllowed: false,
      );
      await container.read(currentAccountProvider.notifier).load();
      await pumpProvider();

      mutation.complete(
        const DocumentLifecycleMutationResult(
          documentId: 'doc-1',
          status: 'ARCHIVED',
        ),
      );
      await run;

      expect(
        container.read(ownerAdminDocumentDetailProvider('doc-1')).document,
        isNull,
      );
    },
  );

  test('no service-role credential appears in Flutter document core', () {
    const sourceHints = [SupabaseDocumentRepository, SafeDocument];

    expect(sourceHints.join(' '), isNot(contains('service_role')));
  });
}

ProviderContainer containerWith({
  required DocumentRepository repository,
  CurrentAccountRepository? currentAccountRepository,
  bool overrideOwnerAdminAccess = true,
}) {
  return ProviderContainer(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(
          authUserId: 'user-a',
          email: 'a@example.test',
        ),
      ),
      documentRepositoryProvider.overrideWithValue(repository),
      currentAccountRepositoryProvider.overrideWithValue(
        currentAccountRepository ??
            ControlledCurrentAccountRepository(accountRow()),
      ),
      if (overrideOwnerAdminAccess)
        ownerAdminDocumentAccessProvider.overrideWithValue(true),
    ],
  );
}

Map<String, dynamic> validDocumentRow({
  String id = 'doc-1',
  String status = 'ACTIVE',
}) {
  return {
    'id': id,
    'document_number': 'DOC-001',
    'original_file_name': 'invoice.pdf',
    'mime_type': 'application/pdf',
    'document_type_code': 'INVOICE',
    'status': status,
    'uploaded_at': '2026-08-10T01:00:00Z',
  };
}

List<Map<String, dynamic>> accountRow({
  String roleCode = 'owner_admin',
  String accountStatus = 'ACTIVE',
  bool isActive = true,
  bool accessAllowed = true,
  String userType = 'STAFF',
}) {
  return [
    {
      'application_user_id': '10000000-0000-0000-0000-000000000201',
      'account_status': accountStatus,
      'is_active': isActive,
      'access_allowed': accessAllowed,
      'user_type': userType,
      'full_name': 'Staff Person',
      'job_title': 'Staff',
      'active_role_codes': [roleCode],
    },
  ];
}

Map<String, dynamic> uploadAuthorizationJson() {
  return {
    'upload_id': 'upload-1',
    'upload_url': 'https://example.test/upload',
    'method': 'PUT',
    'expires_at': '2026-08-10T01:05:00Z',
    'max_file_size_bytes': 10,
    'allowed_mime_types': ['application/pdf'],
  };
}

DocumentUploadRequest uploadRequest() {
  return DocumentUploadRequest(
    originalFileName: 'photo.jpg',
    mimeType: 'image/jpeg',
    bytes: Uint8List.fromList([1, 2, 3]),
    documentTypeCode: 'PROGRESS_PHOTOGRAPH',
    projectId: 'project-1',
  );
}

class FakeAccessClient implements DocumentAccessClient {
  const FakeAccessClient({required this.response});

  final DocumentAccessResponse response;

  @override
  Future<DocumentAccessResponse> post(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    return response;
  }
}

class FakeDocumentRepository implements DocumentRepository {
  FakeDocumentRepository({
    this.completion = const DocumentUploadResult(
      uploadId: 'upload-1',
      status: 'FINALIZED',
      reservedDocumentId: 'doc-1',
    ),
    this.failUpload = false,
    this.failList = false,
    this.uploadCompleters = const [],
    this.listCompleters = const [],
    this.ownerAdminCompleters = const [],
    this.ownerAdminDetailCompleters = const [],
    this.ownerAdminPages = const [],
    this.clientFallbackRows = const [],
    this.mutationCompleter,
  });

  final DocumentUploadResult completion;
  final bool failUpload;
  final bool failList;
  final List<Completer<void>> uploadCompleters;
  final List<Completer<List<SafeDocument>>> listCompleters;
  final List<Completer<List<SafeDocument>>> ownerAdminCompleters;
  final List<Completer<SafeDocument>> ownerAdminDetailCompleters;
  final List<List<SafeDocument>> ownerAdminPages;
  final List<SafeDocument> clientFallbackRows;
  final Completer<DocumentLifecycleMutationResult>? mutationCompleter;
  final ownerAdminOffsets = <int>[];
  bool uploaded = false;
  var _uploadCall = 0;
  var _listCall = 0;
  var _ownerAdminListCall = 0;
  var _ownerAdminCompleterCall = 0;
  var _ownerAdminDetailCompleterCall = 0;

  @override
  Future<SafeDocument> getOwnerAdminDocumentDetail(String documentId) async {
    if (_ownerAdminDetailCompleterCall < ownerAdminDetailCompleters.length) {
      return ownerAdminDetailCompleters[_ownerAdminDetailCompleterCall++]
          .future;
    }
    return SafeDocument.fromJson(validDocumentRow());
  }

  @override
  Future<DocumentLifecycleMutationResult> archiveOwnerAdminDocument(
    String documentId,
  ) async {
    if (mutationCompleter != null) return mutationCompleter!.future;
    return DocumentLifecycleMutationResult(
      documentId: documentId,
      status: 'ARCHIVED',
    );
  }

  @override
  Future<DocumentLifecycleMutationResult> restoreOwnerAdminDocument(
    String documentId,
  ) async {
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
    return DocumentLifecycleMutationResult(
      documentId: documentId,
      replacementDocumentId: replacementDocumentId,
      status: 'ACTIVE',
    );
  }

  @override
  Future<List<SafeDocument>> listOwnerAdminDocuments({
    OwnerAdminDocumentFilters filters = const OwnerAdminDocumentFilters(),
    int limit = 50,
    int offset = 0,
  }) async {
    ownerAdminOffsets.add(offset);
    if (_ownerAdminListCall < ownerAdminPages.length) {
      return ownerAdminPages[_ownerAdminListCall++];
    }
    if (_ownerAdminCompleterCall < ownerAdminCompleters.length) {
      return ownerAdminCompleters[_ownerAdminCompleterCall++].future;
    }
    if (failList) throw StateError('offline');
    return [SafeDocument.fromJson(validDocumentRow())];
  }

  @override
  Future<List<SafeDocument>> listClientDocuments({
    int limit = 50,
    int offset = 0,
  }) async {
    if (_listCall < listCompleters.length) {
      return listCompleters[_listCall++].future;
    }
    if (failList) throw StateError('offline');
    if (clientFallbackRows.isNotEmpty) return clientFallbackRows;
    return const [];
  }

  @override
  Future<DocumentUploadSession> authorizeUpload(
    DocumentUploadRequest request,
  ) async {
    _uploadCall++;
    return DocumentUploadSession(
      uploadId: 'upload-$_uploadCall',
      expiresAt: DateTime.utc(2026, 8, 10),
      maxFileSizeBytes: 10,
      allowedMimeTypes: const ['image/jpeg'],
    );
  }

  @override
  Future<void> uploadAuthorizedBytes(
    DocumentUploadSession session,
    Uint8List bytes,
  ) async {
    final index = int.parse(session.uploadId.split('-').last) - 1;
    if (index < uploadCompleters.length) {
      await uploadCompleters[index].future;
    }
    if (failUpload) throw StateError('upload failed');
    uploaded = true;
  }

  @override
  Future<DocumentUploadResult> completeUpload(String uploadId) async {
    return DocumentUploadResult(
      uploadId: uploadId,
      status: completion.status,
      reservedDocumentId: completion.reservedDocumentId,
    );
  }

  @override
  Future<DocumentUploadSession> authorizeClientTransferEvidenceUpload(
    DocumentUploadRequest request,
  ) async {
    return authorizeUpload(request);
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
  Future<SecureDocumentAccess> requestDocumentAccess(
    String documentId,
    DocumentAccessPurpose purpose,
  ) async {
    return SecureDocumentAccess(
      bytes: Uint8List(0),
      mimeType: 'application/pdf',
      safeFileName: 'document.pdf',
    );
  }

  @override
  Future<SecureDocumentAccess> requestOwnerAdminOriginalPhotograph(
    String documentId,
  ) async {
    return SecureDocumentAccess(
      bytes: Uint8List(0),
      mimeType: 'image/jpeg',
      safeFileName: 'photo.jpg',
    );
  }

  @override
  Future<SecureDocumentAccess> requestPhotographPreview(
    String documentId,
  ) async {
    return SecureDocumentAccess(
      bytes: Uint8List(0),
      mimeType: 'image/webp',
      safeFileName: 'photo.webp',
    );
  }

  @override
  Future<SecureDocumentAccess> requestPhotographThumbnail(
    String documentId,
  ) async {
    return SecureDocumentAccess(
      bytes: Uint8List(0),
      mimeType: 'image/webp',
      safeFileName: 'photo.webp',
    );
  }
}

class ControlledCurrentAccountRepository extends CurrentAccountRepository {
  ControlledCurrentAccountRepository(this.row);

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

Future<void> pumpUntil(bool Function() done) async {
  for (var i = 0; i < 20; i++) {
    if (done()) return;
    await Future<void>.delayed(Duration.zero);
  }
}

class ControlledAuthSessionSource implements AuthSessionSource {
  ControlledAuthSessionSource(this.restoredSession);

  AuthSessionSnapshot? restoredSession;
  final controller = StreamController<AuthSessionChange>.broadcast(sync: true);

  @override
  AuthSessionSnapshot? get currentSession => restoredSession;

  @override
  Stream<AuthSessionChange> get onAuthStateChange => controller.stream;

  void emitSignedIn(AuthSessionSnapshot session) {
    restoredSession = session;
    controller.add(
      AuthSessionChange(
        event: AuthSessionChangeEvent.signedIn,
        session: session,
      ),
    );
  }

  void emitSignedOut() {
    restoredSession = null;
    controller.add(
      const AuthSessionChange(event: AuthSessionChangeEvent.signedOut),
    );
  }
}
