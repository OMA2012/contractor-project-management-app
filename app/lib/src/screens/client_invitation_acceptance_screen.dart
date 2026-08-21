import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/current_account_provider.dart';
import '../auth/account_activation_repository.dart';
import '../auth/auth_session.dart';
import 'responsive_auth_scaffold.dart';

enum _InvitationState { ready, loading, success, invalid }

class ClientInvitationAcceptanceScreen extends ConsumerStatefulWidget {
  const ClientInvitationAcceptanceScreen({required this.token, super.key});

  final String? token;

  @override
  ConsumerState<ClientInvitationAcceptanceScreen> createState() =>
      _ClientInvitationAcceptanceScreenState();
}

class _ClientInvitationAcceptanceScreenState
    extends ConsumerState<ClientInvitationAcceptanceScreen> {
  final fullNameController = TextEditingController();
  _InvitationState _state = _InvitationState.ready;

  @override
  void dispose() {
    fullNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    final token = widget.token?.trim() ?? '';
    final unavailable =
        token.isEmpty || session.status == AuthSessionStatus.unauthenticated;

    return ResponsiveAuthScaffold(
      title: 'Accept invitation',
      subtitle: 'Activate your invited Client portal account.',
      child: switch (_state) {
        _InvitationState.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        _InvitationState.success => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Invitation accepted. Your Client account is active.'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('Continue'),
            ),
          ],
        ),
        _InvitationState.invalid => const Text(
          'This invitation is invalid, expired, or cannot be accepted.',
        ),
        _InvitationState.ready when session.isInitializing => const Center(
          child: CircularProgressIndicator(),
        ),
        _InvitationState.ready when unavailable => const Text(
          'This invitation is invalid, expired, or has no authenticated invitation session.',
        ),
        _InvitationState.ready => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: fullNameController,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _accept,
              child: const Text('Accept invitation'),
            ),
          ],
        ),
      },
    );
  }

  Future<void> _accept() async {
    final token = widget.token?.trim() ?? '';
    final fullName = fullNameController.text.trim();
    if (token.isEmpty || fullName.isEmpty) {
      setState(() => _state = _InvitationState.invalid);
      return;
    }
    setState(() => _state = _InvitationState.loading);
    try {
      await ref
          .read(accountActivationRepositoryProvider)
          .acceptClientInvitation(token: token, fullName: fullName);
      await ref.read(currentAccountProvider.notifier).load();
      if (mounted) setState(() => _state = _InvitationState.success);
    } catch (_) {
      if (mounted) setState(() => _state = _InvitationState.invalid);
    }
  }
}
