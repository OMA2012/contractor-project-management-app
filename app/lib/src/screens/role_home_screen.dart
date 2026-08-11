import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_session.dart';

class RoleHomeScreen extends StatelessWidget {
  const RoleHomeScreen({required this.role, super.key});

  final AccountRole role;

  @override
  Widget build(BuildContext context) {
    final label = switch (role) {
      AccountRole.staff => 'Staff workspace',
      AccountRole.client => 'Client workspace',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 760 : 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Protected shell placeholder'),
                  if (role == AccountRole.staff) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.go('/staff/documents'),
                      icon: const Icon(Icons.description),
                      label: const Text('Documents'),
                    ),
                  ],
                  if (role == AccountRole.client) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.go('/client/projects'),
                      icon: const Icon(Icons.business_center),
                      label: const Text('Projects'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
