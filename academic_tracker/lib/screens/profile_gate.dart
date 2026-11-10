import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../study_theme.dart';
import '../user_repository.dart';
import 'class_picker.dart';

/// Sits between sign-in and the app. Watches the user's profile and, while any
/// required field is empty, shows a page asking only for those fields. This
/// runs on every launch, so older accounts that predate a field (such as
/// class) are asked for it too.
class ProfileGate extends StatefulWidget {
  const ProfileGate({
    super.key,
    required this.uid,
    required this.builder,
    this.displayName,
    this.email,
    this.userRepository,
    this.onSignOut,
  });

  final String uid;

  /// Details from the sign-in account, used to fill the profile where they
  /// are already known, so the user is only asked for what is not.
  final String? displayName;
  final String? email;

  /// Builds the app once the profile is complete.
  final Widget Function(AppUser profile) builder;
  final UserRepository? userRepository;
  final Future<void> Function()? onSignOut;

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late final UserRepository _users = widget.userRepository ?? UserRepository();
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _profile;

  // An empty profile read only from this device's cache may simply not have
  // synced yet, for example right after sign-up. Wait briefly for the server
  // before asking the user to fill anything in.
  bool _cacheWaitOver = false;
  Timer? _cacheTimer;

  // Once the app is showing, a later incomplete snapshot (such as a brief
  // cache read) must not send the user back to the form.
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _cacheWaitOver = false;
    _cacheTimer?.cancel();
    _cacheTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _cacheWaitOver = true);
    });
    _profile = _prepareThenWatch();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _prepareThenWatch() async* {
    try {
      await _users
          .ensureProfile(
            AppUser(
              uid: widget.uid,
              fullName: widget.displayName?.trim() ?? '',
              email: widget.email?.trim() ?? '',
            ),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      // Usually offline. The page below still asks for anything missing.
      debugPrint('Could not prepare the profile: $e');
    }
    yield* _users.watchProfile(widget.uid);
  }

  Future<void> _signOut() =>
      (widget.onSignOut ?? FirebaseAuth.instance.signOut)();

  @override
  void dispose() {
    _cacheTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _profile,
    builder: (context, snapshot) {
      final data = snapshot.data;
      if (data == null) {
        if (snapshot.hasError) {
          return _Problem(onRetry: () => setState(_start), onSignOut: _signOut);
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final profile = AppUser.fromMap(widget.uid, data.data() ?? const {});
      final missing = profile.missingFields;
      if (_complete || missing.isEmpty) {
        _complete = true;
        return widget.builder(profile);
      }
      if (data.metadata.isFromCache && !_cacheWaitOver) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return CompleteProfilePage(
        uid: widget.uid,
        missing: missing,
        suggestedName: widget.displayName,
        suggestedEmail: widget.email,
        userRepository: _users,
        onSignOut: _signOut,
      );
    },
  );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.onRetry, required this.onSignOut});
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Could not load your profile',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your connection and try again.',
                style: TextStyle(color: studyMuted),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
              TextButton(onPressed: onSignOut, child: const Text('Sign out')),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Asks only for the profile fields in [missing].
class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({
    super.key,
    required this.uid,
    required this.missing,
    required this.userRepository,
    required this.onSignOut,
    this.suggestedName,
    this.suggestedEmail,
  });

  final String uid;
  final List<ProfileField> missing;
  final UserRepository userRepository;
  final Future<void> Function() onSignOut;
  final String? suggestedName;
  final String? suggestedEmail;

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.suggestedName);
  late final _email = TextEditingController(text: widget.suggestedEmail);
  String? _studentClass;
  bool _saving = false;
  String? _error;

  bool _asks(ProfileField field) => widget.missing.contains(field);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final fields = <String, dynamic>{
      if (_asks(ProfileField.fullName)) 'fullName': _name.text.trim(),
      if (_asks(ProfileField.email)) 'email': _email.text.trim(),
      if (_asks(ProfileField.studentClass)) 'class': _studentClass,
    };
    try {
      // The gate reacts to the local write straight away, so this page usually
      // closes before the server confirms. Offline, the write is queued.
      await widget.userRepository
          .updateProfile(widget.uid, fields)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      // Queued for when the connection returns; nothing to show.
    } catch (e) {
      debugPrint('Could not save the profile: $e');
      if (mounted) {
        setState(() => _error = 'Could not save your details. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Complete your profile',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'We need a few more details before you continue.',
                    style: TextStyle(color: studyMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  if (_asks(ProfileField.fullName)) ...[
                    _label('Full name'),
                    TextFormField(
                      key: const ValueKey('profile-name'),
                      controller: _name,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Riya Sharma',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter your name.'
                          : null,
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (_asks(ProfileField.email)) ...[
                    _label('Email'),
                    TextFormField(
                      key: const ValueKey('profile-email'),
                      controller: _email,
                      enabled: !_saving,
                      keyboardType: TextInputType.emailAddress,
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
                    const SizedBox(height: 18),
                  ],
                  if (_asks(ProfileField.studentClass))
                    ClassPicker(
                      enabled: !_saving,
                      onChanged: (v) => _studentClass = v,
                    ),
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
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _saving ? null : widget.onSignOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
