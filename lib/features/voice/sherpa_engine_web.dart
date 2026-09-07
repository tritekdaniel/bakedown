import 'dart:async';

class SherpaEngine {
  SherpaEngine({required this.onWakeWordDetected});
  final void Function() onWakeWordDetected;
  static void initBindings() {}
  Future<void> init() async {}
  Future<void> start() async {}
  Future<void> stopMic() async {}
  Future<void> resetToWakeListening() async {}
  Future<void> stop() async {}
  Future<void> playWakeSound() async {}
  Future<void> playCommandFeedback() async {}
  Future<void> playUnknownFeedback() async {}
  Future<void> playVoiceActivated() async {}
  Future<void> playVoiceDeactivated() async {}
  void dispose() {}
}
