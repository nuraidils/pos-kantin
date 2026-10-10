import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/auth_validators.dart';
import '../bloc/auth_bloc.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(
      AuthLoginSubmitted(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final loading = state is AuthInProgress;
        final failure = state is AuthFailure ? state : null;
        final notice = state is AuthUnauthenticated ? state.message : null;

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                              ),
                              child: const Icon(
                                Icons.storefront_rounded,
                                color: Colors.white,
                                size: 28,
                                semanticLabel: 'Kasir Kantin',
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Text('Kasir Kantin', style: text.headlineMedium),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Masuk untuk mulai berjualan.',
                            style: text.bodySmall,
                          ),
                          const SizedBox(height: AppSpacing.x3l),
                          if (notice != null) ...[
                            _MessageBanner(
                              icon: Icons.info_outline,
                              iconColor: AppColors.info,
                              background: AppColors.infoSoft,
                              borderColor: AppColors.info,
                              message: notice,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          if (failure != null) ...[
                            _MessageBanner(
                              icon: Icons.error_outline,
                              iconColor: AppColors.danger,
                              background: AppColors.dangerSoft,
                              borderColor: AppColors.danger,
                              message: failure.message,
                              details: failure.fieldErrors.values
                                  .expand((errors) => errors)
                                  .toList(),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          TextFormField(
                            controller: _emailController,
                            enabled: !loading,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: validateEmail,
                            onFieldSubmitted: (_) =>
                                _passwordFocus.requestFocus(),
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'nama@contoh.com',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          TextFormField(
                            controller: _passwordController,
                            focusNode: _passwordFocus,
                            enabled: !loading,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: validatePassword,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Kata sandi',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Tampilkan kata sandi'
                                    : 'Sembunyikan kata sandi',
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          FilledButton(
                            // null saat memproses = tombol nonaktif, cegah kirim ganda.
                            onPressed: loading ? null : _submit,
                            child: loading
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      SizedBox(width: AppSpacing.md),
                                      Text('Memproses...'),
                                    ],
                                  )
                                : const Text('Masuk'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pesan selalu memakai ikon + teks, tidak hanya warna (DESIGN.md §37).
class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.borderColor,
    required this.message,
    this.details = const [],
  });

  final IconData icon;
  final Color iconColor;
  final Color background;
  final Color borderColor;
  final String message;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: text.bodyMedium),
                  for (final detail in details)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(detail, style: text.bodySmall),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
