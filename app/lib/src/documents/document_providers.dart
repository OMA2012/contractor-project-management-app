import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
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

final ownerAdminDocumentListProvider =
    NotifierProvider<OwnerAdminDocumentListController, DocumentListState>(
      OwnerAdminDocumentListController.new,
    );

final ownerAdminDocumentFiltersProvider =
    StateProvider<OwnerAdminDocumentFilters>(
      (ref) => const OwnerAdminDocumentFilters(),
    );

final ownerAdminDocumentDetailProvider =
    NotifierProvider.family<
      OwnerAdminDocumentDetailController,
      OwnerAdminDocumentDetailState,
      String
    >((documentId) => OwnerAdminDocumentDetailController(documentId));

final documentUploadProvider =
    NotifierProvider<DocumentUploadController, DocumentUploadState>(
      DocumentUploadController.new,
    );

final clientPhotographGalleryProvider =
    NotifierProvider<ClientPhotographGalleryController, PhotographGalleryState>(
      ClientPhotographGalleryController.new,
    );

final ownerAdminPhotographCategoryProvider =
    StateProvider<OwnerAdminPhotographCategory>(
      (ref) => OwnerAdminPhotographCategory.progress,
    );

final ownerAdminPhotographGalleryProvider =
    NotifierProvider<
      OwnerAdminPhotographGalleryController,
      PhotographGalleryState
    >(OwnerAdminPhotographGalleryController.new);

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

class OwnerAdminDocumentListController extends Notifier<DocumentListState> {
  var _requestGeneration = 0;
  String? _activeAuthUserId;
  var _limit = 50;
  var _isLoadingMore = false;
  var _documents = <SafeDocument>[];

  @override
  DocumentListState build() {
    ref.listen<bool>(ownerAdminDocumentAccessProvider, (_, hasAccess) {
      if (!hasAccess) {
        _invalidateActiveLoad();
        state = const DocumentListState.loaded([]);
      }
    }, fireImmediately: true);
    final session = ref.watch(authSessionProvider);
    final hasAccess = ref.watch(ownerAdminDocumentAccessProvider);
    if (session.status != AuthSessionStatus.authenticated || !hasAccess) {
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
    if (session.status != AuthSessionStatus.authenticated ||
        !ref.read(ownerAdminDocumentAccessProvider)) {
      _invalidateActiveLoad();
      state = const DocumentListState.loaded([]);
      return;
    }
    _limit = limit;
    final authUserId = session.authUserId;
    _activeAuthUserId = authUserId;
    final generation = ++_requestGeneration;
    state = const DocumentListState.loading();
    try {
      final documents = await ref
          .read(documentRepositoryProvider)
          .listOwnerAdminDocuments(
            filters: ref.read(ownerAdminDocumentFiltersProvider),
            limit: limit,
            offset: offset,
          );
      if (!_canApplyResult(authUserId, generation)) return;
      _documents = documents;
      state = DocumentListState.loaded(documents);
    } catch (error) {
      if (!_canApplyResult(authUserId, generation)) return;
      state = DocumentListState.failure(error);
    }
  }

  Future<void> refresh() => load(limit: _limit, offset: 0);

  Future<void> applyFilters(OwnerAdminDocumentFilters filters) {
    ref.read(ownerAdminDocumentFiltersProvider.notifier).state = filters;
    _invalidateActiveLoad();
    return load(limit: _limit, offset: 0);
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || state.isLoading || state.error != null) return;
    final session = ref.read(authSessionProvider);
    if (session.status != AuthSessionStatus.authenticated) {
      _invalidateActiveLoad();
      state = const DocumentListState.loaded([]);
      return;
    }
    _isLoadingMore = true;
    final authUserId = session.authUserId;
    _activeAuthUserId = authUserId;
    final generation = ++_requestGeneration;
    final filters = ref.read(ownerAdminDocumentFiltersProvider);
    try {
      final nextDocuments = await ref
          .read(documentRepositoryProvider)
          .listOwnerAdminDocuments(
            filters: filters,
            limit: _limit,
            offset: _documents.length,
          );
      if (!_canApplyResult(authUserId, generation)) return;
      final seen = _documents.map((document) => document.id).toSet();
      _documents = [
        ..._documents,
        ...nextDocuments.where((document) => seen.add(document.id)),
      ];
      state = DocumentListState.loaded(_documents);
    } catch (_) {
      if (!_canApplyResult(authUserId, generation)) return;
      state = DocumentListState.loaded(_documents);
    } finally {
      _isLoadingMore = false;
    }
  }

