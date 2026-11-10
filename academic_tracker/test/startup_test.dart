import 'dart:async';
import 'package:academic_tracker/main.dart';
import 'package:academic_tracker/screens/landing.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('First screen draws while native initialization is pending', (
    tester,
  ) async {
    final initialization = Completer<void>();
    await tester.pumpWidget(
      StartupApp(
        initialize: () => initialization.future,
        authStateChanges: Stream<User?>.value(null),
      ),
    );
    await tester.pump();
    expect(find.text('Starting your workspace…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(MainApp), findsNothing);
    initialization.complete();
    await tester.pumpAndSettle();
    expect(find.byType(Landing), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Initialization failure shows a retry and recovery opens the app',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        StartupApp(
          initialize: () async {
            if (attempts++ == 0) {
              throw StateError('Native initialization failed');
            }
          },
          authStateChanges: Stream<User?>.value(null),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not start Study Flow'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byType(Landing), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A stalled initialization times out instead of leaving a blank app',
    (tester) async {
      final initialization = Completer<void>();
      await tester.pumpWidget(
        StartupApp(
          initialize: () => initialization.future,
          initializationTimeout: const Duration(seconds: 2),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
        find.text('Account services took too long to respond. Please retry.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(MainApp), findsNothing);
      initialization.complete();
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
