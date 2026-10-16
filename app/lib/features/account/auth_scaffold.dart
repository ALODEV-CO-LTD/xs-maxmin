import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// Shared frame of the register / recover screens: MAMBA header, title, optional back arrow to /login.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, this.subtitle, required this.children, this.onBack});
  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Custom back action (null = pop, or go to /login when there is nothing to pop).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Quay lại',
          onPressed: onBack ?? () => context.canPop() ? context.pop() : context.go('/login'),
        ),
        title: Image.asset(
          'assets/images/logo-word.png',
          height: 20,
          semanticLabel: 'MAMBA',
          errorBuilder: (_, _, _) => const Text('MAMBA', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 3)),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: TextStyle(color: context.mutedColor))),
                const SizedBox(height: 16),
                ...children,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
