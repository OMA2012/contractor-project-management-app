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
    },
  );
}
