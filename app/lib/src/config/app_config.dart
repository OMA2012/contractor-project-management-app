class AppConfig {
  const AppConfig({required this.supabaseUrl, required this.supabaseAnonKey});

  const AppConfig.fromEnvironment()
    : supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');

  final String supabaseUrl;
  final String supabaseAnonKey;

  bool get hasSupabasePublicClientConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
