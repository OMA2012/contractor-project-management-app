import 'document_file_services.dart';

DocumentContentPresenter createDocumentContentPresenter() {
  return const UnsupportedDocumentContentPresenter();
}

class UnsupportedDocumentContentPresenter implements DocumentContentPresenter {
  const UnsupportedDocumentContentPresenter();

  @override
  Future<void> preview(DocumentPresentationContent content) {
    throw const DocumentPresentationFailure(
      'Document preview is not available on this platform.',
    );
  }

  @override
  Future<void> download(DocumentPresentationContent content) {
    throw const DocumentPresentationFailure(
      'Document download is not available on this platform.',
    );
  }
}

class DocumentPresentationFailure implements Exception {
  const DocumentPresentationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
