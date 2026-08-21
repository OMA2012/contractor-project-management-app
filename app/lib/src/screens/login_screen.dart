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
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  var _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
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
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => context.go('/reset-password'),
            child: const Text('Reset password'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(authSessionProvider.notifier).signIn(email, password);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Sign in failed. Check your credentials.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
