import 'package:contractor_project_management/src/config/app_config.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports missing Supabase public client configuration', () {
    const config = AppConfig(supabaseUrl: '', supabaseAnonKey: '');

    expect(config.hasSupabasePublicClientConfig, isFalse);
  });

  test('reports present Supabase public client configuration', () {
    const config = AppConfig(
      supabaseUrl: 'https://example.supabase.co',
      supabaseAnonKey: 'public-anon-key',
    );

    expect(config.hasSupabasePublicClientConfig, isTrue);
  });

  test('example environment uses the Flutter public-key name only', () async {
    final example = await File('../.env.example').readAsString();

    expect(example, contains('SUPABASE_ANON_KEY='));
    expect(example, isNot(contains('SUPABASE_PUBLISHABLE_KEY=')));
    expect(example, isNot(contains('SUPABASE_SERVICE_ROLE_KEY=ey')));
  });

  test(
    'handler-auth function deployment config disables gateway JWT check',
    () async {
      final config = await File('../supabase/config.toml').readAsString();
      for (final name in [
        'account-transfers',
        'client-payments',
        'currency-exchanges',
        'document-process-photograph',
        'document-scan-finalize',
        'opening-balances',
        'project-expenses',
      ]) {
        expect(
          config,
          matches(
            RegExp(
              '\\[functions\\.${RegExp.escape(name)}\\]\\r?\\nverify_jwt = false',
            ),
          ),
          reason: name,
        );
      }
    },
  );
}
