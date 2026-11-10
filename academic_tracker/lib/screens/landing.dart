import 'package:flutter/material.dart';
import '../study_theme.dart';
import 'signup.dart';
import 'login.dart';

class Landing extends StatelessWidget {
  const Landing({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _WelcomePainter())),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 440),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        SizedBox(height: constraints.maxHeight * .30),
                        const StudyLogo(size: 88),
                        const SizedBox(height: 25),
                        const Text(
                          'Study Flow',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Plan. Study. Revise.',
                          style: TextStyle(color: studyMuted, fontSize: 16),
                        ),
                        SizedBox(height: constraints.maxHeight * .22),
                        FilledButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const Signup(),
                            ),
                          ),
                          child: const Text('Get started'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const Login(),
                            ),
                          ),
                          child: const Text('Log in'),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _WelcomePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width, 55),
      165,
      Paint()..color = const Color(0xFFE8F3FD),
    );
    canvas.drawCircle(
      Offset(-65, size.height * .72),
      150,
      Paint()..color = const Color(0xFFF0ECFC),
    );
    final line = Paint()
      ..color = const Color(0xFFCCE2FA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < 2; i++) {
      final y = size.height * .65 + i * 24;
      canvas.drawPath(
        Path()
          ..moveTo(0, y)
          ..cubicTo(
            size.width * .2,
            y - 35,
            size.width * .25,
            y + 55,
            size.width * .45,
            y + 5,
          )
          ..cubicTo(
            size.width * .7,
            y - 65,
            size.width * .8,
            y - 30,
            size.width,
            y - 10,
          ),
        line,
      );
    }
    canvas.drawCircle(
      Offset(size.width * .72, 170),
      6,
      Paint()..color = studyBlue,
    );
    canvas.drawCircle(
      Offset(size.width * .8, size.height * .69),
      5,
      Paint()..color = const Color(0xFF8267D9),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
