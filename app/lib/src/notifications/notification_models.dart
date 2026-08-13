class NotificationFailure implements Exception {
  const NotificationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class NotificationParseFailure extends NotificationFailure {
  const NotificationParseFailure(super.message);
}

enum ClientNotificationStatus {
  unread('UNREAD'),
  read('READ'),
  archived('ARCHIVED');

  const ClientNotificationStatus(this.value);

  final String value;

  static ClientNotificationStatus fromText(String? value) {
    return switch (value) {
      'UNREAD' => ClientNotificationStatus.unread,
      'READ' => ClientNotificationStatus.read,
      'ARCHIVED' => ClientNotificationStatus.archived,
      _ => throw const NotificationParseFailure(
        'Notification status is not recognized.',
      ),
    };
  }
}

enum ClientNotificationListFilter {
  inbox('Inbox', null, false, 'No notifications are available.'),
  unread(
    'Unread',
    ClientNotificationStatus.unread,
    false,
    'No unread notifications are available.',
  ),
  read(
    'Read',
    ClientNotificationStatus.read,
    false,
    'No notifications are available.',
  ),
  archived(
    'Archived',
    ClientNotificationStatus.archived,
    true,
    'No archived notifications are available.',
  );

  const ClientNotificationListFilter(
    this.label,
    this.status,
    this.includeArchived,
    this.emptyText,
  );

  final String label;
  final ClientNotificationStatus? status;
  final bool includeArchived;
  final String emptyText;
}

class ClientNotification {
  const ClientNotification({
    required this.id,
    required this.notificationType,
    required this.title,
    required this.body,
    required this.status,
    this.projectId,
    this.relatedEntityType,
    this.relatedEntityId,
    this.createdAt,
    this.readAt,
    this.archivedAt,
  });

  factory ClientNotification.fromJson(Map<String, dynamic> json) {
    return ClientNotification(
      id: _requiredString(json, 'id'),
      projectId: _string(json, 'project_id'),
      notificationType: _requiredString(json, 'notification_type'),
      title: _requiredString(json, 'title'),
      body: _requiredString(json, 'body'),
      status: ClientNotificationStatus.fromText(_string(json, 'status')),
      relatedEntityType: _string(json, 'related_entity_type'),
      relatedEntityId: _string(json, 'related_entity_id'),
      createdAt: _date(json, 'created_at'),
      readAt: _date(json, 'read_at'),
      archivedAt: _date(json, 'archived_at'),
    );
  }

  final String id;
  final String? projectId;
  final String notificationType;
  final String title;
  final String body;
  final ClientNotificationStatus status;
  final String? relatedEntityType;
  final String? relatedEntityId;
  final DateTime? createdAt;
  final DateTime? readAt;
  final DateTime? archivedAt;

  bool get canOpenProject =>
      notificationType == 'PROGRESS_UPDATE_PUBLISHED' &&
      relatedEntityType == 'progress_update' &&
      projectId != null;
}

class ClientNotificationPage {
  const ClientNotificationPage({required this.rawCount, required this.items});

  final int rawCount;
  final List<ClientNotification> items;
}

class ClientNotificationListState {
  const ClientNotificationListState({
    this.items = const [],
    this.filter = ClientNotificationListFilter.inbox,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<ClientNotification> items;
  final ClientNotificationListFilter filter;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  bool get isEmpty => !isLoading && error == null && items.isEmpty;

  ClientNotificationListState copyWith({
    List<ClientNotification>? items,
    ClientNotificationListFilter? filter,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) {
    return ClientNotificationListState(
      items: items ?? this.items,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class ClientNotificationDetailState {
  const ClientNotificationDetailState._({
    required this.isLoading,
    this.notification,
    this.error,
    this.unavailable = false,
    this.isMutating = false,
  });

  const ClientNotificationDetailState.loading() : this._(isLoading: true);

  const ClientNotificationDetailState.loaded(
    ClientNotification notification, {
    bool isMutating = false,
    Object? error,
  }) : this._(
         isLoading: false,
         notification: notification,
         isMutating: isMutating,
         error: error,
       );

  const ClientNotificationDetailState.unavailable()
    : this._(isLoading: false, unavailable: true);

  const ClientNotificationDetailState.failure(Object error)
    : this._(isLoading: false, error: error);

  final bool isLoading;
  final ClientNotification? notification;
  final Object? error;
  final bool unavailable;
  final bool isMutating;
}

String? _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  if (value == null) {
    throw NotificationParseFailure('Required notification field is missing.');
  }
  return value;
}

DateTime? _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is DateTime) return value;
  return value is String ? DateTime.tryParse(value) : null;
}
