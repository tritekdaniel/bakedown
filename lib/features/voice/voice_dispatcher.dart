import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_app/app.dart';
import 'package:recipe_app/features/recipes/presentation/providers/recipe_providers.dart';
import 'package:recipe_app/features/settings/presentation/providers/settings_providers.dart';
import 'package:recipe_app/features/timer/presentation/providers/timer_providers.dart';
import 'package:recipe_app/features/timer/presentation/widgets/timer_overlay.dart';
import 'package:recipe_app/features/tts/presentation/providers/tts_providers.dart';
import 'voice_command.dart';
import 'voice_command_matcher.dart';
import 'voice_providers.dart';

class VoiceDispatcher extends ConsumerStatefulWidget {
  final Widget child;

  const VoiceDispatcher({super.key, required this.child});

  @override
  ConsumerState<VoiceDispatcher> createState() => _VoiceDispatcherState();
}

class _VoiceDispatcherState extends ConsumerState<VoiceDispatcher> {
  bool _engineInitialized = false;
  int _sttSessionId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initVoice());
  }

  Future<void> _initVoice() async {
    if (kIsWeb) return;
    try {
      final tts = ref.read(ttsServiceProvider);
      await tts.initialize();
      final engine = ref.read(sherpaEngineProvider);
      await engine.init();
      _engineInitialized = true;

      final enabled = ref.read(voiceEnabledProvider);
      if (enabled) {
        ref.read(voiceListeningProvider.notifier).state = true;
      }
    } catch (_) {
      _engineInitialized = false;
    }
  }

  void _onCommandText(String text) {
    print('[VOICE] onCommandText "$text" state=${ref.read(voiceStateProvider)}');
    final state = ref.read(voiceStateProvider);
    if (state != VoiceState.wakeDetected && state != VoiceState.commandListening) return;

    final recipesAsync = ref.read(recipesInFolderProvider);
    final recipes = recipesAsync.valueOrNull ?? [];
    final requireWake = ref.read(settingsProvider).voiceRequireWakePrefix;

    final command = matchCommand(
      text,
      recipes: recipes,
      requireWake: requireWake,
    );

    ref.read(voiceCommandProvider.notifier).state = command;
    _dispatchCommand(command);
  }

  void _dispatchCommand(VoiceCommand command) {
    final router = ref.read(goRouterProvider);

    switch (command) {
      case StopListening():
        _sttSessionId++;
        ref.read(speechToTextProvider).stop();
        _stopListening();
        return;
      case ReadStop():
        ref.read(ttsStateProvider.notifier).stop();
        _showSnack('Stopped reading');
      case ReadPause():
        ref.read(ttsStateProvider.notifier).pause();
        _showSnack('Paused');
      case ReadResume():
        ref.read(ttsStateProvider.notifier).resume();
        _showSnack('Resumed');
      case ReadNext():
        ref.read(ttsStateProvider.notifier).next();
      case ReadPrevious():
        ref.read(ttsStateProvider.notifier).previous();
      case ReadIngredients():
        _readIngredients();
      case ReadInstructions():
        _readInstructions();
      case ReadStepN(:final stepNumber):
        _readStep(stepNumber);
      case NavigateHome():
        router.go('/');
      case NavigateSettings():
        router.go('/settings');
      case NavigateTranscode():
        router.go('/transcode');
      case NavigateToRecipe(:final folder, :final filename):
        router.go('/folder/${Uri.encodeComponent(folder)}/recipe/${Uri.encodeComponent(filename)}');
      case GoBack():
        if (router.canPop()) {
          router.pop();
        } else {
          _showSnack('Nothing to go back from');
        }
      case ScaleRecipe(:final factor):
        ref.read(scaleFactorProvider.notifier).state = factor;
        _showSnack('Scaled to $factor×');
      case ConvertUnit(:final unit):
        _showSnack('Convert to $unit');
        break;
      case SwitchTab():
        break;
      case ToggleCheckbox():
        break;
      case SetTimer(:final seconds, :final label):
        ref.read(timerListProvider.notifier).addTimer(seconds, label: label);
        final display = label != null ? '$label ($seconds s)' : '$seconds s';
        _showSnack('Timer set: $display');
      case CancelTimer(:final label):
        ref.read(timerListProvider.notifier).cancelTimer(label);
        _showSnack(label != null ? 'Cancelled timer "$label"' : 'Cancelled timer');
      case PauseTimer(:final label):
        ref.read(timerListProvider.notifier).pauseTimer(label);
        _showSnack(label != null ? 'Paused timer "$label"' : 'Paused timer');
      case ResumeTimer(:final label):
        ref.read(timerListProvider.notifier).resumeTimer(label);
        _showSnack(label != null ? 'Resumed timer "$label"' : 'Resumed timer');
      case HowMuchTimeLeft():
        _showTimeLeft();
      case UnknownCommand(:final text):
        ref.read(sherpaEngineProvider).playUnknownFeedback();
        _showSnack('Unknown: "$text"');
        _finishCommandCycle();
        return;
    }

    ref.read(sherpaEngineProvider).playCommandFeedback();
    _finishCommandCycle();
  }

  Future<void> _finishCommandCycle() async {
    _sttSessionId++;
    final stt = ref.read(speechToTextProvider);
    final engine = ref.read(sherpaEngineProvider);

    // Set state before stop so onStatus guards see it immediately
    ref.read(voiceStateProvider.notifier).state = VoiceState.wakeListening;

    await stt.stop().timeout(
      const Duration(milliseconds: 900),
      onTimeout: () => print('[VOICE] stt.stop() timed out in _finishCommandCycle'),
    );
    await engine.resetToWakeListening();
  }

  Future<void> _startSTT() async {
    final stt = ref.read(speechToTextProvider);
    final engine = ref.read(sherpaEngineProvider);
    bool soundPlayed = false;
    bool recovered = false;
    final sessionId = ++_sttSessionId;

    Future<void> recoverToWakeListening() async {
      if (recovered || sessionId != _sttSessionId) return;
      recovered = true;
      print('[VOICE] recoverToWakeListening (session $sessionId)');
      ref.read(voiceStateProvider.notifier).state = VoiceState.wakeListening;
      await engine.resetToWakeListening();
    }

    await engine.stopMic();
    await Future.delayed(const Duration(milliseconds: 100));

    final started = await stt.listen(
      onResult: (text) {
        if (text.isNotEmpty) {
          ref.read(voiceCommandRawProvider.notifier).state = text;
          _onCommandText(text);
        }
      },
      onStatus: (status) {
        if (status == 'listening' && !soundPlayed) {
          soundPlayed = true;
          engine.playWakeSound();
          if (ref.read(voiceStateProvider) == VoiceState.wakeDetected) {
            ref.read(voiceStateProvider.notifier).state = VoiceState.commandListening;
          }
        }
        if (status == 'done' || status == 'notListening') {
          if (soundPlayed && ref.read(voiceStateProvider) != VoiceState.wakeListening) {
            recoverToWakeListening();
          }
        }
      },
      onError: (error) {
        print('[STT] error in session $sessionId: $error');
        recoverToWakeListening();
      },
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 3),
      onDevice: true,
    );

    if (!started) {
      _sttSessionId++;
      ref.read(voiceStateProvider.notifier).state = VoiceState.wakeListening;
      await engine.resetToWakeListening();
      return;
    }

    Future.delayed(const Duration(seconds: 14), () async {
      if (sessionId != _sttSessionId) return;
      if (ref.read(voiceStateProvider) == VoiceState.wakeDetected ||
          ref.read(voiceStateProvider) == VoiceState.commandListening) {
        _sttSessionId++;
        await stt.stop();
        if (!soundPlayed) engine.playWakeSound();
        if (!recovered) {
          recovered = true;
          ref.read(voiceStateProvider.notifier).state = VoiceState.wakeListening;
          await engine.resetToWakeListening();
        }
      }
    });
  }

  void _readIngredients() {
    final sections = ref.read(recipeSectionsProvider);
    final ingredients = sections['ingredients'] ?? [];
    if (ingredients.isEmpty) {
      _showSnack('No ingredients found in recipe');
      return;
    }
    ref.read(ttsStateProvider.notifier).speakPhrases(ingredients);
  }

  void _readInstructions() {
    final sections = ref.read(recipeSectionsProvider);
    final steps = sections['instructions'] ?? [];
    if (steps.isEmpty) {
      _showSnack('No instructions found');
      return;
    }
    ref.read(ttsStateProvider.notifier).speakPhrases(steps);
  }

  void _readStep(int stepNumber) {
    final sections = ref.read(recipeSectionsProvider);
    final steps = sections['instructions'] ?? [];
    if (stepNumber < 1 || stepNumber > steps.length) {
      _showSnack('Step $stepNumber not found (1-${steps.length})');
      return;
    }
    ref.read(ttsStateProvider.notifier).speakPhrases([steps[stepNumber - 1]]);
  }

  void _showTimeLeft() {
    final active = ref.read(activeTimersProvider);
    if (active.isEmpty) {
      _showSnack('No active timers');
      return;
    }
    final nearest = active.first;
    final remaining = nearest.remaining;
    final m = remaining.inMinutes.remainder(60);
    final s = remaining.inSeconds.remainder(60);
    final timeStr = m > 0 ? '${m}m ${s}s' : '${s}s';
    _showSnack('${nearest.label}: $timeStr remaining');
  }

  void _stopListening() {
    final engine = ref.read(sherpaEngineProvider);
    engine.stop().then((_) {
      if (mounted) {
        ref.read(voiceListeningProvider.notifier).state = false;
      }
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(voiceListeningProvider, (prev, next) {
      if (prev == next || !_engineInitialized) return;
      final engine = ref.read(sherpaEngineProvider);
      if (next) {
        engine.start().then((_) => engine.playVoiceActivated());
      } else {
        engine.playVoiceDeactivated();
        engine.stop();
      }
    });

    ref.listen<VoiceState>(voiceStateProvider, (prev, next) {
      if (next == VoiceState.wakeDetected && prev != next) {
        _startSTT();
      }
    });

    final voiceState = ref.watch(voiceStateProvider);
    final isListening = voiceState != VoiceState.idle;
    final badgeLabel = switch (voiceState) {
      VoiceState.wakeListening => 'Listening...',
      VoiceState.wakeDetected => 'Wake word!',
      VoiceState.commandListening => 'Processing...',
      VoiceState.idle => '',
    };

    return Stack(
      children: [
        widget.child,
        const TimerOverlay(),
        if (isListening)
          Positioned(
            left: 0,
            right: 0,
            bottom: 80 + MediaQuery.of(context).viewPadding.bottom,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      badgeLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