  void _invalidateActiveLoad() {
    _activeAuthUserId = null;
    _documents = [];
    _isLoadingMore = false;
    _requestGeneration++;
  }

  bool _canApplyResult(String? authUserId, int generation) {
    if (!ref.mounted) return false;
    final session = ref.read(authSessionProvider);
    return generation == _requestGeneration &&
        session.status == AuthSessionStatus.authenticated &&
        ref.read(ownerAdminDocumentAccessProvider) &&
        session.authUserId == authUserId &&
        _activeAuthUserId == authUserId;
  }
}

class OwnerAdminDocumentDetailController
    extends Notifier<OwnerAdminDocumentDetailState> {
  OwnerAdminDocumentDetailController(this._documentId);

  var _requestGeneration = 0;
  final String _documentId;

  @override
  OwnerAdminDocumentDetailState build() {
    ref.listen<bool>(ownerAdminDocumentAccessProvider, (_, hasAccess) {
      if (!hasAccess) {
        _requestGeneration++;
        state = const OwnerAdminDocumentDetailState.failure(
          DocumentFailure('Document access requires an active staff account.'),
        );
      }
    }, fireImmediately: true);
    final session = ref.watch(authSessionProvider);
    final hasAccess = ref.watch(ownerAdminDocumentAccessProvider);
    if (session.status != AuthSessionStatus.authenticated || !hasAccess) {
      _requestGeneration++;
      return const OwnerAdminDocumentDetailState.failure(
        DocumentFailure('Document access requires an authenticated session.'),
      );
    }
    return const OwnerAdminDocumentDetailState.loading();
  }

  Future<void> load() async {
    if (!ref.read(ownerAdminDocumentAccessProvider)) {
      _requestGeneration++;
      state = const OwnerAdminDocumentDetailState.failure(
        DocumentFailure('Document access requires an active staff account.'),
      );
      return;
    }
    final generation = ++_requestGeneration;
    state = const OwnerAdminDocumentDetailState.loading();
    try {
      final document = await ref
          .read(documentRepositoryProvider)
          .getOwnerAdminDocumentDetail(_documentId);
      if (!_canApplyResult(generation)) return;
      state = OwnerAdminDocumentDetailState.loaded(document);
    } catch (error) {
      if (!_canApplyResult(generation)) return;
      state = OwnerAdminDocumentDetailState.failure(error);
    }
  }

  Future<bool> archive() => _mutate(
    () => ref
        .read(documentRepositoryProvider)
        .archiveOwnerAdminDocument(_documentId),
  );

  Future<bool> restore() => _mutate(
    () => ref
        .read(documentRepositoryProvider)
        .restoreOwnerAdminDocument(_documentId),
  );

  Future<bool> replaceWith(String replacementDocumentId) => _mutate(
    () => ref
        .read(documentRepositoryProvider)
        .replaceOwnerAdminDocument(
          documentId: _documentId,
          replacementDocumentId: replacementDocumentId,
        ),
  );

  Future<bool> _mutate(
    Future<DocumentLifecycleMutationResult> Function() operation,
  ) async {
    if (!ref.read(ownerAdminDocumentAccessProvider)) {
      _requestGeneration++;
      state = const OwnerAdminDocumentDetailState.failure(
        DocumentFailure('Document access requires an active staff account.'),
      );
      return false;
    }
    if (state.isMutating) return false;
    final generation = ++_requestGeneration;
    state = state.copyWith(
      mutationPhase: DocumentLifecycleMutationPhase.running,
      clearMutationError: true,
    );
    try {
      await operation();
      if (!_canApplyResult(generation)) return false;
      final document = await ref
          .read(documentRepositoryProvider)
          .getOwnerAdminDocumentDetail(_documentId);
      if (!_canApplyResult(generation)) return false;
      state = OwnerAdminDocumentDetailState.loaded(
        document,
      ).copyWith(mutationPhase: DocumentLifecycleMutationPhase.succeeded);
      await ref.read(ownerAdminDocumentListProvider.notifier).refresh();
      return _canApplyResult(generation);
    } catch (error) {
      if (!_canApplyResult(generation)) return false;
      state = state.copyWith(
        mutationPhase: DocumentLifecycleMutationPhase.failed,
        mutationError: error,
      );
      return false;
    }
  }

  bool _canApplyResult(int generation) =>
      ref.mounted &&
      generation == _requestGeneration &&
      ref.read(ownerAdminDocumentAccessProvider);
}

class DocumentUploadController extends Notifier<DocumentUploadState> {
  var _requestGeneration = 0;

