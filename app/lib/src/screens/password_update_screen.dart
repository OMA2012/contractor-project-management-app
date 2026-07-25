import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_session.dart';
import 'responsive_auth_scaffold.dart';

class PasswordUpdateScreen extends ConsumerWidget {
  const PasswordUpdateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ResponsiveAuthScaffold(
      title: 'Update password',
      subtitle: 'Choose a new password to continue.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TextField(
            obscureText: true,
            decoration: InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              ref.read(authSessionProvider.notifier).updatePassword();
            },
            child: const Text('Update password'),
          ),
        ],
      ),
    );
  }
}
