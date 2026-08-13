import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../notifications/notification_models.dart';
import '../notifications/notification_providers.dart';
import '../projects/project_providers.dart';

class ClientNotificationListScreen extends ConsumerStatefulWidget {
  const ClientNotificationListScreen({super.key});

  @override
  ConsumerState<ClientNotificationListScreen> createState() =>
      _ClientNotificationListScreenState();
}

class _ClientNotificationListScreenState
    extends ConsumerState<ClientNotificationListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(clientNotificationListProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(clientProjectAccessProvider, (previous, hasAccess) {
      if (previous != true && hasAccess) {
        Future.microtask(
          () => ref.read(clientNotificationListProvider.notifier).load(),
        );
      }
    });
    final state = ref.watch(clientNotificationListProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Notifications',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ClientNotificationListFilter.values
                    .map(
                      (filter) => FilterChip(
                        label: Text(filter.label),
                        selected: state.filter == filter,
                        onSelected: state.isLoading || state.isLoadingMore
                            ? null
                            : (_) => ref
                                  .read(clientNotificationListProvider.notifier)
                                  .setFilter(filter),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _NotificationListBody(state: state, isWide: isWide),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed:
                      state.isLoading || state.isLoadingMore || !state.hasMore
                      ? null
                      : () => ref
                            .read(clientNotificationListProvider.notifier)
                            .loadMore(),
                  icon: state.isLoadingMore
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more),
                  label: Text(state.hasMore ? 'Load more' : 'All loaded'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationListBody extends StatelessWidget {
  const _NotificationListBody({required this.state, required this.isWide});

  final ClientNotificationListState state;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return const Center(child: Text('Notifications could not be loaded.'));
    }
    if (state.items.isEmpty) {
      return Center(child: Text(state.filter.emptyText));
    }
    return ListView.separated(
      itemBuilder: (context, index) =>
          _NotificationCard(notification: state.items[index], isWide: isWide),
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemCount: state.items.length,
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.isWide});

  final ClientNotification notification;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/client/notifications/${notification.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isWide ? _wide(context) : _narrow(context),
        ),
      ),
    );
  }

  Widget _wide(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: _headline(context)),
        const SizedBox(width: 16),
        Expanded(flex: 2, child: _metadata(context)),
        const SizedBox(width: 16),
        IconButton(
          tooltip: 'View notification',
          onPressed: () =>
              context.go('/client/notifications/${notification.id}'),
          icon: const Icon(Icons.arrow_forward),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headline(context),
        const SizedBox(height: 12),
        _metadata(context),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () =>
                context.go('/client/notifications/${notification.id}'),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('View'),
          ),
        ),
      ],
    );
  }

  Widget _headline(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusChip(status: notification.status),
            if (notification.status == ClientNotificationStatus.unread)
              Text('Unread', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          notification.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: notification.status == ClientNotificationStatus.unread
                ? FontWeight.w700
                : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(notification.body, maxLines: 3, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _metadata(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _Meta('Created', _formatDateTime(notification.createdAt)),
        if (notification.status == ClientNotificationStatus.archived)
          _Meta('Archived', _formatDateTime(notification.archivedAt)),
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

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, overflow: TextOverflow.ellipsis, maxLines: 2),
        ],
      ),
    );
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
