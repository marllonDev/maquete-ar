import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../widgets/brand_mark.dart';
import 'architect_login_screen.dart';
import 'client_code_screen.dart';

/// Screen 1 — brand, then the fork between the two audiences.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 3),
              const Center(child: BrandMark(size: 84)),
              const SizedBox(height: 28),
              Text(
                AppInfo.appName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.8,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                AppInfo.tagline,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.inkSoft,
                    ),
              ),
              const Spacer(flex: 4),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ArchitectLoginScreen(),
                  ),
                ),
                child: const Text('Sou Arquiteto'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ClientCodeScreen()),
                ),
                child: const Text('Sou Cliente'),
              ),
              const SizedBox(height: 20),
              Text(
                'Cliente entra com um codigo de 6 digitos. Sem cadastro.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.inkSoft,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
