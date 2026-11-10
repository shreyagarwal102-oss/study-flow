import 'package:flutter/material.dart';
import 'auth_form.dart';

class Login extends StatelessWidget {
  const Login({super.key});

  @override
  Widget build(BuildContext context) => const AuthForm(isSignup: false);
}
