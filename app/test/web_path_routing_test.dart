import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startup configures Flutter path URL strategy before runApp', () async {
    final mainSource = await File('lib/main.dart').readAsString();

    expect(
      mainSource,
      contains("package:flutter_web_plugins/url_strategy.dart"),
    );
    expect(mainSource, contains('usePathUrlStrategy();'));
    expect(
      mainSource.indexOf('usePathUrlStrategy();'),
      lessThan(mainSource.indexOf('runApp(')),
    );
    expect(mainSource, isNot(contains('HashUrlStrategy')));
  });

  test('auth and invitation routes remain normal path routes', () async {
    final routerSource = await File(
      'lib/src/routing/app_router.dart',
    ).readAsString();

    for (final path in const [
      '/login',
      '/update-password',
      '/accept-invitation',
      '/owner/activate',
    ]) {
      expect(routerSource, contains("path: '$path'"));
    }

    final applicationSources = await Future.wait(
      await Directory('lib')
          .list(recursive: true)
          .where((entry) => entry is File && entry.path.endsWith('.dart'))
          .cast<File>()
          .map((file) => file.readAsString())
          .toList(),
    );
    expect(applicationSources.join('\n'), isNot(contains('#/')));
  });
}
