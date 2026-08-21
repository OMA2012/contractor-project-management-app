import 'dart:typed_data';

enum DocumentAudience { ownerAdmin, client }

enum DocumentAccessPurpose { preview, download }

enum PhotographDerivativeKind { thumbnail, preview }

enum DocumentUploadPhase {
  idle,
  authorizing,
  uploading,
  validatingCompleting,
  awaitingScan,
  quarantined,
  scanFailed,
  processingPhotograph,
  complete,
  failed,
}

enum DocumentOperationKind { archive, restore, replacement, lifecycleHistory }

enum DocumentLifecycleMutationPhase { idle, running, succeeded, failed }

enum PhotographGalleryAudience { ownerAdmin, client }

enum OwnerAdminPhotographCategory { progress, taskImage }

class DocumentFailure implements Exception {
  const DocumentFailure(this.message, {this.permissionDenied = false});

  final String message;
  final bool permissionDenied;

  @override
  String toString() => message;
}

class DocumentParseFailure extends DocumentFailure {
  const DocumentParseFailure(super.message);
}

class DocumentListState {
  const DocumentListState._({
    required this.isLoading,
    required this.documents,
    this.error,
  });

  const DocumentListState.loading()
    : this._(isLoading: true, documents: const []);

  const DocumentListState.loaded(List<SafeDocument> documents)
    : this._(isLoading: false, documents: documents);

  const DocumentListState.failure(Object error)
    : this._(isLoading: false, documents: const [], error: error);

  final bool isLoading;
  final List<SafeDocument> documents;
  final Object? error;

  bool get isEmpty => !isLoading && error == null && documents.isEmpty;
}

class DocumentPage {
  const DocumentPage({required this.rawCount, required this.documents});

  final int rawCount;
  final List<SafeDocument> documents;
}

