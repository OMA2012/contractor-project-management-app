import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_models.dart';

typedef NotificationRpc =
    Future<dynamic> Function(
      String functionName, {
      Map<String, dynamic>? params,
    });

abstract class NotificationRepository {
  Future<ClientNotificationPage> listClientNotifications({
    ClientNotificationStatus? status,
    bool includeArchived = false,
    int limit = 50,
    int offset = 0,
  });

  Future<ClientNotification?> getClientNotification(String notificationId);

  Future<ClientNotification> markClientNotificationRead(String notificationId);

  Future<ClientNotification> markClientNotificationUnread(
    String notificationId,
  );

  Future<ClientNotification> archiveClientNotification(String notificationId);
}

class SupabaseNotificationRepository implements NotificationRepository {
  const SupabaseNotificationRepository({this.supabaseClient, this.rpc});

  final SupabaseClient? supabaseClient;
  final NotificationRpc? rpc;

  SupabaseClient get client => supabaseClient ?? Supabase.instance.client;

  @override
  Future<ClientNotificationPage> listClientNotifications({
    ClientNotificationStatus? status,
    bool includeArchived = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _rpc('current_notification_list', {
      'p_status': status?.value,
      'p_include_archived': includeArchived,
      'p_limit': limit,
      'p_offset': offset,
    });
    final rows = _rows(response);
    return ClientNotificationPage(
      rawCount: rows.length,
      items: rows.map(ClientNotification.fromJson).toList(growable: false),
    );
  }

  @override
  Future<ClientNotification?> getClientNotification(
    String notificationId,
  ) async {
    final response = await _rpc('current_notification_detail', {
      'p_notification_id': notificationId,
    });
    final rows = _rows(response);
    if (rows.isEmpty) return null;
    return ClientNotification.fromJson(rows.single);
  }

  @override
  Future<ClientNotification> markClientNotificationRead(String notificationId) {
    return _mutate('current_mark_notification_read', notificationId);
  }

  @override
  Future<ClientNotification> markClientNotificationUnread(
    String notificationId,
  ) {
    return _mutate('current_mark_notification_unread', notificationId);
  }

  @override
  Future<ClientNotification> archiveClientNotification(String notificationId) {
    return _mutate('current_archive_notification', notificationId);
  }

  Future<ClientNotification> _mutate(
    String functionName,
    String notificationId,
  ) async {
    final response = await _rpc(functionName, {
      'p_notification_id': notificationId,
    });
    final rows = _rows(response);
    if (rows.isEmpty) {
      throw const NotificationFailure('Notification is unavailable.');
    }
    return ClientNotification.fromJson(rows.single);
  }

  Future<dynamic> _rpc(String functionName, Map<String, dynamic> params) {
    if (rpc != null) return rpc!(functionName, params: params);
    return client.rpc(functionName, params: params);
  }

  List<Map<String, dynamic>> _rows(dynamic response) {
    if (response is List) return response.cast<Map<String, dynamic>>();
    if (response is Map<String, dynamic>) return [response];
    return const [];
  }
}
