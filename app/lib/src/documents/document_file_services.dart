import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'document_file_services_web.dart'
    if (dart.library.io) 'document_file_services_stub.dart';

final documentFilePickerProvider = Provider<DocumentFilePicker>(
  (ref) => const FilePickerDocumentFilePicker(),
);

final documentContentPresenterProvider = Provider<DocumentContentPresenter>(
  (ref) => createDocumentContentPresenter(),
);

class SelectedDocumentFile {
  const SelectedDocumentFile({
    required this.safeFileName,
    required this.mimeType,
    required this.bytes,
  });

  final String safeFileName;
  final String mimeType;
  final Uint8List bytes;

  int get sizeBytes => bytes.lengthInBytes;
}

abstract class DocumentFilePicker {
  Future<SelectedDocumentFile?> pickDocumentFile();
}

abstract class DocumentContentPresenter {
  Future<void> preview(DocumentPresentationContent content);

  Future<void> download(DocumentPresentationContent content);
}

class DocumentPresentationContent {
  const DocumentPresentationContent({
    required this.bytes,
    required this.mimeType,
    required this.safeFileName,
  });

  final Uint8List bytes;
  final String mimeType;
  final String safeFileName;
}

class FilePickerDocumentFilePicker implements DocumentFilePicker {
  const FilePickerDocumentFilePicker();

  @override
  Future<SelectedDocumentFile?> pickDocumentFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || bytes.isEmpty) {
      return null;
    }
    return SelectedDocumentFile(
      safeFileName: _safeName(file.name),
      mimeType: 'application/octet-stream',
      bytes: bytes,
    );
  }
}

String _safeName(String value) {
  final sanitized = value
      .trim()
      .replaceAll(RegExp(r'[\r\n"\\/]+'), '_')
      .replaceAll(RegExp(r'\.\.+'), '.');
  return sanitized.isEmpty ? 'document' : sanitized;
}
