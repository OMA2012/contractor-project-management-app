import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/supabase/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const config = AppConfig.fromEnvironment();
  await initializeSupabase(config);

  runApp(const ProviderScope(child: ContractorProjectManagementApp()));
}
