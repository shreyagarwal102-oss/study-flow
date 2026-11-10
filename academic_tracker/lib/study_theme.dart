import 'package:flutter/material.dart';

const studyBlue = Color(0xFF318DE5);
const studyInk = Color(0xFF182133);
const studyMuted = Color(0xFF71829C);
const studyBackground = Color(0xFFF7F9FC);
const studyBorder = Color(0xFFDFE6F0);
ThemeData studyTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: studyBackground,
  colorScheme: ColorScheme.fromSeed(seedColor: studyBlue, primary: studyBlue),
  textTheme: ThemeData.light().textTheme.apply(
    bodyColor: studyInk,
    displayColor: studyInk,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: studyBackground,
    foregroundColor: studyInk,
    elevation: 0,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    hintStyle: const TextStyle(color: studyMuted, fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: studyBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: studyBorder),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(double.infinity, 54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(double.infinity, 50),
      foregroundColor: studyInk,
      backgroundColor: Colors.white,
      side: const BorderSide(color: studyBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
  ),
);

class StudyLogo extends StatelessWidget {
  const StudyLogo({super.key, this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: studyBlue,
      borderRadius: BorderRadius.circular(size * .28),
    ),
    child: Icon(Icons.insights_rounded, color: Colors.white, size: size * .58),
  );
}

class StudyCard extends StatelessWidget {
  const StudyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: studyBorder),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(padding: padding, child: child),
  );
}
