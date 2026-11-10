import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:academic_tracker/screens/landing.dart';
import 'package:academic_tracker/screens/auth_form.dart';
import 'package:academic_tracker/screens/home.dart';
import 'package:academic_tracker/study_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final size in [const Size(393, 852), const Size(320, 568)]) {
    testWidgets('Existing pages fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final page in [
        const Landing(),
        const AuthForm(isSignup: true),
        const AuthForm(isSignup: false),
        const Home(displayName: 'Riya Sharma'),
      ]) {
        await tester.pumpWidget(MaterialApp(theme: studyTheme(), home: page));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: page is AuthForm
              ? 'AuthForm signup=${page.isSignup}'
              : page.runtimeType.toString(),
        );
      }
      expect(find.textContaining('Riya'), findsOneWidget);
    });
  }
  testWidgets('Landing opens signup and validates empty fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: studyTheme(), home: const Landing()),
    );
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name.'), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
