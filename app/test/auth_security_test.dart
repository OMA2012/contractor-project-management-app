import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'production auth code does not infer roles from user metadata',
    () async {
      final authCode = await File(
        'lib/src/auth/auth_session.dart',
      ).readAsString();

      expect(authCode, isNot(contains('userMetadata')));
      expect(authCode, isNot(contains('appMetadata')));
      expect(authCode, isNot(contains('rawUserMetaData')));
      expect(authCode, isNot(contains('rawAppMetaData')));
      expect(authCode, isNot(contains('email.endsWith')));
      expect(authCode, isNot(contains('localStorage')));
      expect(authCode, isNot(contains('service_role')));
    },
  );

  test('Flutter never contains scanner credentials or verdict logic', () async {
    final repositoryCode = await File(
      'lib/src/documents/document_repository.dart',
    ).readAsString();
    final providerCode = await File(
      'lib/src/documents/document_providers.dart',
    ).readAsString();
    final flutterCode = '$repositoryCode\n$providerCode';

    expect(flutterCode, isNot(contains('DOCUMENT_SCANNER_TOKEN')));
    expect(flutterCode, isNot(contains('DOCUMENT_SCANNER_URL')));
    expect(flutterCode, isNot(contains('malware_name')));
    expect(flutterCode, isNot(contains('service_role')));
  });
}
