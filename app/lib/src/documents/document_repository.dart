import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'document_models.dart';

typedef DocumentRpc =
    Future<dynamic> Function(
      String functionName, {
      Map<String, dynamic>? params,
    });
typedef DocumentFunctionInvoke =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);
typedef DocumentUploadBytes =
    Future<void> Function(
      DocumentUploadCredential authorization,
      Uint8List bytes,
    );
typedef DocumentAccessTokenProvider = Future<String?> Function();

abstract class DocumentAccessClient {
  Future<DocumentAccessResponse> post(
    String functionName,
    Map<String, dynamic> body,
  );
}

class DocumentAccessResponse {
  const DocumentAccessResponse({
    required this.statusCode,
    required this.bytes,
    required this.headers,
  });

  final int statusCode;
  final Uint8List bytes;
  final Map<String, String> headers;
}

abstract class DocumentRepository {
  Future<List<SafeDocument>> listClientDocuments({
    int limit = 50,
    int offset = 0,
  });

  Future<SecureDocumentAccess> requestDocumentAccess(
    String documentId,
    DocumentAccessPurpose purpose,
  );

  Future<SecureDocumentAccess> requestPhotographThumbnail(String documentId);

  Future<SecureDocumentAccess> requestPhotographPreview(String documentId);

  Future<SecureDocumentAccess> requestOwnerAdminOriginalPhotograph(
    String documentId,
  );

  Future<DocumentUploadSession> authorizeUpload(DocumentUploadRequest request);

  Future<void> uploadAuthorizedBytes(
    DocumentUploadSession session,
    Uint8List bytes,
  );

  Future<DocumentUploadResult> completeUpload(String uploadId);

  Future<PhotographSummary> processPhotograph(String documentId);

  Future<DocumentUploadSession> authorizeClientTransferEvidenceUpload(
    DocumentUploadRequest request,
  );
}

class SupabaseDocumentRepository implements DocumentRepository {
  SupabaseDocumentRepository({
    this.supabaseClient,
    this.rpc,
    this.invokeFunction,
    this.uploadBytes,
    this.accessClient,
    this.config = const AppConfig.fromEnvironment(),
  });

  final SupabaseClient? supabaseClient;
  final DocumentRpc? rpc;
  final DocumentFunctionInvoke? invokeFunction;
  final DocumentUploadBytes? uploadBytes;
  final DocumentAccessClient? accessClient;
  final AppConfig config;
  final Map<String, DocumentUploadCredential> _authorizations =
      <String, DocumentUploadCredential>{};

  SupabaseClient get client => supabaseClient ?? Supabase.instance.client;

