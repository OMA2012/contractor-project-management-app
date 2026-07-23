import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calls current_account rpc with no parameters', () async {
    final calls = <String>[];
    final repository = CurrentAccountRepository(
      rpc: (functionName) async {
        calls.add(functionName);
        return <Map<String, dynamic>>[];
      },
    );

    await repository.loadCurrentAccount();

    expect(calls, ['current_account']);
  });

  test('zero rows map to not provisioned account result', () async {
    final repository = CurrentAccountRepository(
      rpc: (_) async => <Map<String, dynamic>>[],
    );

    expect(await repository.loadCurrentAccount(), isNull);
  });

  test('maps trusted active staff account', () async {
    final repository = CurrentAccountRepository(
      rpc: (_) async => [
        {
          'application_user_id': '10000000-0000-0000-0000-000000000201',
          'account_status': 'ACTIVE',
          'is_active': true,
          'access_allowed': true,
          'user_type': 'STAFF',
          'full_name': 'Staff Person',
          'job_title': 'Project Manager',
          'active_role_codes': ['owner_admin'],
        },
      ],
    );

    final account = await repository.loadCurrentAccount();

    expect(account?.accountStatus, AccountStatus.active);
    expect(account?.userType, AccountUserType.staff);
    expect(account?.hasStaffRole, isTrue);
  });

  test('maps trusted inactive and empty role values', () async {
    final repository = CurrentAccountRepository(
      rpc: (_) async => {
        'application_user_id': '10000000-0000-0000-0000-000000000203',
        'account_status': 'INVITED',
        'is_active': false,
        'access_allowed': false,
        'user_type': 'STAFF',
        'full_name': null,
        'job_title': null,
        'active_role_codes': null,
      },
    );

    final account = await repository.loadCurrentAccount();

    expect(account?.accountStatus, AccountStatus.invited);
    expect(account?.activeRoleCodes, isEmpty);
  });
}
