import 'dart:async';

import 'package:rumpun_frontend/tunas/tunas.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Tunas sways forever on device; tests need screens that settle.
  tunasIdleMotion = false;
  await testMain();
}
