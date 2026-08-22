import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';

class ProtectedShellScreen extends ConsumerWidget {
  const ProtectedShellScreen({
    required this.location,
    required this.child,
    super.key,
  });

  final Uri location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final account = ref.watch(currentAccountProvider);
    final displayName = switch (account) {
      CurrentAccountLoaded(:final account) => account.fullName,
      _ => null,
    };
    final backDestination = protectedBackDestination(location);
    final childOwnsAppBar =
        location.path.startsWith('/staff/clients') ||
        location.path.startsWith('/staff/projects');

    return Scaffold(
      appBar: AppBar(
        leading: backDestination == null || childOwnsAppBar
            ? null
            : BackButton(
                onPressed: () => navigateBack(context, backDestination),
              ),
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

void navigateBack(BuildContext context, String fallbackLocation) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallbackLocation);
  }
}

String? protectedBackDestination(Uri location) {
  final path = location.path;
  if (path == '/staff' || path == '/client') return null;

  final segments = location.pathSegments;
  if (segments.isEmpty) return null;

  if (segments.first == 'client') {
    if (segments.length == 1) return null;
    if (segments.length == 2) return '/client';
    return '/client/${segments[1]}';
  }

  if (segments.first != 'staff' || segments.length == 1) return null;

  if (segments.length == 2) return '/staff';
  if (segments[1] == 'clients') {
    if (segments[2] == 'new') return '/staff/clients';
    if (segments.length >= 4 && segments[3] == 'edit') {
      return '/staff/clients/${segments[2]}';
    }
    return '/staff/clients';
  }
  if (segments[1] == 'projects') {
    if (segments[2] == 'new') {
      final clientId = location.queryParameters['clientId'];
      return clientId == null ? '/staff/projects' : '/staff/clients/$clientId';
    }
    if (segments.length >= 4 && segments[3] == 'edit') {
      return '/staff/projects/${segments[2]}';
    }
    return '/staff/projects';
  }
  return '/staff/${segments[1]}';
}