class DocumentPageState {
  const DocumentPageState({
    this.documents = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<SafeDocument> documents;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  bool get isEmpty => !isLoading && error == null && documents.isEmpty;

  DocumentPageState copyWith({
    List<SafeDocument>? documents,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) {
    return DocumentPageState(
      documents: documents ?? this.documents,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class PhotographGalleryItem {
  const PhotographGalleryItem({
    required this.id,
    required this.documentNumber,
    required this.safeDisplayFileName,
    required this.mimeType,
    required this.documentTypeCode,
    required this.uploadedAt,
    required this.processingState,
    required this.thumbnailAvailable,
    required this.previewAvailable,
    this.fileSizeBytes,
    this.status,
    this.clientVisible,
    this.isSuperseded = false,
  });

  factory PhotographGalleryItem.fromClientJson(Map<String, dynamic> json) {
    return PhotographGalleryItem(
      id: _requiredString(json, 'id'),
      documentNumber: _requiredString(json, 'document_number'),
      safeDisplayFileName: _sanitizeFileName(
        _requiredString(json, 'original_file_name'),
      ),
      mimeType: _requiredString(json, 'mime_type'),
      fileSizeBytes: _int(json, 'file_size_bytes'),
      documentTypeCode: _requiredString(json, 'document_type_code'),
      uploadedAt: _date(json, 'uploaded_at'),
      processingState:
          _string(json, 'photograph_processing_status') ?? 'UNKNOWN',
      thumbnailAvailable: json['thumbnail_available'] == true,
      previewAvailable: json['preview_available'] == true,
    );
  }

  factory PhotographGalleryItem.fromOwnerAdminJson(Map<String, dynamic> json) {
    return PhotographGalleryItem(
      id: _requiredString(json, 'id'),
      documentNumber: _requiredString(json, 'document_number'),
      safeDisplayFileName: _sanitizeFileName(
        _requiredString(json, 'original_file_name'),
      ),
      mimeType: _requiredString(json, 'mime_type'),
      fileSizeBytes: _int(json, 'file_size_bytes'),
      documentTypeCode: _requiredString(json, 'document_type_code'),
      uploadedAt: _date(json, 'uploaded_at'),
      processingState:
          _string(json, 'photograph_processing_status') ?? 'UNKNOWN',
      thumbnailAvailable: json['thumbnail_available'] == true,
      previewAvailable: json['preview_available'] == true,
      clientVisible: json['client_visible'] is bool
          ? json['client_visible'] as bool
          : null,
    );
  }

  factory PhotographGalleryItem.fromOwnerAdminDocument(SafeDocument document) {
    final photograph = document.photograph;
    return PhotographGalleryItem(
      id: document.id,
      documentNumber: document.documentNumber,
      safeDisplayFileName: document.safeDisplayFileName,
      mimeType: document.mimeType,
      fileSizeBytes: document.fileSizeBytes,
      documentTypeCode: document.documentTypeCode,
      uploadedAt: document.createdAt,
      processingState: photograph?.processingState ?? 'UNKNOWN',
      thumbnailAvailable: photograph?.thumbnailAvailable == true,
      previewAvailable: photograph?.previewAvailable == true,
      status: document.status,
      clientVisible: document.clientVisible,
      isSuperseded: document.lifecycle?.isSuperseded == true,
    );
  }

  final String id;
  final String documentNumber;
  final String safeDisplayFileName;
  final String mimeType;
  final String documentTypeCode;
  final DateTime? uploadedAt;
  final String processingState;
  final bool thumbnailAvailable;
  final bool previewAvailable;
  final int? fileSizeBytes;
  final String? status;
  final bool? clientVisible;
  final bool isSuperseded;

  bool get isTaskImage => documentTypeCode == 'TASK_ATTACHMENT';
  bool get isProgressPhotograph => documentTypeCode == 'PROGRESS_PHOTOGRAPH';
}

class PhotographGalleryPage {
  const PhotographGalleryPage({required this.rawCount, required this.items});

  final int rawCount;
  final List<PhotographGalleryItem> items;
}

class PhotographGalleryState {
  const PhotographGalleryState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<PhotographGalleryItem> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  bool get isEmpty => !isLoading && error == null && items.isEmpty;

  PhotographGalleryState copyWith({
    List<PhotographGalleryItem>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) {
    return PhotographGalleryState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class OwnerAdminDocumentFilters {
  const OwnerAdminDocumentFilters({
    this.projectId,
    this.documentTypeCode,
    this.clientVisible,
    this.status,
    this.contextType,
  });

  final String? projectId;
  final String? documentTypeCode;
  final bool? clientVisible;
  final String? status;
  final String? contextType;

  Map<String, dynamic> toRpcParams({required int limit, required int offset}) {
    return {
      'p_limit': limit,
      'p_offset': offset,
      if (projectId != null && projectId!.isNotEmpty) 'p_project_id': projectId,
      if (documentTypeCode != null && documentTypeCode!.isNotEmpty)
        'p_document_type_code': documentTypeCode,
      if (clientVisible != null) 'p_client_visible': clientVisible,
      if (status != null && status!.isNotEmpty) 'p_status': status,
      if (contextType != null && contextType!.isNotEmpty)
        'p_context_type': contextType,
    };
  }

  OwnerAdminDocumentFilters copyWith({
    String? projectId,
    String? documentTypeCode,
    bool? clientVisible,
    String? status,
    String? contextType,
    bool clearProject = false,
    bool clearDocumentType = false,
    bool clearClientVisible = false,
    bool clearStatus = false,
    bool clearContextType = false,
  }) {
    return OwnerAdminDocumentFilters(
      projectId: clearProject ? null : projectId ?? this.projectId,
      documentTypeCode: clearDocumentType
          ? null
          : documentTypeCode ?? this.documentTypeCode,
      clientVisible: clearClientVisible
          ? null
          : clientVisible ?? this.clientVisible,
      status: clearStatus ? null : status ?? this.status,
      contextType: clearContextType ? null : contextType ?? this.contextType,
    );
  }
}

class OwnerAdminDocumentDetailState {
  const OwnerAdminDocumentDetailState._({
    required this.isLoading,
    this.mutationPhase = DocumentLifecycleMutationPhase.idle,
    this.document,
    this.error,
    this.mutationError,
  });

  const OwnerAdminDocumentDetailState.loading() : this._(isLoading: true);

  const OwnerAdminDocumentDetailState.loaded(SafeDocument document)
    : this._(isLoading: false, document: document);

  const OwnerAdminDocumentDetailState.failure(Object error)
    : this._(isLoading: false, error: error);

  final bool isLoading;
  final DocumentLifecycleMutationPhase mutationPhase;
  final SafeDocument? document;
  final Object? error;
  final Object? mutationError;

  bool get isMutating =>
      mutationPhase == DocumentLifecycleMutationPhase.running;

  OwnerAdminDocumentDetailState copyWith({
    bool? isLoading,
    DocumentLifecycleMutationPhase? mutationPhase,
    SafeDocument? document,
    Object? error,
    Object? mutationError,
    bool clearMutationError = false,
  }) {
    return OwnerAdminDocumentDetailState._(
      isLoading: isLoading ?? this.isLoading,
      mutationPhase: mutationPhase ?? this.mutationPhase,
      document: document ?? this.document,
      error: error ?? this.error,
      mutationError: clearMutationError
          ? null
          : mutationError ?? this.mutationError,
    );
  }
}

class DocumentLifecycleMutationResult {
  const DocumentLifecycleMutationResult({
    required this.documentId,
    required this.status,
    this.replacementDocumentId,
    this.requestId,
  });

  factory DocumentLifecycleMutationResult.fromJson(Map<String, dynamic> json) {
    return DocumentLifecycleMutationResult(
      documentId: _requiredString(json, 'document_id', fallbackKey: 'id'),
      status: _requiredDocumentStatus(json, 'status'),
      replacementDocumentId: _string(json, 'replacement_document_id'),
      requestId: _string(json, 'request_id'),
    );
  }

  final String documentId;
  final String status;
  final String? replacementDocumentId;
  final String? requestId;
}

class SafeDocument {
  const SafeDocument({
    required this.id,
    required this.documentNumber,
    required this.safeDisplayFileName,
    required this.mimeType,
    required this.documentTypeCode,
    required this.status,
    this.fileSizeBytes,
    this.createdAt,
    this.finalizedAt,
    this.clientVisible,
    this.lifecycle,
    this.context,
    this.photograph,
  });

  factory SafeDocument.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id', fallbackKey: 'document_id');
    final documentNumber = _requiredString(json, 'document_number');
    final fileName = _requiredString(
      json,
      'original_file_name',
      fallbackKey: 'safe_display_file_name',
    );
    final status = _requiredDocumentStatus(json, 'status');
    return SafeDocument(
      id: id,
      documentNumber: documentNumber,
      safeDisplayFileName: _sanitizeFileName(fileName),
      mimeType: _requiredString(json, 'mime_type'),
      documentTypeCode: _requiredString(json, 'document_type_code'),
      status: status,
      fileSizeBytes: _int(json, 'file_size_bytes'),
      createdAt: _date(json, 'created_at') ?? _date(json, 'uploaded_at'),
      finalizedAt: _date(json, 'finalized_at'),
      clientVisible: json['client_visible'] is bool
          ? json['client_visible'] as bool
          : null,
      lifecycle: DocumentLifecycleSummary.maybeFromJson(json),
      context: DocumentContext.maybeFromJson(json),
      photograph: PhotographSummary.maybeFromJson(json),
    );
  }

  factory SafeDocument.fromClientContextJson(Map<String, dynamic> json) {
    return SafeDocument.fromJson({
      'status': 'ACTIVE',
      ...json,
      if (!json.containsKey('status')) 'status': 'ACTIVE',
    });
  }

  final String id;
  final String documentNumber;
  final String safeDisplayFileName;
  final String mimeType;
  final String documentTypeCode;
  final String status;
  final int? fileSizeBytes;
  final DateTime? createdAt;
  final DateTime? finalizedAt;
  final bool? clientVisible;
  final DocumentLifecycleSummary? lifecycle;
  final DocumentContext? context;
  final PhotographSummary? photograph;

  bool get isPhotograph =>
      documentTypeCode == 'PROGRESS_PHOTOGRAPH' ||
      documentTypeCode == 'TASK_ATTACHMENT' && photograph != null;
}

class DocumentContext {
  const DocumentContext({
    this.clientId,
    this.projectId,
    this.taskId,
    this.progressUpdateId,
    this.clientPaymentId,
  });

  static DocumentContext? maybeFromJson(Map<String, dynamic> json) {
    final context = DocumentContext(
      clientId: _string(json, 'client_id'),
      projectId: _string(json, 'project_id'),
      taskId: _string(json, 'task_id'),
      progressUpdateId: _string(json, 'progress_update_id'),
      clientPaymentId: _string(json, 'client_payment_id'),
    );
    return context.hasAny ? context : null;
  }

  final String? clientId;
  final String? projectId;
  final String? taskId;
  final String? progressUpdateId;
  final String? clientPaymentId;

  bool get hasAny =>
      clientId != null ||
      projectId != null ||
      taskId != null ||
      progressUpdateId != null ||
      clientPaymentId != null;
}

class DocumentLifecycleSummary {
  const DocumentLifecycleSummary({
    required this.status,
    required this.isSuperseded,
    this.supersededByDocumentId,
    this.replacesDocumentId,
    this.archivedAt,
  });

  static DocumentLifecycleSummary? maybeFromJson(Map<String, dynamic> json) {
    final hasLifecycle =
        json.containsKey('is_superseded') ||
        json.containsKey('superseded_by_document_id') ||
        json.containsKey('replaces_document_id') ||
        json.containsKey('archived_at');
    if (!hasLifecycle) {
      return null;
    }
    return DocumentLifecycleSummary(
      status: _requiredDocumentStatus(json, 'status'),
      isSuperseded: json['is_superseded'] == true,
      supersededByDocumentId: _string(json, 'superseded_by_document_id'),
      replacesDocumentId: _string(json, 'replaces_document_id'),
      archivedAt: _date(json, 'archived_at'),
    );
  }

  final String status;
  final bool isSuperseded;
  final String? supersededByDocumentId;
  final String? replacesDocumentId;
  final DateTime? archivedAt;
}

class PhotographSummary {
  const PhotographSummary({
    required this.processingState,
    required this.thumbnailAvailable,
    required this.previewAvailable,
  });

  static PhotographSummary? maybeFromJson(Map<String, dynamic> json) {
    final processingState =
        _string(json, 'processing_status') ??
        _string(json, 'photograph_processing_status');
    final thumbnailAvailable =
        json['thumbnail_available'] == true || processingState == 'READY';
    final previewAvailable =
        json['preview_available'] == true || processingState == 'READY';
    if (processingState == null && !thumbnailAvailable && !previewAvailable) {
      return null;
    }
    return PhotographSummary(
      processingState: processingState ?? 'UNKNOWN',
      thumbnailAvailable: thumbnailAvailable,
      previewAvailable: previewAvailable,
    );
  }

  final String processingState;
  final bool thumbnailAvailable;
  final bool previewAvailable;
}

class DocumentUploadRequest {
  const DocumentUploadRequest({
    required this.originalFileName,
    required this.mimeType,
    required this.bytes,
    this.documentTypeCode,
    this.clientVisible = false,
    this.clientId,
    this.projectId,
    this.taskId,
    this.progressUpdateId,
    this.clientPaymentId,
    this.processPhotograph = false,
  });

  final String originalFileName;
  final String mimeType;
  final Uint8List bytes;
  final String? documentTypeCode;
  final bool clientVisible;
  final String? clientId;
  final String? projectId;
  final String? taskId;
  final String? progressUpdateId;
  final String? clientPaymentId;
  final bool processPhotograph;

  bool get isClientTransferEvidence =>
      clientPaymentId != null && documentTypeCode == null;
}

class DocumentUploadSession {
  const DocumentUploadSession({
    required this.uploadId,
    required this.expiresAt,
    required this.maxFileSizeBytes,
    required this.allowedMimeTypes,
  });

  factory DocumentUploadSession.fromJson(Map<String, dynamic> json) {
    return DocumentUploadSession(
      uploadId: _requiredString(json, 'upload_id'),
      expiresAt: _requiredDate(json, 'expires_at'),
      maxFileSizeBytes: _requiredPositiveInt(json, 'max_file_size_bytes'),
      allowedMimeTypes: (json['allowed_mime_types'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  final String uploadId;
  final DateTime expiresAt;
  final int maxFileSizeBytes;
  final List<String> allowedMimeTypes;
}

class DocumentUploadResult {
  const DocumentUploadResult({
    required this.uploadId,
    required this.status,
    this.reservedDocumentId,
  });

  factory DocumentUploadResult.fromJson(Map<String, dynamic> json) {
    final status = _requiredUploadStatus(json, 'status');
    return DocumentUploadResult(
      uploadId: _requiredString(json, 'upload_id'),
      status: status,
      reservedDocumentId: _string(json, 'reserved_document_id'),
    );
  }

  final String uploadId;
  final String status;
  final String? reservedDocumentId;

  bool get awaitingScan => status == 'AWAITING_SCAN';
  bool get finalized => status == 'FINALIZED';
}

class DocumentScanResult {
  const DocumentScanResult({
    required this.uploadId,
    required this.status,
    this.documentId,
  });

  factory DocumentScanResult.fromJson(Map<String, dynamic> json) {
    return DocumentScanResult(
      uploadId: _requiredString(json, 'upload_id'),
      status: _requiredUploadStatus(json, 'status'),
      documentId: _string(json, 'document_id'),
    );
  }

  final String uploadId;
  final String status;
  final String? documentId;

  bool get finalized => status == 'FINALIZED' && documentId != null;
  bool get quarantined => status == 'QUARANTINED';
  bool get scanFailed => status == 'SCAN_FAILED';
  bool get scanInProgress => status == 'SCAN_IN_PROGRESS';
}

class DocumentUploadState {
  const DocumentUploadState({
    required this.phase,
    this.uploadId,
    this.documentId,
    this.error,
  });

  const DocumentUploadState.idle() : this(phase: DocumentUploadPhase.idle);

  final DocumentUploadPhase phase;
  final String? uploadId;
  final String? documentId;
  final Object? error;

  DocumentUploadState copyWith({
    DocumentUploadPhase? phase,
    String? uploadId,
    String? documentId,
    Object? error,
  }) {
    return DocumentUploadState(
      phase: phase ?? this.phase,
      uploadId: uploadId ?? this.uploadId,
      documentId: documentId ?? this.documentId,
      error: error,
    );
  }
}

class SecureDocumentAccess {
  const SecureDocumentAccess({
    required this.bytes,
    required this.mimeType,
    required this.safeFileName,
  });

  final Uint8List bytes;
  final String mimeType;
  final String safeFileName;
}

String _sanitizeFileName(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'[\r\n"\\/]+'), '_')
      .replaceAll(RegExp(r'\.\.+'), '.');
}

String? _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String && value.isNotEmpty ? value : null;
}

int? _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? DateTime.tryParse(value) : null;
}

String _requiredString(
  Map<String, dynamic> json,
  String key, {
  String? fallbackKey,
}) {
  final value =
      _string(json, key) ??
      (fallbackKey == null ? null : _string(json, fallbackKey));
  if (value == null) {
    throw DocumentParseFailure('Required document field is missing: $key.');
  }
  return value;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _date(json, key);
  if (value == null) {
    throw DocumentParseFailure('Required document date is invalid: $key.');
  }
  return value;
}

int _requiredPositiveInt(Map<String, dynamic> json, String key) {
  final raw = json[key];
  final value = raw is int ? raw : null;
  if (value == null || value <= 0) {
    throw DocumentParseFailure('Required document number is invalid: $key.');
  }
  return value;
}

String _requiredDocumentStatus(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  if (!{'ACTIVE', 'ARCHIVED'}.contains(value)) {
    throw DocumentParseFailure('Document status is not recognized.');
  }
  return value;
}

String _requiredUploadStatus(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  if (!{
    'AWAITING_SCAN',
    'SCAN_IN_PROGRESS',
    'QUARANTINED',
    'SCAN_FAILED',
    'FINALIZED',
  }.contains(value)) {
    throw DocumentParseFailure('Upload status is not recognized.');
  }
  return value;
}
