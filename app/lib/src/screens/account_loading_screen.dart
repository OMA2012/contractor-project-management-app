import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';

class AccountLoadingScreen extends ConsumerWidget {
  const AccountLoadingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final account = ref.watch(currentAccountProvider);
    final subtitle = switch (account) {
      CurrentAccountFailure() => 'Unable to load account access.',
      _ => session.email ?? 'Checking account access',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Contractor Projects')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account loading',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(subtitle),
                if (account is CurrentAccountFailure) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        ref.read(currentAccountProvider.notifier).load(),
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