  @override
  Future<List<SafeDocument>> listClientDocuments({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _rpc('current_client_document_list', {
      'p_limit': limit,
      'p_offset': offset,
    });
    return _rows(response).map(SafeDocument.fromJson).toList(growable: false);
  }

  @override
  Future<SecureDocumentAccess> requestDocumentAccess(
    String documentId,
    DocumentAccessPurpose purpose,
  ) {
    return _accessDocument(
      documentId: documentId,
      body: {'document_id': documentId, 'purpose': purpose.name},
    );
  }

  @override
  Future<SecureDocumentAccess> requestPhotographThumbnail(String documentId) {
    return _accessDocument(
      documentId: documentId,
      body: {'document_id': documentId, 'mode': 'thumbnail'},
    );
  }

  @override
  Future<SecureDocumentAccess> requestPhotographPreview(String documentId) {
    return _accessDocument(
      documentId: documentId,
      body: {'document_id': documentId, 'mode': 'preview'},
    );
  }

  @override
  Future<SecureDocumentAccess> requestOwnerAdminOriginalPhotograph(
    String documentId,
  ) {
    return _accessDocument(
      documentId: documentId,
      body: {'document_id': documentId, 'mode': 'original'},
    );
  }

  @override
  Future<DocumentUploadSession> authorizeUpload(
    DocumentUploadRequest request,
  ) async {
    if (request.isClientTransferEvidence) {
      throw const DocumentFailure(
        'Client transfer evidence uses the narrow evidence workflow.',
      );
    }
    final envelope = await _function('document-upload-authorize', {
      'original_file_name': request.originalFileName,
      'mime_type': request.mimeType,
      'document_type_code': request.documentTypeCode,
      'client_visible': request.clientVisible,
      if (request.clientId != null) 'client_id': request.clientId,
      if (request.projectId != null) 'project_id': request.projectId,
      if (request.taskId != null) 'task_id': request.taskId,
      if (request.progressUpdateId != null)
        'progress_update_id': request.progressUpdateId,
    });
    final authorization = DocumentUploadCredential._fromJson(_data(envelope));
    _rememberAuthorization(authorization);
    return authorization.session;
  }

  @override
  Future<DocumentUploadSession> authorizeClientTransferEvidenceUpload(
    DocumentUploadRequest request,
  ) async {
    if (!request.isClientTransferEvidence) {
      throw const DocumentFailure(
        'Transfer evidence authorization requires a client payment ID only.',
      );
    }
    final envelope = await _function('document-upload-authorize', {
      'original_file_name': request.originalFileName,
      'mime_type': request.mimeType,
      'client_payment_id': request.clientPaymentId,
    });
    final authorization = DocumentUploadCredential._fromJson(_data(envelope));
    _rememberAuthorization(authorization);
    return authorization.session;
  }

  @override
  Future<void> uploadAuthorizedBytes(
    DocumentUploadSession session,
    Uint8List bytes,
  ) async {
    final authorization = _takeAuthorization(session.uploadId);
    if (uploadBytes != null) {
      await uploadBytes!(authorization, bytes);
      return;
    }
    await _putSignedUpload(authorization, bytes);
  }

  @override
  Future<DocumentUploadResult> completeUpload(String uploadId) async {
    final envelope = await _function('document-upload-complete', {
      'upload_id': uploadId,
    });
    return DocumentUploadResult.fromJson(_data(envelope));
  }

  @override
  Future<PhotographSummary> processPhotograph(String documentId) async {
    final envelope = await _function('document-process-photograph', {
      'document_id': documentId,
    });
    final data = _data(envelope);
    return PhotographSummary(
      processingState: data['status'] as String? ?? 'UNKNOWN',
      thumbnailAvailable: data['thumbnail'] == 'ready',
      previewAvailable: data['preview'] == 'ready',
    );
  }

  Future<dynamic> _rpc(String functionName, Map<String, dynamic> params) {
    if (rpc != null) {
      return rpc!(functionName, params: params);
    }
    return client.rpc(functionName, params: params);
  }

  Future<dynamic> _function(String functionName, Map<String, dynamic> body) {
    if (invokeFunction != null) {
      return invokeFunction!(functionName, body);
    }
    return client.functions.invoke(functionName, body: body);
  }

  Future<SecureDocumentAccess> _accessDocument({
    required String documentId,
    required Map<String, dynamic> body,
  }) async {
    final response = await _binaryAccessClient().post('document-access', body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DocumentFailure(
        'Document access failed with status ${response.statusCode}.',
        permissionDenied:
            response.statusCode == 401 || response.statusCode == 403,
      );
    }
    if (response.bytes.isEmpty) {
      throw const DocumentFailure('Document access returned an empty file.');
    }
    final mimeType = _contentType(response.headers);
    if (mimeType == null) {
      throw const DocumentFailure(
        'Document access response did not include a content type.',
      );
    }
    return SecureDocumentAccess(
      bytes: response.bytes,
      mimeType: mimeType,
      safeFileName:
          _safeFileNameFromDisposition(response.headers) ?? documentId,
    );
  }

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is List) {
      return response.cast<Map<String, dynamic>>();
    }
    if (response is Map<String, dynamic>) {
      return [response];
    }
    return const [];
  }

  Map<String, dynamic> _data(dynamic envelope) {
    if (envelope is FunctionResponse) {
      return _data(envelope.data);
    }
    if (envelope is Map<String, dynamic>) {
      final data = envelope['data'];
      if (data is Map<String, dynamic>) return data;
      return envelope;
    }
    throw const DocumentFailure('Document service response was invalid.');
  }

  DocumentAccessClient _binaryAccessClient() {
    return accessClient ??
        SupabaseBinaryDocumentAccessClient(
          functionsUrl: '${config.supabaseUrl}/functions/v1',
          anonKey: config.supabaseAnonKey,
          accessTokenProvider: () async =>
              client.auth.currentSession?.accessToken,
        );
  }

  void _rememberAuthorization(DocumentUploadCredential authorization) {
    _authorizations[authorization.session.uploadId] = authorization;
  }

  DocumentUploadCredential _takeAuthorization(String uploadId) {
    final authorization = _authorizations.remove(uploadId);
    if (authorization == null) {
      throw const DocumentFailure('Upload authorization is not available.');
    }
    return authorization;
  }

  Future<void> _putSignedUpload(
    DocumentUploadCredential authorization,
    Uint8List bytes,
  ) async {
    final response = await http.put(
      Uri.parse(authorization._uploadUrl),
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DocumentFailure(
        'Signed upload failed with status ${response.statusCode}.',
      );
    }
  }
}

