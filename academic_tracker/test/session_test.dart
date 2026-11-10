import 'dart:async';
import 'package:academic_tracker/main.dart';
import 'package:academic_tracker/screens/home.dart';
import 'package:academic_tracker/screens/landing.dart';
import 'package:academic_tracker/user_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SavedUser implements User {
  @override
  String get uid => 'saved-student';
  @override
  String get displayName => 'Riya Sharma';
  @override
  String get email => 'riya@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late UserRepository users;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final firestore = FakeFirebaseFirestore();
    await profileDoc(firestore, 'saved-student').set({
      'fullName': 'Riya Sharma',
      'email': 'riya@example.com',
      'class': 'Class 10',
      'subjects': <String>[],
    });
    users = UserRepository(firestore: firestore);
  });
  testWidgets('Restored session opens Home without showing authentication', (
    tester,
  ) async {
    final sessions = StreamController<User?>();
    addTearDown(sessions.close);
    await tester.pumpWidget(
      MainApp(authStateChanges: sessions.stream, userRepository: users),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Landing), findsNothing);
    sessions.add(_SavedUser());
    await tester.pumpAndSettle();
    expect(find.byType(Home), findsOneWidget);
    expect(find.textContaining('Riya'), findsOneWidget);
    expect(find.byType(Landing), findsNothing);
    expect(Navigator.of(tester.element(find.byType(Home))).canPop(), isFalse);
  });

  testWidgets(
    'Session changes clear signup routes and return to landing on sign-out',
    (tester) async {
      final sessions = StreamController<User?>();
      addTearDown(sessions.close);
      await tester.pumpWidget(
        MainApp(authStateChanges: sessions.stream, userRepository: users),
      );
      sessions.add(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.text('Create your account'), findsOneWidget);
      sessions.add(_SavedUser());
      await tester.pumpAndSettle();
      expect(find.byType(Home), findsOneWidget);
      expect(find.text('Create your account'), findsNothing);
      expect(Navigator.of(tester.element(find.byType(Home))).canPop(), isFalse);
      sessions.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(Landing), findsOneWidget);
      expect(find.byType(Home), findsNothing);
    },
  );

  testWidgets('Session errors show an error instead of authentication pages', (
    tester,
  ) async {
    final sessions = StreamController<User?>();
    addTearDown(sessions.close);
    await tester.pumpWidget(
      MainApp(authStateChanges: sessions.stream, userRepository: users),
    );
    sessions.addError(Exception('Session restoration failed'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to check your session. Please restart the app.'),
      findsOneWidget,
    );
    expect(find.byType(Landing), findsNothing);
    expect(find.byType(Home), findsNothing);
  });
}
