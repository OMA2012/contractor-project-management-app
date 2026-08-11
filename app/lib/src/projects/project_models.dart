class ProjectFailure implements Exception {
  const ProjectFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProjectParseFailure extends ProjectFailure {
  const ProjectParseFailure(super.message);
}

class ClientProject {
  const ClientProject({
    required this.id,
    required this.projectNumber,
    required this.name,
    required this.status,
    required this.reportingCurrencyCode,
    this.projectType,
    this.location,
    this.startDate,
    this.endDate,
    this.clientVisibleSummary,
  });

  factory ClientProject.fromJson(Map<String, dynamic> json) {
    return ClientProject(
      id: _requiredString(json, 'id'),
      projectNumber: _requiredString(json, 'project_number'),
      name: _requiredString(json, 'name'),
      projectType: _string(json, 'project_type'),
      location: _string(json, 'location'),
      status: _requiredProjectStatus(json, 'status'),
      startDate: _date(json, 'start_date'),
      endDate: _date(json, 'end_date'),
      reportingCurrencyCode: _requiredString(json, 'reporting_currency_code'),
      clientVisibleSummary: _string(json, 'client_visible_summary'),
    );
  }

  final String id;
  final String projectNumber;
  final String name;
  final String? projectType;
  final String? location;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final String reportingCurrencyCode;
  final String? clientVisibleSummary;
}

class ClientProjectPage {
  const ClientProjectPage({required this.rawCount, required this.projects});

  final int rawCount;
  final List<ClientProject> projects;
}

class ClientProjectListState {
  const ClientProjectListState({
    this.projects = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<ClientProject> projects;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  bool get isEmpty => !isLoading && error == null && projects.isEmpty;

  ClientProjectListState copyWith({
    List<ClientProject>? projects,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) {
    return ClientProjectListState(
      projects: projects ?? this.projects,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class ClientProjectDetailState {
  const ClientProjectDetailState._({
    required this.isLoading,
    this.project,
    this.error,
    this.unavailable = false,
  });

  const ClientProjectDetailState.loading() : this._(isLoading: true);

  const ClientProjectDetailState.loaded(ClientProject project)
    : this._(isLoading: false, project: project);

  const ClientProjectDetailState.unavailable()
    : this._(isLoading: false, unavailable: true);

  const ClientProjectDetailState.failure(Object error)
    : this._(isLoading: false, error: error);

  final bool isLoading;
  final ClientProject? project;
  final Object? error;
  final bool unavailable;
}

String? _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  if (value == null) {
    throw ProjectParseFailure('Required project field is missing: $key.');
  }
  return value;
}

DateTime? _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is DateTime) return value;
  return value is String ? DateTime.tryParse(value) : null;
}

String _requiredProjectStatus(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  if (!{
    'DRAFT',
    'QUOTATION',
    'APPROVED',
    'ACTIVE',
    'ON_HOLD',
    'COMPLETED',
    'CANCELLED',
    'ARCHIVED',
  }.contains(value)) {
    throw const ProjectParseFailure('Project status is not recognized.');
  }
  return value;
}
