// ignore_for_file: deprecated_member_use
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'document_file_services.dart';

DocumentContentPresenter createDocumentContentPresenter() {
  return const WebDocumentContentPresenter();
}

class WebDocumentContentPresenter implements DocumentContentPresenter {
  const WebDocumentContentPresenter();

  @override
  Future<void> preview(DocumentPresentationContent content) async {
    final url = _objectUrl(content);
    html.window.open(url, '_blank', 'noopener,noreferrer');
    Future<void>.delayed(
      const Duration(seconds: 5),
    ).then((_) => html.Url.revokeObjectUrl(url));
  }

  @override
  Future<void> download(DocumentPresentationContent content) async {
    final url = _objectUrl(content);
    final anchor = html.AnchorElement(href: url)
      ..download = content.safeFileName
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  String _objectUrl(DocumentPresentationContent content) {
    final blob = html.Blob([content.bytes], content.mimeType);
    return html.Url.createObjectUrlFromBlob(blob);
  }
}
