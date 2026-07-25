import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_session.dart';
import 'responsive_auth_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final emailController = TextEditingController(text: 'staff@example.com');

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAuthScaffold(
      title: 'Sign in',
      subtitle: 'Contractor project management',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          const TextField(
            obscureText: true,
            decoration: InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              ref
                  .read(authSessionProvider.notifier)
                  .signInAsStaff(emailController.text);
            },
            child: const Text('Sign in as staff'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              ref
                  .read(authSessionProvider.notifier)
                  .signInAsClient(emailController.text);
            },
            child: const Text('Sign in as client'),
          ),
          TextButton(
            onPressed: () => context.go('/reset-password'),
            child: const Text('Reset password'),
          ),
        ],
      ),
    );
  }
}
