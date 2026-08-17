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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => context.go('/staff/clients'),
                          icon: const Icon(Icons.business),
                          label: const Text('Clients'),
                        ),
                        FilledButton.icon(
                          onPressed: () => context.go('/staff/projects'),
                          icon: const Icon(Icons.work),
                          label: const Text('Projects'),
                        ),
                        FilledButton.icon(
                          onPressed: () => context.go('/staff/documents'),
                          icon: const Icon(Icons.description),
                          label: const Text('Documents'),
                        ),
                        FilledButton.icon(
                          onPressed: () =>
                              context.go('/staff/opening-balances'),
                          icon: const Icon(Icons.account_balance_wallet),
                          label: const Text('Opening balances'),
                        ),
                        FilledButton.icon(
                          onPressed: () =>
                              context.go('/staff/account-transfers'),
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Account transfers'),
                        ),
                        FilledButton.icon(
                          onPressed: () =>
                              context.go('/staff/currency-exchanges'),
                          icon: const Icon(Icons.currency_exchange),
                          label: const Text('Currency exchanges'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.go('/staff/financial-approval-queue'),
                          icon: const Icon(Icons.verified_user),
                          label: const Text('Approval queue'),
                        ),
                      ],
                    ),
                  ],
                  if (role == AccountRole.client) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => context.go('/client/projects'),
                          icon: const Icon(Icons.business_center),
                          label: const Text('Projects'),
                        ),
                        FilledButton.icon(
                          onPressed: () => context.go('/client/payments'),
                          icon: const Icon(Icons.payments),
                          label: const Text('Payments'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.go('/client/payment-requests'),
                          icon: const Icon(Icons.request_quote),
                          label: const Text('Payment requests'),
                        ),
                      ],
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
