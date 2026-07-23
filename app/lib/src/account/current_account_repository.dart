import 'package:supabase_flutter/supabase_flutter.dart';

import 'current_account.dart';

typedef CurrentAccountRpc = Future<dynamic> Function(String functionName);

class CurrentAccountRepository {
  const CurrentAccountRepository({this.supabaseClient, this.rpc});

  final SupabaseClient? supabaseClient;
  final CurrentAccountRpc? rpc;

  SupabaseClient get client => supabaseClient ?? Supabase.instance.client;

  Future<CurrentAccount?> loadCurrentAccount() async {
    final response = await (rpc ?? client.rpc)('current_account');
    final rows = _rowsFromResponse(response);
    if (rows.isEmpty) {
      return null;
    }

    return CurrentAccount.fromJson(rows.single);
  }

  List<Map<String, dynamic>> _rowsFromResponse(dynamic response) {
    if (response is List) {
      return response.cast<Map<String, dynamic>>();
    }
    if (response is Map<String, dynamic>) {
      return [response];
    }
    return const [];
  }
}
