// Coach setup no longer exists as its own screen, and nothing walls the
// chat: the coach answers on this phone from the first question, and
// Claude or Gemini is connected in Settings → Coach (the Connect sheet:
// key, then consent). Routes.coachSetup stays registered so an old link or
// a cold start still resolves: it builds Settings → Coach.

import 'package:flutter/material.dart';

import 'coach_settings_screen.dart';

class CoachSetupScreen extends StatelessWidget {
  const CoachSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => const CoachSettingsScreen();
}
