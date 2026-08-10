import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_session.dart';
import 'document_models.dart';
import 'document_repository.dart';

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => SupabaseDocumentRepository(),
);

final clientDocumentListProvider =
    NotifierProvider<ClientDocumentListController, DocumentListState>(
      ClientDocumentListController.new,
    );

final documentUploadProvider =
    NotifierProvider<DocumentUploadController, DocumentUploadState>(
      DocumentUploadController.new,
    );

class ClientDocumentListController extends Notifier<DocumentListState> {
  var _requestGeneration = 0;
  String? _activeAuthUserId;

  @override
  DocumentListState build() {
    final session = ref.watch(authSessionProvider);
    if (session.status != AuthSessionStatus.authenticated) {
      _invalidateActiveLoad();
      return const DocumentListState.loaded([]);
    }
    if (_activeAuthUserId != session.authUserId) {
      _invalidateActiveLoad();
      _activeAuthUserId = session.authUserId;
    }
    return const DocumentListState.loading();
  }

  Future<void> load({int limit = 50, int offset = 0}) async {
    final session = ref.read(authSessionProvider);
    if (session.status != AuthSessionStatus.authenticated) {
      _invalidateActiveLoad();
      state = const DocumentListState.loaded([]);
      return;
    }
    final authUserId = session.authUserId;
    _activeAuthUserId = authUserId;
    final generation = ++_requestGeneration;
    state = const DocumentListState.loading();
    try {
      final documents = await ref
          .read(documentRepositoryProvider)
          .listClientDocuments(limit: limit, offset: offset);
      if (!_canApplyResult(authUserId, generation)) return;
      state = DocumentListState.loaded(documents);
    } catch (error) {
      if (!_canApplyResult(authUserId, generation)) return;
      state = DocumentListState.failure(error);
    }
  }

  Future<void> refresh() => load();

  void _invalidateActiveLoad() {
    _activeAuthUserId = null;
    _requestGeneration++;
  }

  bool _canApplyResult(String? authUserId, int generation) {
    if (!ref.mounted) return false;
    final session = ref.read(authSessionProvider);
    return generation == _requestGeneration &&
        session.status == AuthSessionStatus.authenticated &&
        session.authUserId == authUserId &&
        _activeAuthUserId == authUserId;
  }
}

class DocumentUploadController extends Notifier<DocumentUploadState> {
  var _requestGeneration = 0;

  @override
  DocumentUploadState build() => const DocumentUploadState.idle();

  Future<void> start(DocumentUploadRequest request) async {
    final generation = ++_requestGeneration;
    final repository = ref.read(documentRepositoryProvider);
    state = const DocumentUploadState(phase: DocumentUploadPhase.authorizing);
    try {
      final authorization = request.isClientTransferEvidence
          ? await repository.authorizeClientTransferEvidenceUpload(request)
          : await repository.authorizeUpload(request);
      if (!_canApplyResult(generation)) return;
      state = DocumentUploadState(
        phase: DocumentUploadPhase.uploading,
        uploadId: authorization.uploadId,
      );
      await repository.uploadAuthorizedBytes(authorization, request.bytes);
      if (!_canApplyResult(generation)) return;
      state = DocumentUploadState(
        phase: DocumentUploadPhase.validatingCompleting,
        uploadId: authorization.uploadId,
      );
      final result = await repository.completeUpload(authorization.uploadId);
      if (!_canApplyResult(generation)) return;
      if (result.awaitingScan) {
        state = DocumentUploadState(
          phase: DocumentUploadPhase.awaitingScan,
          uploadId: result.uploadId,
          documentId: result.reservedDocumentId,
        );
        return;
      }
      if (!result.finalized) {
        throw const DocumentFailure(
          'Upload did not reach an approved finalized backend state.',
        );
      }
      if (request.processPhotograph && result.reservedDocumentId != null) {
        state = DocumentUploadState(
          phase: DocumentUploadPhase.processingPhotograph,
          uploadId: result.uploadId,
          documentId: result.reservedDocumentId,
        );
        await repository.processPhotograph(result.reservedDocumentId!);
        if (!_canApplyResult(generation)) return;
      }
      state = DocumentUploadState(
        phase: DocumentUploadPhase.complete,
        uploadId: result.uploadId,
        documentId: result.reservedDocumentId,
      );
    } catch (error) {
      if (!_canApplyResult(generation)) return;
      state = DocumentUploadState(
        phase: DocumentUploadPhase.failed,
        uploadId: state.uploadId,
        documentId: state.documentId,
        error: error,
      );
    }
  }

  void reset() {
    _requestGeneration++;
    state = const DocumentUploadState.idle();
  }

  bool _canApplyResult(int generation) =>
      ref.mounted && generation == _requestGeneration;
}
