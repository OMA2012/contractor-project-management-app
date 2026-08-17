class OwnerClientRecord {
  const OwnerClientRecord({
    required this.id,
    required this.clientNumber,
    required this.displayName,
    required this.status,
    required this.isActive,
    required this.versionNumber,
    this.email,
    this.phone,
    this.legalName,
    this.address,
    this.portalUserId,
    this.projectCount = 0,
  });

  factory OwnerClientRecord.fromJson(Map<String, dynamic> json) {
    return OwnerClientRecord(
      id: _requiredString(json, 'id'),
      clientNumber: _requiredString(json, 'client_number'),
      displayName: _requiredString(json, 'display_name'),
      legalName: _string(json, 'legal_name'),
      email: _string(json, 'email'),
      phone: _string(json, 'phone'),
      address: _string(json, 'address'),
      status: _requiredString(json, 'status'),
      isActive: json['is_active'] == true,
      portalUserId: _string(json, 'portal_user_id'),
      versionNumber: _requiredInt(json, 'version_number'),
      projectCount: _int(json, 'project_count') ?? 0,
    );
  }

  final String id;
  final String clientNumber;
  final String displayName;
  final String? legalName;
  final String? email;
  final String? phone;
  final String? address;
  final String status;
  final bool isActive;
  final String? portalUserId;
  final int versionNumber;
  final int projectCount;

  String get pickerLabel => '$clientNumber - $displayName';
  String get accountState => portalUserId == null ? 'Pending invite' : 'Linked';
}

class OwnerProjectRecord {
  const OwnerProjectRecord({
    required this.id,
    required this.clientId,
    required this.projectNumber,
    required this.name,
    required this.status,
    required this.reportingCurrencyCode,
    required this.versionNumber,
    this.clientNumber,
    this.clientName,
    this.projectType,
    this.location,
    this.startDate,
    this.endDate,
    this.clientVisibleSummary,
  });

  factory OwnerProjectRecord.fromJson(Map<String, dynamic> json) {
    return OwnerProjectRecord(
      id: _requiredString(json, 'id'),
      clientId: _requiredString(json, 'client_id'),
      clientNumber: _string(json, 'client_number'),
      clientName: _string(json, 'client_name'),
      projectNumber: _requiredString(json, 'project_number'),
      name: _requiredString(json, 'name'),
      projectType: _string(json, 'project_type'),
      location: _string(json, 'location'),
      status: _requiredString(json, 'status'),
      startDate: _date(json, 'start_date'),
      endDate: _date(json, 'end_date'),
      reportingCurrencyCode: _requiredString(json, 'reporting_currency_code'),
      clientVisibleSummary: _string(json, 'client_visible_summary'),
      versionNumber: _requiredInt(json, 'version_number'),
    );
  }

  final String id;
  final String clientId;
  final String? clientNumber;
  final String? clientName;
  final String projectNumber;
  final String name;
  final String? projectType;
  final String? location;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final String reportingCurrencyCode;
  final String? clientVisibleSummary;
  final int versionNumber;

  bool get canEdit => !{'COMPLETED', 'CANCELLED', 'ARCHIVED'}.contains(status);

  List<String> get nextStatuses => switch (status) {
    'DRAFT' => const ['QUOTATION', 'APPROVED', 'CANCELLED'],
    'QUOTATION' => const ['DRAFT', 'APPROVED', 'CANCELLED'],
    'APPROVED' => const ['ACTIVE', 'CANCELLED'],
    'ACTIVE' => const ['ON_HOLD', 'COMPLETED', 'CANCELLED'],
    'ON_HOLD' => const ['ACTIVE', 'CANCELLED'],
    'COMPLETED' || 'CANCELLED' => const ['ARCHIVED'],
    _ => const [],
  };
}

String? _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  if (value == null) throw FormatException('Missing $key');
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = _int(json, key);
  if (value == null) throw FormatException('Missing $key');
  return value;
}

int? _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is DateTime) return value;
  return value is String ? DateTime.tryParse(value) : null;
}
