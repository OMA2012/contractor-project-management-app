import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ActivationFunctionInvoke =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);
typedef ActivationRpc = Future<dynamic> Function(String functionName);

final accountActivationRepositoryProvider =
    Provider<AccountActivationRepository>(
      (ref) => AccountActivationRepository(),
    );

class AccountActivationFailure implements Exception {
  const AccountActivationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class AccountActivationRepository {
  AccountActivationRepository({
    this.supabaseClient,
    this.invokeFunction,
    this.rpc,
  });

  final SupabaseClient? supabaseClient;
  final ActivationFunctionInvoke? invokeFunction;
  final ActivationRpc? rpc;

  SupabaseClient get client => supabaseClient ?? Supabase.instance.client;

  Future<void> acceptClientInvitation({
    required String token,
    required String fullName,
  }) async {
    final response = invokeFunction != null
        ? await invokeFunction!('accept-client-invitation', {
            'token': token,
            'full_name': fullName,
          })
        : await client.functions.invoke(
            'accept-client-invitation',
            body: {'token': token, 'full_name': fullName},
          );
    final data = _data(response);
    if (data['status'] != 'ACTIVE' || data['client_user_id'] is! String) {
      throw const AccountActivationFailure('Invitation could not be accepted.');
    }
  }

  Future<void> activateOwner() async {
    final response = await (rpc ?? client.rpc)(
      'activate_current_invited_owner',
    );
    final value = response is List && response.length == 1
        ? response.single
        : response;
    if (value is! String || value.isEmpty) {
      throw const AccountActivationFailure(
        'Owner invitation could not be activated.',
      );
    }
  }

  Map<String, dynamic> _data(dynamic response) {
    if (response is FunctionResponse) return _data(response.data);
    if (response is! Map<String, dynamic>) {
      throw const AccountActivationFailure(
        'Activation service response was invalid.',
      );
    }
    if (response['success'] == false || response['error'] != null) {
      throw const AccountActivationFailure(
        'Invitation is invalid, expired, or cannot be accepted.',
      );
    }
    final data = response['data'];
    return data is Map<String, dynamic> ? data : response;
  }
}
