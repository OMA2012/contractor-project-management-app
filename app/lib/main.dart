import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/supabase/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  const config = AppConfig.fromEnvironment();
  await initializeSupabase(config);

  runApp(const ProviderScope(child: ContractorProjectManagementApp()));
}
