import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_session.dart';
import 'responsive_auth_scaffold.dart';

class InactiveAccountScreen extends ConsumerWidget {
  const InactiveAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);

    return ResponsiveAuthScaffold(
      title: 'Account inactive',
      subtitle: session.email ?? 'Contact an administrator to restore access.',
      child: FilledButton(
        onPressed: () => ref.read(authSessionProvider.notifier).signOut(),
        child: const Text('Back to sign in'),
      ),
    );
  }
}
