import 'package:flutter/material.dart';

import '../utils/app_routes.dart';
import '../widgets/custom_button.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              Image.asset('docs/Logo.png', width: 138, height: 138),
              const SizedBox(height: 28),
              const Text(
                'Noted',
                style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              const Text(
                'Organize your study notes easily',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, height: 1.4),
              ),
              const Spacer(),
              CustomButton(
                label: 'Sign In',
                icon: Icons.login_rounded,
                onPressed: () => Navigator.pushNamed(context, AppRoutes.signIn),
              ),
              const SizedBox(height: 12),
              CustomButton(
                label: 'Sign Up',
                icon: Icons.person_add_alt_1_rounded,
                isSecondary: true,
                onPressed: () => Navigator.pushNamed(context, AppRoutes.signUp),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
