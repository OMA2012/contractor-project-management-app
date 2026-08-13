import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../notifications/notification_models.dart';
import '../notifications/notification_providers.dart';
import '../projects/project_providers.dart';

class ClientNotificationDetailScreen extends ConsumerStatefulWidget {
  const ClientNotificationDetailScreen({
    required this.notificationId,
    super.key,
  });

  final String notificationId;

  @override
  ConsumerState<ClientNotificationDetailScreen> createState() =>
      _ClientNotificationDetailScreenState();
}

class _ClientNotificationDetailScreenState
    extends ConsumerState<ClientNotificationDetailScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ClientNotificationDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notificationId != widget.notificationId) _load();
  }

  void _load({bool force = false}) {
    Future.microtask(
      () => ref
          .read(
            clientNotificationDetailProvider(widget.notificationId).notifier,
          )
          .load(force: force),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(clientProjectAccessProvider, (previous, hasAccess) {
      if (previous != true && hasAccess) _load();
    });
    final state = ref.watch(
      clientNotificationDetailProvider(widget.notificationId),
    );
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.unavailable) {
      return const Center(child: Text('Notification is unavailable.'));
    }
    if (state.notification == null) {
      return const Center(child: Text('Notification could not be loaded.'));
    }
    return _NotificationDetail(
      notification: state.notification!,
      state: state,
      notificationId: widget.notificationId,
      onRetry: () => _load(force: true),
    );
  }
}

class _NotificationDetail extends ConsumerWidget {
  const _NotificationDetail({
    required this.notification,
    required this.state,
    required this.notificationId,
    required this.onRetry,
  });

  final ClientNotification notification;
  final ClientNotificationDetailState state;
  final String notificationId;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth >= 900 ? 820.0 : double.infinity;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.go('/client/notifications'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Notifications'),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusChip(status: notification.status),
                    const SizedBox(height: 12),
                    Text(
                      notification.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                      softWrap: true,
                    ),
                    const SizedBox(height: 8),
                    Text('Created ${_formatDateTime(notification.createdAt)}'),
                    const SizedBox(height: 24),
                    SelectableText(notification.body),
                    const SizedBox(height: 24),
                    if (state.error != null) ...[
                      const Text('Notification action could not be completed.'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: state.isMutating ? null : onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _Actions(
                      notification: notification,
                      isMutating: state.isMutating,
                      onMarkRead: () => ref
                          .read(
                            clientNotificationDetailProvider(
                              notificationId,
                            ).notifier,
                          )
                          .markRead(),
                      onMarkUnread: () => ref
                          .read(
                            clientNotificationDetailProvider(
                              notificationId,
                            ).notifier,
                          )
                          .markUnread(),
                      onArchive: () => ref
                          .read(
                            clientNotificationDetailProvider(
                              notificationId,
                            ).notifier,
                          )
                          .archive(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.notification,
    required this.isMutating,
    required this.onMarkRead,
    required this.onMarkUnread,
    required this.onArchive,
  });

  final ClientNotification notification;
  final bool isMutating;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final archived = notification.status == ClientNotificationStatus.archived;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!archived && notification.status == ClientNotificationStatus.unread)
          OutlinedButton.icon(
            onPressed: isMutating ? null : onMarkRead,
            icon: const Icon(Icons.mark_email_read),
            label: const Text('Mark read'),
          ),
        if (!archived && notification.status == ClientNotificationStatus.read)
          OutlinedButton.icon(
            onPressed: isMutating ? null : onMarkUnread,
            icon: const Icon(Icons.mark_email_unread),
            label: const Text('Mark unread'),
          ),
        if (notification.canOpenProject)
          OutlinedButton.icon(
            onPressed: isMutating
                ? null
                : () =>
                      context.go('/client/projects/${notification.projectId}'),
            icon: const Icon(Icons.business_center),
            label: const Text('View project'),
          ),
        if (!archived)
          FilledButton.tonalIcon(
            onPressed: isMutating ? null : onArchive,
            icon: const Icon(Icons.archive),
            label: const Text('Archive'),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ClientNotificationStatus status;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(status.value));
  }
}

String _formatDateTime(DateTime? date) {
  if (date == null) return 'Not available';
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
