import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../study_theme.dart';
import '../user_repository.dart';
import 'class_picker.dart';
import 'signup.dart';

class AuthForm extends StatefulWidget {
  const AuthForm({super.key, required this.isSignup});
  final bool isSignup;

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidden = true;
  bool _keepLoggedIn = true;
  String? _studentClass;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (kIsWeb && !widget.isSignup) {
        await auth.setPersistence(
          _keepLoggedIn ? Persistence.LOCAL : Persistence.SESSION,
        );
      }
      if (widget.isSignup) {
        // Read these first: creating the account replaces this page with Home.
        final fullName = _name.text.trim();
        final email = _email.text.trim();
        final studentClass = _studentClass;
        final result = await auth.createUserWithEmailAndPassword(
          email: email,
          password: _password.text,
        );
        // A profile failure must not prompt the user to create the account again.
        try {
          await UserRepository()
              .saveProfile(
                AppUser(
                  uid: result.user!.uid,
                  fullName: fullName,
                  email: email,
                  studentClass: studentClass,
                ),
              )
              .timeout(const Duration(seconds: 10));
        } catch (error) {
          debugPrint('Could not save the user profile: $error');
        }
        // A verified email lets Firebase attach Google to this same account
        // later. Without it, signing in with Google for a Gmail address
        // replaces the password instead of adding to it.
        result.user!.sendEmailVerification().catchError(
          (Object e) => debugPrint('Could not send verification email: $e'),
        );
        try {
          await result.user!.updateDisplayName(fullName);
        } on FirebaseAuthException {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Account created, but your name could not be saved.',
                ),
              ),
            );
          }
        }
      } else {
        await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = switch (e.code) {
          'invalid-email' => 'Enter a valid email address.',
          'email-already-in-use' =>
            'This email already has an account. Sign in instead.',
          'weak-password' =>
            'Choose a stronger password that meets the project password policy.',
          'invalid-credential' || 'wrong-password' || 'user-not-found' =>
            'Incorrect email or password. If you signed up with Google, use Continue with Google or reset your password.',
          'user-disabled' => 'This account has been disabled.',
          'too-many-requests' => 'Too many attempts. Please try again later.',
          'network-request-failed' =>
            'Check your internet connection and try again.',
          'operation-not-allowed' =>
            'Enable Email/Password in Firebase Authentication.',
          _ => 'Authentication failed. Please try again.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider());
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        await _connectGoogle(e.email);
      } else {
        debugPrint('Google sign-in failed: ${e.code} ${e.message}');
        _showError(
          'Google sign-in is unavailable. Please use email or try again.',
        );
      }
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      _showError(
        'Google sign-in is unavailable. Please use email or try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (mounted) setState(() => _error = message);
  }

  /// This email already has a password account, and Firebase keeps one account
  /// per email. Confirm the password once, then attach Google to that same
  /// account: same UID, same data, and both sign-in methods work afterwards.
  Future<void> _connectGoogle(String? knownEmail) async {
    final details = await _askForPassword(knownEmail);
    if (details == null) {
      _showError('Google was not connected. Log in with your password.');
      return;
    }
    final User user;
    try {
      final result = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: details.email,
        password: details.password,
      );
      user = result.user!;
    } on FirebaseAuthException catch (e) {
      _showError(
        e.code == 'too-many-requests'
            ? 'Too many attempts. Please try again later.'
            : 'That password is not correct for ${details.email}.',
      );
      return;
    }
    // Signing in has already opened the app, so this page may be gone. Linking
    // still runs; if it fails, the user is signed in and can retry later.
    try {
      await user.linkWithProvider(GoogleAuthProvider());
    } on FirebaseAuthException catch (e) {
      if (e.code != 'provider-already-linked') {
        debugPrint('Could not connect Google: ${e.code} ${e.message}');
      }
    }
  }

  Future<({String email, String password})?> _askForPassword(
    String? knownEmail,
  ) {
    final email = TextEditingController(text: knownEmail ?? _email.text.trim());
    final password = TextEditingController();
    final form = GlobalKey<FormState>();
    return showDialog<({String email, String password})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect Google to your account'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'An account with ${knownEmail ?? 'this email'} already uses a '
                'password. Enter it once to connect Google; after that you can '
                'use either.',
              ),
              const SizedBox(height: 16),
              if (knownEmail == null)
                TextFormField(
                  controller: email,
                  decoration: const InputDecoration(hintText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter your email.'
                      : null,
                ),
              TextFormField(
                controller: password,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Password'),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Enter your password.' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, (
                email: email.text.trim(),
                password: password.text,
              ));
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword() async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      setState(() => _error = 'Enter your email above to reset your password.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _email.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset requested. Check your email.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not send a reset email. Please try again.',
        );
      }
    }
  }

  Widget _field(String label, Widget field) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        field,
      ],
    ),
  );

  Widget _divider(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Row(
      children: [
        const Expanded(child: Divider(color: studyBorder)),
        Flexible(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              text,
              style: const TextStyle(color: studyMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const Expanded(child: Divider(color: studyBorder)),
      ],
    ),
  );

  Widget _googleButton() => OutlinedButton.icon(
    onPressed: _busy ? null : _google,
    icon: const CircleAvatar(
      radius: 11,
      backgroundColor: studyBackground,
      child: Text('G', style: TextStyle(fontSize: 13, color: studyMuted)),
    ),
    label: const Text('Continue with Google'),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.maybePop(context),
                        icon: const Icon(Icons.chevron_left),
                        tooltip: 'Back',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!widget.isSignup) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: StudyLogo(),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      widget.isSignup ? 'Create your account' : 'Welcome back',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isSignup
                          ? 'Set up Study Flow in under a minute.'
                          : 'Log in to pick up where you left off.',
                      style: const TextStyle(color: studyMuted, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    if (widget.isSignup) ...[
                      _googleButton(),
                      _divider('or sign up with email'),
                      _field(
                        'Full name',
                        TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            hintText: 'e.g. Riya Sharma',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter your name.'
                              : null,
                        ),
                      ),
                    ],
                    _field(
                      'Email',
                      TextFormField(
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          hintText: 'you@example.com',
                        ),
                        validator: (v) =>
                            v == null ||
                                !RegExp(
                                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                ).hasMatch(v.trim())
                            ? 'Enter a valid email address.'
                            : null,
                      ),
                    ),
                    _field(
                      'Password',
                      TextFormField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _hidden,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: [
                          widget.isSignup
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          hintText: widget.isSignup
                              ? 'At least 8 characters'
                              : 'Your password',
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _hidden = !_hidden),
                            tooltip: _hidden
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: studyMuted,
                              size: 20,
                            ),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Enter your password.'
                            : widget.isSignup && v.length < 8
                            ? 'Use at least 8 characters.'
                            : null,
                      ),
                    ),
                    if (widget.isSignup) ...[
                      ClassPicker(
                        enabled: !_busy,
                        onChanged: (v) => _studentClass = v,
                      ),
                      const Text(
                        'By creating an account you agree to the Terms and Privacy Policy.',
                        style: TextStyle(
                          color: studyMuted,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ] else ...[
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _keepLoggedIn,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() => _keepLoggedIn = v!),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Keep me logged in',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _resetPassword,
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(widget.isSignup ? 'Create account' : 'Log in'),
                    ),
                    if (!widget.isSignup) ...[
                      _divider('or'),
                      _googleButton(),
                      const SizedBox(height: 80),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'New to Study Flow?',
                            style: TextStyle(color: studyMuted, fontSize: 13),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => const Signup(),
                                    ),
                                  ),
                            child: const Text('Create an account'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
