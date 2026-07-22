import 'package:contractor_project_management/src/config/app_config.dart';
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
}
