import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';
import 'responsive_auth_scaffold.dart';

class InactiveAccountScreen extends ConsumerWidget {
  const InactiveAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final account = ref.watch(currentAccountProvider);
    final title = switch (account.routeTarget) {
      TrustedAccountRouteTarget.notProvisioned => 'Account not provisioned',
      TrustedAccountRouteTarget.pendingInvite => 'Account pending',
      TrustedAccountRouteTarget.suspended => 'Account suspended',
      TrustedAccountRouteTarget.deactivated => 'Account deactivated',
      TrustedAccountRouteTarget.noActiveRole => 'No active role',
      _ => 'Account inactive',
    };

    return ResponsiveAuthScaffold(
      title: title,
      subtitle: session.email ?? 'Contact an administrator to restore access.',
      child: FilledButton(
        onPressed: () => ref.read(authSessionProvider.notifier).signOut(),
        child: const Text('Back to sign in'),
      ),
    );
  }
}
