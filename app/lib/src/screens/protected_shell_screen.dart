import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';

class ProtectedShellScreen extends ConsumerWidget {
  const ProtectedShellScreen({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final account = ref.watch(currentAccountProvider);
    final displayName = switch (account) {
      CurrentAccountLoaded(:final account) => account.fullName,
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contractor Projects'),
        actions: [
          if (account.routeTarget == TrustedAccountRouteTarget.staff)
            IconButton(
              tooltip: 'Photographs',
              onPressed: () => context.go('/staff/photographs'),
              icon: const Icon(Icons.photo_library),
            ),
          if (account.routeTarget == TrustedAccountRouteTarget.client)
            PopupMenuButton<String>(
              tooltip: 'Client navigation',
              icon: const Icon(Icons.menu),
              onSelected: context.go,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: '/client/projects',
                  child: ListTile(
                    leading: Icon(Icons.business_center),
                    title: Text('Projects'),
                  ),
                ),
                PopupMenuItem(
                  value: '/client/payments',
                  child: ListTile(
                    leading: Icon(Icons.payments),
                    title: Text('Payments'),
                  ),
                ),
                PopupMenuItem(
                  value: '/client/payment-requests',
                  child: ListTile(
                    leading: Icon(Icons.request_quote),
                    title: Text('Payment Requests'),
                  ),
                ),
                PopupMenuItem(
                  value: '/client/photographs',
                  child: ListTile(
                    leading: Icon(Icons.photo_library),
                    title: Text('Photographs'),
                  ),
                ),
                PopupMenuItem(
                  value: '/client/notifications',
                  child: ListTile(
                    leading: Icon(Icons.notifications),
                    title: Text('Notifications'),
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(displayName ?? session.email ?? 'Signed in'),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => ref.read(authSessionProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: child,
    );
  }
}
