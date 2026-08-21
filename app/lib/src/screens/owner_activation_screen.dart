import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/current_account_provider.dart';
import '../auth/account_activation_repository.dart';
import '../auth/auth_session.dart';
import 'responsive_auth_scaffold.dart';

enum _OwnerActivationState { loading, success, invalid }

class OwnerActivationScreen extends ConsumerStatefulWidget {
  const OwnerActivationScreen({super.key});

  @override
  ConsumerState<OwnerActivationScreen> createState() =>
      _OwnerActivationScreenState();
}

class _OwnerActivationScreenState extends ConsumerState<OwnerActivationScreen> {
  _OwnerActivationState _state = _OwnerActivationState.loading;
  var _started = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    if (session.status == AuthSessionStatus.authenticated && !_started) {
      _started = true;
      Future<void>.microtask(_activate);
    } else if (session.status == AuthSessionStatus.unauthenticated &&
        !_started) {
      _state = _OwnerActivationState.invalid;
    }

    return ResponsiveAuthScaffold(
      title: 'Activate Owner account',
      subtitle: 'Complete the secure first-Owner invitation.',
      child: switch (_state) {
        _OwnerActivationState.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        _OwnerActivationState.success => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Owner account activated successfully.'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('Continue'),
            ),
          ],
        ),
        _OwnerActivationState.invalid => const Text(
          'This Owner activation is invalid, expired, or cannot be completed.',
        ),
      },
    );
  }

  Future<void> _activate() async {
    try {
      await ref.read(accountActivationRepositoryProvider).activateOwner();
      await ref.read(currentAccountProvider.notifier).load();
      if (mounted) setState(() => _state = _OwnerActivationState.success);
    } catch (_) {
      if (mounted) setState(() => _state = _OwnerActivationState.invalid);
    }
  }
}
