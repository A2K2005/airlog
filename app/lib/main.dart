// Bootstrap only: build the data layer (synchronously; the database opens
// in the background), hand it to Riverpod, run the app.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/common/timing.dart';
import 'data/data_module.dart';

void main() {
  Timing.start();
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final data = DataModule.open();
  Timing.mark('run_app');
  runApp(
    ProviderScope(
      overrides: [
        healthRepositoryProvider.overrideWithValue(data.health),
        liveHrServiceProvider.overrideWithValue(data.liveHr),
        coachRepositoryProvider.overrideWithValue(data.coach!.coach),
        coachServiceProvider.overrideWithValue(data.coach!.service),
        insightServiceProvider.overrideWithValue(data.coach!.insightService),
      ],
      child: const AirlogApp(),
    ),
  );
  if (kAirlogTiming) {
    binding.addPostFrameCallback((_) => Timing.mark('first_frame_built'));
    binding.waitUntilFirstFrameRasterized.then(
      (_) => Timing.mark('first_frame_rasterized'),
    );
  }
}
