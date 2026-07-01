import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/settings/presentation/providers/settings_providers.dart';
import 'features/voice/sherpa_engine.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SherpaEngine.initBindings();
  runApp(
    const ProviderScope(child: _SettingsLoader()),
  );
}

class _SettingsLoader extends ConsumerStatefulWidget {
  const _SettingsLoader();

  @override
  ConsumerState<_SettingsLoader> createState() => _SettingsLoaderState();
}

class _SettingsLoaderState extends ConsumerState<_SettingsLoader> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(settingsProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const RecipeApp();
  }
}
