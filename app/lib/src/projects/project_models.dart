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

class ClientProjectCompletion {
  const ClientProjectCompletion({
    required this.projectId,
    this.calculatedCompletionPercent,
    this.officialCompletionPercent,
    this.isOverridden = false,
  });

  factory ClientProjectCompletion.fromJson(Map<String, dynamic> json) {
    return ClientProjectCompletion(
      projectId: _requiredString(json, 'project_id'),
      calculatedCompletionPercent: _num(json, 'calculated_completion_percent'),
      officialCompletionPercent: _num(json, 'official_completion_percent'),
      isOverridden: json['is_overridden'] == true,
    );
  }

  final String projectId;
  final num? calculatedCompletionPercent;
  final num? officialCompletionPercent;
  final bool isOverridden;
}

class ClientProgressUpdate {
  const ClientProgressUpdate({
    required this.id,
    required this.projectId,
    required this.title,
    this.milestoneId,
    this.summary,
    this.reportedCompletionPercent,
    this.publishedAt,
  });

  factory ClientProgressUpdate.fromJson(Map<String, dynamic> json) {
    return ClientProgressUpdate(
      id: _requiredString(json, 'id'),
      projectId: _requiredString(json, 'project_id'),
      milestoneId: _string(json, 'milestone_id'),
      title: _requiredString(json, 'title'),
      summary: _string(json, 'summary'),
      reportedCompletionPercent: _num(json, 'reported_completion_percent'),
      publishedAt: _date(json, 'published_at'),
    );
  }

  final String id;
  final String projectId;
  final String? milestoneId;
  final String title;
  final String? summary;
  final num? reportedCompletionPercent;
  final DateTime? publishedAt;
}

class ClientProgressUpdatePage {
  const ClientProgressUpdatePage({required this.rawCount, required this.items});

  final int rawCount;
  final List<ClientProgressUpdate> items;
}

class ClientProjectPhase {
  const ClientProjectPhase({
    required this.id,
    required this.projectId,
    required this.name,
    this.description,
    this.sequenceNo,
    this.startDate,
    this.endDate,
  });

  factory ClientProjectPhase.fromJson(Map<String, dynamic> json) {
    return ClientProjectPhase(
      id: _requiredString(json, 'id'),
      projectId: _requiredString(json, 'project_id'),
      name: _requiredString(json, 'name'),
      description: _string(json, 'description'),
      sequenceNo: _int(json, 'sequence_no'),
      startDate: _date(json, 'start_date'),
      endDate: _date(json, 'end_date'),
    );
  }

  final String id;
  final String projectId;
  final String name;
  final String? description;
  final int? sequenceNo;
  final DateTime? startDate;
  final DateTime? endDate;
}

class ClientProjectPhaseCompletion {
  const ClientProjectPhaseCompletion({
    required this.projectId,
    required this.phaseId,
    this.calculatedCompletionPercent,
  });

  factory ClientProjectPhaseCompletion.fromJson(Map<String, dynamic> json) {
    return ClientProjectPhaseCompletion(
      projectId: _requiredString(json, 'project_id'),
      phaseId: _requiredString(json, 'phase_id'),
      calculatedCompletionPercent: _num(json, 'calculated_completion_percent'),
    );
  }

  final String projectId;
  final String phaseId;
  final num? calculatedCompletionPercent;
}

class ClientProjectTask {
  const ClientProjectTask({
    required this.id,
    required this.projectId,
    required this.title,
    this.phaseId,
    this.milestoneId,
    this.taskNumber,
    this.clientSummary,
    this.status,
    this.completionPercent,
    this.startDate,
    this.dueDate,
    this.completedAt,
  });

  factory ClientProjectTask.fromJson(Map<String, dynamic> json) {
    return ClientProjectTask(
      id: _requiredString(json, 'id'),
      projectId: _requiredString(json, 'project_id'),
      phaseId: _string(json, 'phase_id'),
      milestoneId: _string(json, 'milestone_id'),
      taskNumber: _string(json, 'task_number'),
      title: _requiredString(json, 'title'),
      clientSummary: _string(json, 'client_summary'),
      status: _string(json, 'status'),
      completionPercent: _num(json, 'completion_percent'),
      startDate: _date(json, 'start_date'),
      dueDate: _date(json, 'due_date'),
      completedAt: _date(json, 'completed_at'),
    );
  }

  final String id;
  final String projectId;
  final String? phaseId;
  final String? milestoneId;
  final String? taskNumber;
  final String title;
  final String? clientSummary;
  final String? status;
  final num? completionPercent;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime? completedAt;
}

class ClientProjectPhaseTaskState {
  const ClientProjectPhaseTaskState({
    this.phases = const [],
    this.tasks = const [],
    this.completions = const {},
    this.completionFailures = const {},
    this.isLoading = false,
    this.error,
  });

  final List<ClientProjectPhase> phases;
  final List<ClientProjectTask> tasks;
  final Map<String, ClientProjectPhaseCompletion> completions;
  final Set<String> completionFailures;
  final bool isLoading;
  final Object? error;

  bool get isEmpty =>
      !isLoading && error == null && phases.isEmpty && tasks.isEmpty;
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

class ClientProjectCompletionState {
  const ClientProjectCompletionState({
    this.completion,
    this.isLoading = false,
    this.error,
  });

  final ClientProjectCompletion? completion;
  final bool isLoading;
  final Object? error;
}

class ClientProgressUpdateListState {
  const ClientProgressUpdateListState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<ClientProgressUpdate> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  bool get isEmpty => !isLoading && error == null && items.isEmpty;

  ClientProgressUpdateListState copyWith({
    List<ClientProgressUpdate>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) {
    return ClientProgressUpdateListState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : error ?? this.error,
    );
  }
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

num? _num(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

int? _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
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
