import 'package:academic_tracker/models/app_user.dart';
import 'package:academic_tracker/screens/profile_gate.dart';
import 'package:academic_tracker/study_theme.dart';
import 'package:academic_tracker/user_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository users;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    users = UserRepository(firestore: firestore);
  });

  Future<void> pumpGate(
    WidgetTester tester, {
    String? displayName = 'Riya Sharma',
    String? email = 'riya@example.com',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studyTheme(),
        home: ProfileGate(
          uid: 'uid-1',
          displayName: displayName,
          email: email,
          userRepository: users,
          onSignOut: () async {},
          builder: (profile) =>
              Scaffold(body: Text('App for ${profile.fullName}')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('missingFields lists only the empty required fields', () {
    const complete = AppUser(
      uid: 'u',
      fullName: 'Riya',
      email: 'r@example.com',
      studentClass: 'Class 10',
    );
    expect(complete.missingFields, isEmpty);
    const blank = AppUser(uid: 'u', fullName: ' ', email: '');
    expect(blank.missingFields, [
      ProfileField.fullName,
      ProfileField.email,
      ProfileField.studentClass,
    ]);
  });

  testWidgets('A complete profile goes straight to the app', (tester) async {
    await tester.runAsync(
      () => profileDoc(firestore, 'uid-1').set({
        'fullName': 'Riya Sharma',
        'email': 'riya@example.com',
        'class': 'Class 10',
        'subjects': <String>[],
      }),
    );
    await pumpGate(tester);
    expect(find.text('App for Riya Sharma'), findsOneWidget);
    expect(find.text('Complete your profile'), findsNothing);
  });

  testWidgets('An older account is asked only for its missing class', (
    tester,
  ) async {
    await tester.runAsync(
      () => profileDoc(firestore, 'uid-1').set({
        'fullName': 'Riya Sharma',
        'email': 'riya@example.com',
        'subjects': <String>[],
      }),
    );
    await pumpGate(tester);
    expect(find.text('Complete your profile'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-name')), findsNothing);
    expect(find.byKey(const ValueKey('profile-email')), findsNothing);
    expect(find.text('Select class'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your class.'), findsOneWidget);

    await tester.tap(find.text('Select class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Class 10').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('App for Riya Sharma'), findsOneWidget);
    final saved = await tester.runAsync(
      () => profileDoc(firestore, 'uid-1').get(),
    );
    expect(saved!.data()!['class'], 'Class 10');
  });

  testWidgets('A new account without a name is asked for name and class', (
    tester,
  ) async {
    await pumpGate(tester, displayName: null);
    expect(find.byKey(const ValueKey('profile-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-email')), findsNothing);
    expect(find.text('Select class'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
