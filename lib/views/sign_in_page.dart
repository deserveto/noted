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

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
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
                              const Text('Welcome back',
                                  style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.75)),
                              const SizedBox(height: 4),
                              Text('Sign in to pick up where you left off.',
                                  style: TextStyle(
                                      fontSize: 15,
                                      color: Theme.of(context).hintColor)),
                              const SizedBox(height: 32),
                              AutofillGroup(
                                  child: Form(
                                      key: _formKey,
                                      child: Column(children: [
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
                                              AutofillHints.password
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
                                                ? 'Signing in…'
                                                : 'Sign in',
                                            isLoading: auth.isLoading,
                                            onPressed: _submit),
                                      ]))),
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                      onPressed: _resetPassword,
                                      child: const Text('Forgot password?',
                                          style: TextStyle(fontSize: 13)))),
                              Center(
                                  child: TextButton(
                                      onPressed: () {
                                        auth.clearError();
                                        Navigator.pushReplacementNamed(
                                            context, AppRoutes.signUp);
                                      },
                                      child: Text(
                                          'New to Noted? Create an account',
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: Theme.of(context)
                                                  .hintColor)))),
                            ]))))));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthViewModel>();
    final success =
        await auth.signIn(email: _email.text, password: _password.text);
    if (!mounted || !success) return;
    Navigator.popUntil(
        context,
        (route) =>
            route.isFirst || noteIdFromLink(route.settings.name ?? '') != null);
  }

  Future<void> _resetPassword() async {
    final email = TextEditingController(text: _email.text);
    final form = GlobalKey<FormState>();
    final auth = context.read<AuthViewModel>();
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          bool busy = false;
          String? error;
          return StatefulBuilder(
              builder: (context, setSheetState) => SafeArea(
                  child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20,
                          24 + MediaQuery.viewInsetsOf(context).bottom),
                      child: Form(
                          key: form,
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Reset your password',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                const Text(
                                    'We’ll send a password reset link to your email.'),
                                const SizedBox(height: 20),
                                CustomTextField(
                                    controller: email,
                                    label: 'Email',
                                    keyboardType: TextInputType.emailAddress,
                                    validator: Validators.email),
                                if (error != null) ...[
                                  const SizedBox(height: 12),
                                  InlineError(error!)
                                ],
                                const SizedBox(height: 20),
                                CustomButton(
                                    label: 'Send reset link',
                                    isLoading: busy,
                                    onPressed: () async {
                                      if (!form.currentState!.validate()) {
                                        return;
                                      }
                                      setSheetState(() {
                                        busy = true;
                                        error = null;
                                      });
                                      final ok =
                                          await auth.resetPassword(email.text);
                                      if (!sheetContext.mounted) return;
                                      if (ok) {
                                        Navigator.pop(sheetContext);
                                        if (mounted) {
                                          notedToast(this.context,
                                              'Password reset link sent. Check your email.');
                                        }
                                      } else {
                                        setSheetState(() {
                                          busy = false;
                                          error = auth.errorMessage;
                                        });
                                      }
                                    })
                              ])))));
        });
    email.dispose();
  }
}
