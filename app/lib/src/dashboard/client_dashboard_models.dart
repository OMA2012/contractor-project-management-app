class ClientDashboardFailure implements Exception {
  const ClientDashboardFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ClientDashboardParseFailure extends ClientDashboardFailure {
  const ClientDashboardParseFailure(super.message);
}

class ClientDashboardProjectSummary {
  const ClientDashboardProjectSummary({
    required this.projectId,
    required this.projectNumber,
    required this.projectName,
    required this.lifecycleStatus,
    required this.reportingCurrencyCode,
    this.officialPercent,
  });

  factory ClientDashboardProjectSummary.fromJson(Map<String, dynamic> json) {
    return ClientDashboardProjectSummary(
      projectId: _requiredUuid(json, 'project_id'),
      projectNumber: _requiredString(json, 'project_number'),
      projectName: _requiredString(json, 'project_name'),
      lifecycleStatus: _requiredString(json, 'lifecycle_status'),
      officialPercent: _num(
        json,
        'official_'
        'com'
        'pletion_percent',
      ),
      reportingCurrencyCode: _requiredString(json, 'reporting_currency_code'),
    );
  }

  final String projectId;
  final String projectNumber;
  final String projectName;
  final String lifecycleStatus;
  final num? officialPercent;
  final String reportingCurrencyCode;
}

class ClientDashboardRecentUpdate {
  const ClientDashboardRecentUpdate({
    required this.updateId,
    required this.projectId,
    required this.projectNumber,
    required this.projectName,
    required this.title,
    this.summary,
    this.reportedPercent,
    this.publishedAt,
  });

  factory ClientDashboardRecentUpdate.fromJson(Map<String, dynamic> json) {
    return ClientDashboardRecentUpdate(
      updateId: _requiredUuid(
        json,
        'pro'
        'gress_update_id',
      ),
      projectId: _requiredUuid(json, 'project_id'),
      projectNumber: _requiredString(json, 'project_number'),
      projectName: _requiredString(json, 'project_name'),
      title: _requiredString(json, 'title'),
      summary: _string(json, 'summary'),
      reportedPercent: _num(
        json,
        'reported_'
        'com'
        'pletion_percent',
      ),
      publishedAt: _date(json, 'published_at'),
    );
  }

  final String updateId;
  final String projectId;
  final String projectNumber;
  final String projectName;
  final String title;
  final String? summary;
  final num? reportedPercent;
  final DateTime? publishedAt;
}

class ClientDashboardRecentActivity {
  const ClientDashboardRecentActivity({
    required this.activityType,
    required this.title,
    required this.message,
    required this.occurredAt,
    required this.relatedEntityType,
    this.relatedEntityId,
    this.projectId,
    this.projectNumber,
  });

  factory ClientDashboardRecentActivity.fromJson(Map<String, dynamic> json) {
    return ClientDashboardRecentActivity(
      activityType: _requiredString(json, 'activity_type'),
      projectId: _uuid(json, 'project_id'),
      projectNumber: _string(json, 'project_number'),
      title: _requiredString(json, 'title'),
      message: _requiredString(json, 'message'),
      occurredAt: _date(json, 'occurred_at'),
      relatedEntityType: _requiredString(json, 'related_entity_type'),
      relatedEntityId: _uuid(json, 'related_entity_id'),
    );
  }

  final String activityType;
  final String? projectId;
  final String? projectNumber;
  final String title;
  final String message;
  final DateTime? occurredAt;
  final String relatedEntityType;
  final String? relatedEntityId;
}

class ClientDashboardState {
  const ClientDashboardState({
    this.projects = const [],
    this.recentUpdates = const [],
    this.recentActivity = const [],
    this.isLoading = false,
    this.error,
  });

  final List<ClientDashboardProjectSummary> projects;
  final List<ClientDashboardRecentUpdate> recentUpdates;
  final List<ClientDashboardRecentActivity> recentActivity;
  final bool isLoading;
  final Object? error;

  bool get isEmpty =>
      !isLoading &&
      error == null &&
      projects.isEmpty &&
      recentUpdates.isEmpty &&
      recentActivity.isEmpty;
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is String && value.trim().isNotEmpty) return value;
  throw ClientDashboardParseFailure(
    'Required dashboard field is missing: $field.',
  );
}

String? _string(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is String) return value;
  throw ClientDashboardParseFailure('Dashboard field is invalid: $field.');
}

final _canonicalUuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String _requiredUuid(Map<String, dynamic> json, String field) {
  final value = _requiredString(json, field);
  if (_canonicalUuidPattern.hasMatch(value)) return value;
  throw ClientDashboardParseFailure('Dashboard UUID field is invalid: $field.');
}

String? _uuid(Map<String, dynamic> json, String field) {
  final value = _string(json, field);
  if (value == null) return null;
  if (_canonicalUuidPattern.hasMatch(value)) return value;
  throw ClientDashboardParseFailure('Dashboard UUID field is invalid: $field.');
}

num? _num(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is num) return value;
  if (value is String) {
    final parsed = num.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw ClientDashboardParseFailure('Dashboard field is invalid: $field.');
}

DateTime? _date(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw ClientDashboardParseFailure('Dashboard field is invalid: $field.');
}