  @override
  DocumentUploadState build() {
    ref.listen<bool>(ownerAdminDocumentAccessProvider, (_, hasAccess) {
      if (!hasAccess) {
        _requestGeneration++;
        state = const DocumentUploadState.idle();
      }
    }, fireImmediately: true);
    final hasAccess = ref.watch(ownerAdminDocumentAccessProvider);
    if (!hasAccess) {
      _requestGeneration++;
    }
    return const DocumentUploadState.idle();
  }

  Future<void> start(DocumentUploadRequest request) async {
    if (!ref.read(ownerAdminDocumentAccessProvider)) {
      _requestGeneration++;
      state = const DocumentUploadState.idle();
      return;
    }
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
      ref.mounted &&
      generation == _requestGeneration &&
      ref.read(ownerAdminDocumentAccessProvider);
}

final ownerAdminDocumentAccessProvider = Provider<bool>((ref) {
  final account = ref.watch(currentAccountProvider);
  return _hasOwnerAdminDocumentAccess(account);
});

bool _hasOwnerAdminDocumentAccess(CurrentAccountState account) {
  return account.routeTarget == TrustedAccountRouteTarget.staff;
}

class ClientPhotographGalleryController
    extends Notifier<PhotographGalleryState> {
  static const defaultLimit = 50;

  var _generation = 0;
  var _offset = 0;
  var _limit = defaultLimit;
  var _seen = <String>{};
  String? _authUserId;

  @override
  PhotographGalleryState build() {
    ref.listen<AuthSessionState>(authSessionProvider, (_, session) {
      if (session.status != AuthSessionStatus.authenticated ||
          session.authUserId != _authUserId) {
        _clear();
      }
    }, fireImmediately: true);
    final session = ref.watch(authSessionProvider);
    final account = ref.watch(currentAccountProvider);
    if (session.status != AuthSessionStatus.authenticated ||
        account.routeTarget != TrustedAccountRouteTarget.client) {
      _clear();
      return const PhotographGalleryState(hasMore: false);
    }
    _authUserId = session.authUserId;
    return const PhotographGalleryState(isLoading: true);
  }

  Future<void> load({int limit = defaultLimit}) async {
    final session = ref.read(authSessionProvider);
    if (!_hasClientAccess(session)) {
      _clear();
      state = const PhotographGalleryState(hasMore: false);
      return;
    }
    _limit = limit.clamp(1, 100);
    _offset = 0;
    _seen = <String>{};
    _authUserId = session.authUserId;
    final generation = ++_generation;
    state = const PhotographGalleryState(isLoading: true);
    await _loadPage(generation, session.authUserId, append: false);
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final session = ref.read(authSessionProvider);
    if (!_hasClientAccess(session)) {
      _clear();
      state = const PhotographGalleryState(hasMore: false);
      return;
    }
    _authUserId = session.authUserId;
    final generation = ++_generation;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    await _loadPage(generation, session.authUserId, append: true);
  }

  Future<void> _loadPage(
    int generation,
    String? authUserId, {
    required bool append,
  }) async {
    try {
      final page = await ref
          .read(documentRepositoryProvider)
          .listClientPhotographs(limit: _limit, offset: _offset);
      if (!_canApply(generation, authUserId)) return;
      _offset += page.rawCount;
      final items = append ? [...state.items] : <PhotographGalleryItem>[];
      for (final item in page.items) {
        if (_seen.add(item.id)) items.add(item);
      }
      state = PhotographGalleryState(
        items: items,
        hasMore: page.rawCount == _limit,
      );
    } catch (error) {
      if (!_canApply(generation, authUserId)) return;
      state = PhotographGalleryState(
        items: append ? state.items : [],
        error: error,
      );
    }
  }

  bool _hasClientAccess(AuthSessionState session) =>
      session.status == AuthSessionStatus.authenticated &&
      ref.read(currentAccountProvider).routeTarget ==
          TrustedAccountRouteTarget.client;

  bool _canApply(int generation, String? authUserId) =>
      ref.mounted &&
      generation == _generation &&
      _hasClientAccess(ref.read(authSessionProvider)) &&
      ref.read(authSessionProvider).authUserId == authUserId &&
      _authUserId == authUserId;

  void _clear() {
    _generation++;
    _offset = 0;
    _seen = <String>{};
    _authUserId = null;
  }
}

class OwnerAdminPhotographGalleryController
    extends Notifier<PhotographGalleryState> {
  static const defaultLimit = 50;

  final _offsets = <OwnerAdminPhotographCategory, int>{};
  final _seen = <OwnerAdminPhotographCategory, Set<String>>{};
  final _states = <OwnerAdminPhotographCategory, PhotographGalleryState>{};
  var _generation = 0;
  var _limit = defaultLimit;
  String? _authUserId;

  @override
  PhotographGalleryState build() {
    ref.listen<bool>(ownerAdminDocumentAccessProvider, (_, hasAccess) {
      if (!hasAccess) _clearAll();
    }, fireImmediately: true);
    final session = ref.watch(authSessionProvider);
    final category = ref.watch(ownerAdminPhotographCategoryProvider);
    if (session.status != AuthSessionStatus.authenticated ||
        !ref.watch(ownerAdminDocumentAccessProvider)) {
      _clearAll();
      return const PhotographGalleryState(hasMore: false);
    }
    if (_authUserId != session.authUserId) _clearAll();
    _authUserId = session.authUserId;
    return _states[category] ?? const PhotographGalleryState(isLoading: true);
  }

  Future<void> selectCategory(OwnerAdminPhotographCategory category) async {
    ref.read(ownerAdminPhotographCategoryProvider.notifier).state = category;
    if (!_states.containsKey(category)) {
      await load();
    }
  }

  Future<void> load({int limit = defaultLimit}) async {
    final session = ref.read(authSessionProvider);
    if (!_hasAccess(session)) {
      _clearAll();
      state = const PhotographGalleryState(hasMore: false);
      return;
    }
    _limit = limit.clamp(1, 100);
    final category = ref.read(ownerAdminPhotographCategoryProvider);
    _offsets[category] = 0;
    _seen[category] = <String>{};
    _authUserId = session.authUserId;
    final generation = ++_generation;
    _setCategoryState(category, const PhotographGalleryState(isLoading: true));
    await _loadPage(category, generation, session.authUserId, append: false);
  }

  Future<void> loadMore() async {
    final category = ref.read(ownerAdminPhotographCategoryProvider);
    final current = _states[category] ?? state;
    if (current.isLoading || current.isLoadingMore || !current.hasMore) return;
    final session = ref.read(authSessionProvider);
    if (!_hasAccess(session)) {
      _clearAll();
      state = const PhotographGalleryState(hasMore: false);
      return;
    }
    _authUserId = session.authUserId;
    final generation = ++_generation;
    _setCategoryState(
      category,
      current.copyWith(isLoadingMore: true, clearError: true),
    );
    await _loadPage(category, generation, session.authUserId, append: true);
  }

  Future<void> _loadPage(
    OwnerAdminPhotographCategory category,
    int generation,
    String? authUserId, {
    required bool append,
  }) async {
    try {
      final page = await ref
          .read(documentRepositoryProvider)
          .listOwnerAdminPhotographs(
            category: category,
            limit: _limit,
            offset: _offsets[category] ?? 0,
          );
      if (!_canApply(generation, authUserId)) return;
      _offsets[category] = (_offsets[category] ?? 0) + page.rawCount;
      final seen = _seen.putIfAbsent(category, () => <String>{});
      final base = append
          ? [...(_states[category]?.items ?? const <PhotographGalleryItem>[])]
          : <PhotographGalleryItem>[];
      for (final item in page.items) {
        if (seen.add(item.id)) base.add(item);
      }
      _setCategoryState(
        category,
        PhotographGalleryState(items: base, hasMore: page.rawCount == _limit),
      );
    } catch (error) {
      if (!_canApply(generation, authUserId)) return;
      _setCategoryState(
        category,
        PhotographGalleryState(
          items: append ? _states[category]?.items ?? const [] : const [],
          error: error,
        ),
      );
    }
  }

  void _setCategoryState(
    OwnerAdminPhotographCategory category,
    PhotographGalleryState next,
  ) {
    _states[category] = next;
    if (ref.read(ownerAdminPhotographCategoryProvider) == category) {
      state = next;
    }
  }

  bool _hasAccess(AuthSessionState session) =>
      session.status == AuthSessionStatus.authenticated &&
      ref.read(ownerAdminDocumentAccessProvider);

  bool _canApply(int generation, String? authUserId) =>
      ref.mounted &&
      generation == _generation &&
      _hasAccess(ref.read(authSessionProvider)) &&
      ref.read(authSessionProvider).authUserId == authUserId &&
      _authUserId == authUserId;

  void _clearAll() {
    _generation++;
    _offsets.clear();
    _seen.clear();
    _states.clear();
    _authUserId = null;
  }
}
