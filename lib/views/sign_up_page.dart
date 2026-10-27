import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_routes.dart';
import '../utils/note_links.dart';
import '../utils/validators.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/noted_ui.dart';
import '../widgets/reference_icon.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AuthViewModel>().clearError();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    return Scaffold(
        body: SafeArea(
            child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
                    child: ConstrainedBox(
                        constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - 36),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Transform.translate(
                                  offset: const Offset(-12, 0),
                                  child: IconButton(
                                      tooltip: 'Back',
                                      onPressed: () => Navigator.pop(context),
                                      icon: const ReferenceIcon('back'))),
                              const SizedBox(height: 24),
                              const Text('Start your notebook',
                                  style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.75)),
                              const SizedBox(height: 4),
                              Text('It takes less than a minute.',
                                  style: TextStyle(
                                      fontSize: 15,
                                      color: Theme.of(context).hintColor)),
                              const SizedBox(height: 32),
                              AutofillGroup(
                                  child: Form(
                                      key: _formKey,
                                      child: Column(children: [
                                        CustomTextField(
                                            controller: _name,
                                            label: 'Name',
                                            hint: 'Your name',
                                            autofillHints: const [
                                              AutofillHints.name
                                            ],
                                            textInputAction:
                                                TextInputAction.next,
                                            validator: (v) => v
                                                        ?.trim()
                                                        .isNotEmpty ==
                                                    true
                                                ? null
                                                : 'Tell us what to call you.'),
                                        const SizedBox(height: 16),
                                        CustomTextField(
                                            controller: _email,
                                            label: 'Email',
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            autofillHints: const [
                                              AutofillHints.email
                                            ],
                                            textInputAction:
                                                TextInputAction.next,
                                            validator: Validators.email),
                                        const SizedBox(height: 16),
                                        CustomTextField(
                                            controller: _password,
                                            label: 'Password',
                                            hint: 'At least 6 characters',
                                            obscureText: true,
                                            autofillHints: const [
                                              AutofillHints.newPassword
                                            ],
                                            textInputAction:
                                                TextInputAction.done,
                                            onFieldSubmitted: (_) => _submit(),
                                            validator: (v) => v == null ||
                                                    v.length < 6
                                                ? 'Use at least 6 characters.'
                                                : null),
                                        if (auth.errorMessage != null) ...[
                                          const SizedBox(height: 16),
                                          InlineError(auth.errorMessage!)
                                        ],
                                        const SizedBox(height: 24),
                                        CustomButton(
                                            label: auth.isLoading
                                                ? 'Creating account…'
                                                : 'Create account',
                                            isLoading: auth.isLoading,
                                            onPressed: _submit),
                                      ]))),
                              Center(
                                  child: TextButton(
                                      onPressed: () {
                                        auth.clearError();
                                        Navigator.pushReplacementNamed(
                                            context, AppRoutes.signIn);
                                      },
                                      child: Text(
                                          'Already have an account? Sign in',
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: Theme.of(context)
                                                  .hintColor)))),
                            ]))))));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthViewModel>();
    final success = await auth.signUp(
        name: _name.text, email: _email.text, password: _password.text);
    if (!mounted || !success) return;
    Navigator.popUntil(
        context,
        (route) =>
            route.isFirst || noteIdFromLink(route.settings.name ?? '') != null);
  }
}
