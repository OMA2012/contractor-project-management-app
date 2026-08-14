import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../dashboard/client_dashboard_models.dart';
import '../dashboard/client_dashboard_providers.dart';
import '../notifications/notification_models.dart';
import '../notifications/notification_providers.dart';
import '../payments/payment_models.dart';
import '../payments/payment_providers.dart';

class ClientDashboardScreen extends ConsumerStatefulWidget {
  const ClientDashboardScreen({super.key});

  @override
  ConsumerState<ClientDashboardScreen> createState() =>
      _ClientDashboardScreenState();
}

class _ClientDashboardScreenState extends ConsumerState<ClientDashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (!mounted) return;
      ref.read(clientPaymentRequestListProvider.notifier).load(limit: 3);
      ref.read(clientApprovedPaymentListProvider.notifier).load(limit: 3);
      ref.read(clientNotificationListProvider.notifier).load(limit: 3);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(clientDashboardProvider);
    final account = ref.watch(currentAccountProvider);
    final name = switch (account) {
      CurrentAccountLoaded(:final account) => account.fullName,
      _ => null,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.read(clientDashboardProvider.notifier).refresh(),
              ref
                  .read(clientPaymentRequestListProvider.notifier)
                  .load(limit: 3),
              ref
                  .read(clientApprovedPaymentListProvider.notifier)
                  .load(limit: 3),
              ref.read(clientNotificationListProvider.notifier).load(limit: 3),
            ]);
          },
          child: ListView(
            padding: EdgeInsets.all(isWide ? 24 : 16),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _welcome(name),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    if (dashboard.isLoading)
                      const _LoadingCard()
                    else if (dashboard.error != null)
                      _ErrorCard(
                        onRetry: () => ref
                            .read(clientDashboardProvider.notifier)
                            .refresh(),
                      )
                    else ...[
                      _Section(
                        title: 'My projects',
                        actionLabel: 'View all',
                        onAction: () => context.go('/client/projects'),
                        child: _ProjectSummaryList(
                          projects: dashboard.projects,
                          isWide: isWide,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _Section(
                        title: 'Recent updates',
                        child: _RecentUpdateList(
                          items: dashboard.recentUpdates,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _ResponsiveColumns(
                      isWide: isWide,
                      children: [
                        _Section(
                          title: 'Payment requests',
                          actionLabel: 'View all',
                          onAction: () =>
                              context.go('/client/payment-requests'),
                          child: _PaymentRequestList(
                            state: ref.watch(clientPaymentRequestListProvider),
                          ),
                        ),
                        _Section(
                          title: 'Recent payments',
                          actionLabel: 'View all',
                          onAction: () => context.go('/client/payments'),
                          child: _PaymentList(
                            state: ref.watch(clientApprovedPaymentListProvider),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!dashboard.isLoading && dashboard.error == null) ...[
                      _Section(
                        title: 'Recent activity',
                        child: _ActivityList(items: dashboard.recentActivity),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _ResponsiveColumns(
                      isWide: isWide,
                      children: [
                        _Section(
                          title: 'Files and media',
                          child: const _FilesMediaActions(),
                        ),
                        _Section(
                          title: 'Notifications',
                          actionLabel: 'View all',
                          onAction: () => context.go('/client/notifications'),
                          child: _NotificationList(
                            state: ref.watch(clientNotificationListProvider),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _welcome(String? name) {
    final safe = name?.trim();
    return safe == null || safe.isEmpty ? 'Welcome' : 'Welcome, $safe';
  }
}

class _ResponsiveColumns extends StatelessWidget {
  const _ResponsiveColumns({required this.isWide, required this.children});

  final bool isWide;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!isWide) {
      return Column(
        children: [
          for (final child in children) ...[child, const SizedBox(height: 16)],
        ]..removeLast(),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          Expanded(child: children[index]),
          if (index < children.length - 1) const SizedBox(width: 16),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ProjectSummaryList extends StatelessWidget {
  const _ProjectSummaryList({required this.projects, required this.isWide});

  final List<ClientDashboardProjectSummary> projects;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return const _SafeMessage('No projects are currently available.');
    }
    if (!isWide) {
      return Column(
        children: [
          for (final project in projects) ...[
            SizedBox(height: 230, child: _ProjectCard(project)),
            const SizedBox(height: 8),
          ],
        ]..removeLast(),
      );
    }
    final columns = isWide ? 2 : 1;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: projects.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 3.1,
      ),
      itemBuilder: (context, index) => _ProjectCard(projects[index]),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard(this.project);

  final ClientDashboardProjectSummary project;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => context.go('/client/projects/${project.projectId}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(project.projectNumber),
              const SizedBox(height: 4),
              Text(
                project.projectName,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _Pill(_displayStatus(project.lifecycleStatus)),
                  _Pill(_percent(project.officialPercent)),
                  _Pill(project.reportingCurrencyCode),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentUpdateList extends StatelessWidget {
  const _RecentUpdateList({required this.items});

  final List<ClientDashboardRecentUpdate> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _SafeMessage('No recent updates are available yet.');
    }
    return Column(
      children: [
        for (final item in items) ...[
          _SimpleCard(
            title: item.title,
            subtitle: '${item.projectNumber} - ${item.projectName}',
            body: item.summary,
            trailing: [
              if (item.reportedPercent != null) _percent(item.reportedPercent),
              if (item.publishedAt != null) _formatDate(item.publishedAt!),
            ].join(' - '),
            onTap: () => context.go('/client/projects/${item.projectId}'),
          ),
          const SizedBox(height: 8),
        ],
      ]..removeLast(),
    );
  }
}

class _PaymentRequestList extends StatelessWidget {
  const _PaymentRequestList({required this.state});

  final ClientPaymentRequestListState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) return const _InlineLoading();
    if (state.error != null)
      return const _SafeMessage('Payment requests failed to load.');
    if (state.requests.isEmpty) {
      return const _SafeMessage('No payment requests are available.');
    }
    return Column(
      children: [
        for (final request in state.requests.take(3)) ...[
          _SimpleCard(
            title: request.requestNumber,
            subtitle: request.projectNumber,
            body: request.description,
            trailing:
                '${request.remainingAmount.display(request.currencyCode)} remaining',
            onTap: () => context.go(
              '/client/payment-requests/${request.paymentRequestId}',
            ),
          ),
          const SizedBox(height: 8),
        ],
      ]..removeLast(),
    );
  }
}

class _PaymentList extends StatelessWidget {
  const _PaymentList({required this.state});

  final ClientPaymentListState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) return const _InlineLoading();
    if (state.error != null)
      return const _SafeMessage('Payments failed to load.');
    final payments = state.payments.where((payment) => payment.isReceived);
    if (payments.isEmpty) {
      return const _SafeMessage('No posted payments are available yet.');
    }
    return Column(
      children: [
        for (final payment in payments.take(3)) ...[
          _SimpleCard(
            title: payment.amount.display(payment.currencyCode),
            subtitle: payment.projectNumber,
            body: payment.paymentReference,
            trailing: 'Received ${_formatDate(payment.receivedDate)}',
            onTap: () =>
                context.go('/client/payments/${payment.clientPaymentId}'),
          ),
          const SizedBox(height: 8),
        ],
      ]..removeLast(),
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.items});

  final List<ClientDashboardRecentActivity> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _SafeMessage('No recent activity is available yet.');
    }
    return Column(
      children: [
        for (final item in items) ...[
          _SimpleCard(
            title: _activityLabel(item.activityType),
            subtitle: item.projectNumber ?? item.relatedEntityType,
            body: '${item.title}\n${item.message}',
            trailing: item.occurredAt == null
                ? null
                : _formatDate(item.occurredAt!),
            onTap: _activityRoute(item) == null
                ? null
                : () => context.go(_activityRoute(item)!),
          ),
          const SizedBox(height: 8),
        ],
      ]..removeLast(),
    );
  }
}

class _FilesMediaActions extends StatelessWidget {
  const _FilesMediaActions();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => context.go('/client/projects'),
          icon: const Icon(Icons.folder_copy),
          label: const Text('Project documents'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/client/photographs'),
          icon: const Icon(Icons.photo_library),
          label: const Text('Photographs'),
        ),
      ],
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({required this.state});

  final ClientNotificationListState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) return const _InlineLoading();
    if (state.error != null)
      return const _SafeMessage('Notifications failed to load.');
    if (state.items.isEmpty) {
      return const _SafeMessage('No notifications are available.');
    }
    return Column(
      children: [
        for (final notification in state.items.take(3)) ...[
          _SimpleCard(
            title: notification.title,
            subtitle: _notificationStatus(notification.status),
            body: notification.body,
            trailing: notification.createdAt == null
                ? null
                : _formatDate(notification.createdAt!),
            onTap: () => context.go('/client/notifications/${notification.id}'),
          ),
          const SizedBox(height: 8),
        ],
      ]..removeLast(),
    );
  }
}

class _SimpleCard extends StatelessWidget {
  const _SimpleCard({
    required this.title,
    this.subtitle,
    this.body,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? body;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null) ...[
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
              ],
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
                softWrap: true,
              ),
              if (body != null && body!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(body!, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              if (trailing != null && trailing!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label), visualDensity: VisualDensity.compact);
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 160,
      child: Center(child: Text('Loading...')),
    );
  }
}

class _InlineLoading extends StatelessWidget {
  const _InlineLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: Text('Loading...')),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dashboard failed to load.'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _SafeMessage extends StatelessWidget {
  const _SafeMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(12), child: Text(text));
  }
}

String _percent(num? value) {
  if (value == null) return 'Percent unavailable';
  final text = value % 1 == 0 ? value.toInt().toString() : value.toString();
  return '$text% complete';
}

String _displayStatus(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0]}${part.substring(1).toLowerCase()}')
      .join(' ');
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String _activityLabel(String value) {
  return switch (value) {
    'PRO'
        'GRESS_UPDATE_PUBLISHED' =>
      'Project update',
    'DOCUMENT_AVAILABLE' => 'Document available',
    'PHOTOGRAPH_AVAILABLE' => 'Photograph available',
    'PAYMENT_REQUEST_SENT' => 'Payment request',
    'CLIENT_PAYMENT_POSTED' => 'Payment received',
    _ => _displayStatus(value),
  };
}

String? _activityRoute(ClientDashboardRecentActivity item) {
  if ((item.activityType ==
              'PRO'
                  'GRESS_UPDATE_PUBLISHED' ||
          item.activityType == 'DOCUMENT_AVAILABLE') &&
      item.projectId != null) {
    return '/client/projects/${item.projectId}';
  }
  if (item.activityType == 'PHOTOGRAPH_AVAILABLE') {
    return '/client/photographs';
  }
  if (item.activityType == 'PAYMENT_REQUEST_SENT' &&
      item.relatedEntityId != null) {
    return '/client/payment-requests/${item.relatedEntityId}';
  }
  if (item.activityType == 'CLIENT_PAYMENT_POSTED' &&
      item.relatedEntityId != null) {
    return '/client/payments/${item.relatedEntityId}';
  }
  return null;
}

String _notificationStatus(ClientNotificationStatus status) {
  return switch (status) {
    ClientNotificationStatus.unread => 'Unread',
    ClientNotificationStatus.read => 'Read',
    ClientNotificationStatus.archived => 'Archived',
  };
}
