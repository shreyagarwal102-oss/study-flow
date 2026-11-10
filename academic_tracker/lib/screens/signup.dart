import 'package:flutter/material.dart';
import 'auth_form.dart';

class Signup extends StatelessWidget {
  const Signup({super.key});

  @override
  Widget build(BuildContext context) => const AuthForm(isSignup: true);
}