String _safeName(String value) {
  return value.trim().replaceAll(RegExp(r'[\r\n"\\/]+'), '_');
}

class SupabaseBinaryDocumentAccessClient implements DocumentAccessClient {
  const SupabaseBinaryDocumentAccessClient({
    required this.functionsUrl,
    required this.anonKey,
    required this.accessTokenProvider,
    this.httpClient,
  });

  final String functionsUrl;
  final String anonKey;
  final DocumentAccessTokenProvider accessTokenProvider;
  final http.Client? httpClient;

  @override
  Future<DocumentAccessResponse> post(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    if (functionsUrl.isEmpty || !Uri.parse(functionsUrl).hasScheme) {
      throw const DocumentFailure(
        'Document access transport is not configured.',
      );
    }
    if (anonKey.isEmpty) {
      throw const DocumentFailure(
        'Document access transport is not configured.',
      );
    }
    final accessToken = await accessTokenProvider();
    if (accessToken == null || accessToken.isEmpty) {
      throw const DocumentFailure(
        'Document access requires an authenticated session.',
        permissionDenied: true,
      );
    }
    final client = httpClient ?? http.Client();
    final closeClient = httpClient == null;
    try {
      final response = await client.post(
        Uri.parse('$functionsUrl/$functionName'),
        headers: {
          'apikey': anonKey,
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      return DocumentAccessResponse(
        statusCode: response.statusCode,
        bytes: response.bodyBytes,
        headers: response.headers,
      );
    } finally {
      if (closeClient) client.close();
    }
  }
}

class DocumentUploadCredential {
  const DocumentUploadCredential._({
    required this.session,
    required this._uploadUrl,
  });

  factory DocumentUploadCredential._fromJson(Map<String, dynamic> json) {
    final method = json['method'];
    final uploadUrl = json['upload_url'];
    if (method is! String || method != 'PUT') {
      throw const DocumentParseFailure('Upload method is invalid.');
    }
    if (uploadUrl is! String || Uri.tryParse(uploadUrl)?.hasScheme != true) {
      throw const DocumentParseFailure('Upload URL is invalid.');
    }
    return DocumentUploadCredential._(
      session: DocumentUploadSession.fromJson(json),
      uploadUrl: uploadUrl,
    );
  }

  final DocumentUploadSession session;
  final String _uploadUrl;
}

String? _contentType(Map<String, String> headers) {
  final value = headers['content-type'] ?? headers['Content-Type'];
  final mime = value?.split(';').first.trim().toLowerCase();
  return mime == null || mime.isEmpty ? null : mime;
}

String? _safeFileNameFromDisposition(Map<String, String> headers) {
  final value =
      headers['content-disposition'] ?? headers['Content-Disposition'];
  if (value == null) return null;
  final match = RegExp(r'filename="([^"]+)"').firstMatch(value);
  final fileName = match?.group(1);
  if (fileName == null || fileName.trim().isEmpty) return null;
  return _safeName(fileName);
}
