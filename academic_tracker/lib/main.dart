import 'dart:async';
import 'package:academic_tracker/screens/landing.dart';
import 'package:academic_tracker/screens/home.dart';
import 'package:academic_tracker/screens/profile_gate.dart';
import 'package:academic_tracker/user_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'study_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StartupApp());
}

Future<void> _initializeFirebase() async {
  await Firebase.initializeApp();
}

/// Draw the first screen before waiting on a native plugin. A failed or stalled
/// Firebase call must never leave the Android launch window on screen forever.
class StartupApp extends StatefulWidget {
  const StartupApp({
    super.key,
    this.initialize,
    this.authStateChanges,
    this.initializationTimeout = const Duration(seconds: 20),
  });

  final Future<void> Function()? initialize;
  final Stream<User?>? authStateChanges;
  final Duration initializationTimeout;

  @override
  State<StartupApp> createState() => _StartupAppState();
}

class _StartupAppState extends State<StartupApp> {
  Object? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      await Future<void>.sync(
        widget.initialize ?? _initializeFirebase,
      ).timeout(widget.initializationTimeout);
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      debugPrint('Study Flow initialization failed: $error');
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return MainApp(authStateChanges: widget.authStateChanges);
    }
    return MaterialApp(
      title: 'Study Flow',
      debugShowCheckedModeBanner: false,
      theme: studyTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const StudyLogo(size: 64),
                  const SizedBox(height: 24),
                  const Text(
                    'Study Flow',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    const Text(
                      'Could not start Study Flow',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error is TimeoutException
                          ? 'Account services took too long to respond. Please retry.'
                          : 'Account services could not initialize. Please retry.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: studyMuted),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: _start, child: const Text('Retry')),
                  ] else ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text(
                      'Starting your workspace…',
                      style: TextStyle(color: studyMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key, this.authStateChanges, this.userRepository});

  // Tests can provide session events and profiles without connecting to
  // Firebase.
  final Stream<User?>? authStateChanges;
  final UserRepository? userRepository;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final Stream<User?> _authStateChanges;

  @override
  void initState() {
    super.initState();
    _authStateChanges =
        widget.authStateChanges ?? FirebaseAuth.instance.authStateChanges();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _authStateChanges,
    builder: (context, snapshot) {
      final Widget page;
      if (snapshot.hasError) {
        page = const Scaffold(
          body: Center(
            child: Text(
              'Unable to check your session. Please restart the app.',
            ),
          ),
        );
      } else if (snapshot.connectionState == ConnectionState.waiting) {
        // Wait for Firebase to restore a saved session before showing auth pages.
        page = const Scaffold(body: Center(child: CircularProgressIndicator()));
      } else {
        final user = snapshot.data;
        page = user == null
            ? const Landing()
            : ProfileGate(
                uid: user.uid,
                displayName: user.displayName,
                email: user.email,
                userRepository: widget.userRepository,
                builder: (profile) =>
                    Home(displayName: profile.fullName, userId: user.uid),
              );
      }
      return MaterialApp(
        // A session change replaces the navigator, clearing login/signup routes.
        key: ValueKey((
          snapshot.connectionState == ConnectionState.waiting,
          snapshot.hasError,
          snapshot.data?.uid,
        )),
        title: 'Study Flow',
        debugShowCheckedModeBanner: false,
        theme: studyTheme(),
        home: page,
      );
    },
  );
}
