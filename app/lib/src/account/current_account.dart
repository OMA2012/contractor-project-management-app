enum AccountStatus { invited, active, suspended, disabled, unknown }

enum AccountUserType { staff, client, unknown }

enum TrustedAccountRouteTarget {
  loading,
  notProvisioned,
  pendingInvite,
  suspended,
  deactivated,
  noActiveRole,
  staff,
  client,
  failure,
}

class CurrentAccount {
  const CurrentAccount({
    required this.applicationUserId,
    required this.accountStatus,
    required this.isActive,
    required this.accessAllowed,
    required this.userType,
    required this.fullName,
    required this.jobTitle,
    required this.activeRoleCodes,
  });

  factory CurrentAccount.fromJson(Map<String, dynamic> json) {
    return CurrentAccount(
      applicationUserId: json['application_user_id'] as String,
      accountStatus: accountStatusFromText(json['account_status'] as String?),
      isActive: json['is_active'] as bool? ?? false,
      accessAllowed: json['access_allowed'] as bool? ?? false,
      userType: accountUserTypeFromText(json['user_type'] as String?),
      fullName: json['full_name'] as String?,
      jobTitle: json['job_title'] as String?,
      activeRoleCodes: List<String>.from(
        (json['active_role_codes'] as List<dynamic>?) ?? const <dynamic>[],
      ),
    );
  }

  final String applicationUserId;
  final AccountStatus accountStatus;
  final bool isActive;
  final bool accessAllowed;
  final AccountUserType userType;
  final String? fullName;
  final String? jobTitle;
  final List<String> activeRoleCodes;

  bool get hasStaffRole =>
      activeRoleCodes.contains('owner_admin') ||
      activeRoleCodes.contains('project_manager') ||
      activeRoleCodes.contains('accountant') ||
      activeRoleCodes.contains('site_supervisor');

  bool get hasClientRole => activeRoleCodes.contains('client');
}

AccountStatus accountStatusFromText(String? value) {
  return switch (value) {
    'INVITED' => AccountStatus.invited,
    'ACTIVE' => AccountStatus.active,
    'SUSPENDED' => AccountStatus.suspended,
    'DISABLED' => AccountStatus.disabled,
    _ => AccountStatus.unknown,
  };
}

AccountUserType accountUserTypeFromText(String? value) {
  return switch (value) {
    'STAFF' => AccountUserType.staff,
    'CLIENT' => AccountUserType.client,
    _ => AccountUserType.unknown,
  };
}

sealed class CurrentAccountState {
  const CurrentAccountState();

  const factory CurrentAccountState.initializing() = CurrentAccountInitializing;
  const factory CurrentAccountState.loading() = CurrentAccountLoading;
  const factory CurrentAccountState.loaded(CurrentAccount account) =
      CurrentAccountLoaded;
  const factory CurrentAccountState.notProvisioned() =
      CurrentAccountNotProvisioned;
  const factory CurrentAccountState.pendingInvite() =
      CurrentAccountPendingInvite;
  const factory CurrentAccountState.suspended() = CurrentAccountSuspended;
  const factory CurrentAccountState.deactivated() = CurrentAccountDeactivated;
  const factory CurrentAccountState.noActiveRole() = CurrentAccountNoActiveRole;
  const factory CurrentAccountState.failure(Object error) =
      CurrentAccountFailure;

  TrustedAccountRouteTarget get routeTarget {
    return switch (this) {
      CurrentAccountInitializing() ||
      CurrentAccountLoading() => TrustedAccountRouteTarget.loading,
      CurrentAccountNotProvisioned() =>
        TrustedAccountRouteTarget.notProvisioned,
      CurrentAccountPendingInvite() => TrustedAccountRouteTarget.pendingInvite,
      CurrentAccountSuspended() => TrustedAccountRouteTarget.suspended,
      CurrentAccountDeactivated() => TrustedAccountRouteTarget.deactivated,
      CurrentAccountNoActiveRole() => TrustedAccountRouteTarget.noActiveRole,
      CurrentAccountFailure() => TrustedAccountRouteTarget.failure,
      CurrentAccountLoaded(:final account) =>
        account.userType == AccountUserType.staff
            ? TrustedAccountRouteTarget.staff
            : TrustedAccountRouteTarget.client,
    };
  }
}

class CurrentAccountInitializing extends CurrentAccountState {
  const CurrentAccountInitializing();
}

class CurrentAccountLoading extends CurrentAccountState {
  const CurrentAccountLoading();
}

class CurrentAccountLoaded extends CurrentAccountState {
  const CurrentAccountLoaded(this.account);

  final CurrentAccount account;
}

class CurrentAccountNotProvisioned extends CurrentAccountState {
  const CurrentAccountNotProvisioned();
}

class CurrentAccountPendingInvite extends CurrentAccountState {
  const CurrentAccountPendingInvite();
}

class CurrentAccountSuspended extends CurrentAccountState {
  const CurrentAccountSuspended();
}

class CurrentAccountDeactivated extends CurrentAccountState {
  const CurrentAccountDeactivated();
}

class CurrentAccountNoActiveRole extends CurrentAccountState {
  const CurrentAccountNoActiveRole();
}

class CurrentAccountFailure extends CurrentAccountState {
  const CurrentAccountFailure(this.error);

  final Object error;
}
