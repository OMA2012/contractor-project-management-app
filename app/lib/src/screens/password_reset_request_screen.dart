import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_session.dart';
import 'responsive_auth_scaffold.dart';

class PasswordResetRequestScreen extends ConsumerStatefulWidget {
  const PasswordResetRequestScreen({super.key});

  @override
  ConsumerState<PasswordResetRequestScreen> createState() =>
      _PasswordResetRequestScreenState();
}

class _PasswordResetRequestScreenState
    extends ConsumerState<PasswordResetRequestScreen> {
  final emailController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAuthScaffold(
      title: 'Reset password',
      subtitle: 'Request a secure password reset link.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              ref
                  .read(authSessionProvider.notifier)
                  .requestPasswordReset(emailController.text);
            },
            child: const Text('Send reset link'),
          ),
        ],
      ),
    );
  }
}
