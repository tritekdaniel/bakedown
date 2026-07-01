import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:recipe_app/shared/utils/android_saf_helper.dart';
import '../../../ai_transcoder/presentation/providers/ai_providers.dart';
import '../../../ai_transcoder/data/repositories/lm_studio_repository.dart';
import '../../../recipes/data/repositories/smb_recipe_repository.dart';
import '../../../recipes/presentation/providers/recipe_providers.dart';

import '../../../../features/voice/widgets/voice_commands_guide.dart';
import '../../../../shared/widgets/sound_preview_button.dart';
import '../../../timer/presentation/providers/timer_providers.dart';
import '../providers/settings_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _presetController;
  late final TextEditingController _smbHostController;
  late final TextEditingController _smbShareController;
  late final TextEditingController _smbUserController;
  late final TextEditingController _smbPasswordController;
  late final TextEditingController _smbDomainController;
  late final TextEditingController _smbPathController;
  bool _testing = false;
  bool _smbTesting = false;
  String _smbStatus = '';
  bool _modelLoaded = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _urlController = TextEditingController(text: s.lmStudioUrl);
    _presetController = TextEditingController(text: s.lmPreset ?? '');
    _smbHostController = TextEditingController(text: s.smbHost);
    _smbShareController = TextEditingController(text: s.smbShare);
    _smbUserController = TextEditingController(text: s.smbUser);
    _smbPasswordController = TextEditingController(text: s.smbPassword);
    _smbDomainController = TextEditingController(text: s.smbDomain);
    _smbPathController = TextEditingController(text: s.smbPath);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _presetController.dispose();
    _smbHostController.dispose();
    _smbShareController.dispose();
    _smbUserController.dispose();
    _smbPasswordController.dispose();
    _smbDomainController.dispose();
    _smbPathController.dispose();
    super.dispose();
  }

  Future<void> _testConnection(String url) async {
    setState(() => _testing = true);
    try {
      final repo = LmStudioRepository(url);
      final result = await repo.testConnection();
      if (!mounted) return;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected — ${result.modelCount} model(s) found in ${result.elapsed.inMilliseconds}ms')),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Connection Failed'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _resultRow('URL', result.url),
                  _resultRow('Status', '${result.statusCode ?? '-'}'),
                  _resultRow('Response time', '${result.elapsed.inMilliseconds}ms'),
                  if (result.error != null) ...[
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 4),
                    Text('Error:', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 4),
                    SelectableText(
                      result.error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Future<void> _testSmbConnection() async {
    final s = ref.read(settingsProvider);
    if (s.smbHost.isEmpty || s.smbShare.isEmpty) {
      setState(() => _smbStatus = 'Enter host and share name first');
      return;
    }
    setState(() {
      _smbTesting = true;
      _smbStatus = '';
    });
    SmbRecipeRepository? repo;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        final uncPath = '\\\\${s.smbHost}\\${s.smbShare}';
        final userPart = s.smbDomain.isNotEmpty
            ? '${s.smbDomain}\\${s.smbUser}'
            : s.smbUser;
        final result = await Process.run('net', [
          'use', uncPath,
          '/user:$userPart',
          s.smbPassword,
        ]);
        if (result.exitCode == 0) {
          ref.read(smbConnectRequestProvider.notifier).state++;
          setState(() => _smbStatus = 'OK — connected via UNC');
          return;
        }
        final netErr = (result.stderr as String?)?.trim() ?? 'exit ${result.exitCode}';
        setState(() => _smbStatus = 'net use failed ($netErr), trying smb_connect...');
      } else if (kIsWeb) {
        setState(() => _smbStatus = 'SMB not supported on web');
        return;
      }
      repo = SmbRecipeRepository(
        host: s.smbHost,
        domain: s.smbDomain,
        username: s.smbUser,
        password: s.smbPassword,
        share: s.smbShare,
        subPath: s.smbPath,
      );
      await repo.connect(debugPrint: true);
      final diag = await repo.diagnostics();
      setState(() => _smbStatus = diag);
      ref.read(smbConnectRequestProvider.notifier).state++;
    } catch (e) {
      setState(() => _smbStatus = 'Connection failed: $e');
    } finally {
      if (mounted) setState(() => _smbTesting = false);
      try {
        await repo?.dispose();
      } catch (_) {}
    }
  }

  void _showCommandsGuide(BuildContext context) {
    showVoiceCommandsGuide(context);
  }

  void _showManualPathDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recipe Directory Path'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the absolute path to your recipe folder:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '/path/to/recipes',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                ref.read(settingsProvider.notifier).updateDirectory(path);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Set Path'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final modelsAsync = ref.watch(availableModelsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.folder, size: 20,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Recipe Directory',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
                ListTile(
                  title: Text(settings.recipeDirectory.isEmpty
                      ? 'Not set'
                      : settings.recipeDirectory),
                  subtitle: Text(settings.smbEnabled && settings.recipeDirectory.isNotEmpty
                      ? 'SMB share — recipes stored on network'
                      : 'Folder containing recipe .md files'),
                  leading: const Icon(Icons.folder_outlined),
                  trailing: const Icon(Icons.edit),
                  onTap: () async {
                    if (settings.smbEnabled &&
                        settings.smbHost.isNotEmpty &&
                        settings.smbShare.isNotEmpty) {
                      final unc = '\\\\${settings.smbHost}\\${settings.smbShare}';
                      await ref.read(settingsProvider.notifier).updateDirectory(unc);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Directory set to SMB share: $unc'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    if (kIsWeb) {
                      _showManualPathDialog();
                      return;
                    }

                    final result = await FilePicker.platform.getDirectoryPath();
                    if (result == null) return;

                    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android &&
                        result.startsWith('content://')) {
                      await AndroidSafHelper.takePersistablePermission(result);
                      await AndroidSafHelper.listFiles(result);
                    }

                    await ref.read(settingsProvider.notifier).updateDirectory(result);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.cloud, size: 20,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Network Share',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: const Text('Use network share'),
                  subtitle: const Text('Access recipes via SMB/CIFS'),
                  value: settings.smbEnabled,
                  onChanged: (_) async {
                    await ref.read(settingsProvider.notifier).toggleSmb();
                    ref.invalidate(recipeRepositoryProvider);
                  },
                  secondary: const Icon(Icons.folder_shared),
                ),
                if (settings.smbEnabled) ...[
                  ListTile(
                    title: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        hintText: '192.168.1.100',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: _smbHostController,
                      onChanged: (v) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .updateSmbHost(v);
                      },
                    ),
                    subtitle: const Text('Server IP or hostname'),
                  ),
                  ListTile(
                    title: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Share Name',
                        hintText: 'recipes',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: _smbShareController,
                      onChanged: (v) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .updateSmbShare(v);
                      },
                    ),
                    subtitle: const Text('SMB share containing recipe folders'),
                  ),
                  ListTile(
                    title: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: _smbUserController,
                      onChanged: (v) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .updateSmbUser(v);
                      },
                    ),
                  ),
                  ListTile(
                    title: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: _smbPasswordController,
                      obscureText: true,
                      onChanged: (v) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .updateSmbPassword(v);
                      },
                    ),
                  ),
                  ListTile(
                    title: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Domain (optional)',
                        hintText: 'WORKGROUP',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: _smbDomainController,
                      onChanged: (v) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .updateSmbDomain(v);
                      },
                    ),
                  ),
                  ListTile(
                    title: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Path (optional)',
                        hintText: 'Recipes/Subfolder',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: _smbPathController,
                      onChanged: (v) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .updateSmbPath(v);
                      },
                    ),
                    subtitle: const Text('Sub-path within the share'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _smbTesting ? null : () => _testSmbConnection(),
                            icon: _smbTesting
                                ? const SizedBox(
                                    width: 16, height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.wifi_find, size: 18),
                            label: Text(_smbTesting ? 'Connecting...' : 'Connect'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_smbStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            _smbStatus.startsWith('OK')
                                ? Icons.check_circle
                                : Icons.error,
                            size: 16,
                            color: _smbStatus.startsWith('OK')
                                ? Colors.green
                                : theme.colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _smbStatus,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 1),
                  _SmbDiscoverySection(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.model_training, size: 20,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('AI Transcode',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: const Text('Enable AI features'),
                  subtitle: const Text('Format recipes with local LLM via LM Studio'),
                  value: settings.aiEnabled,
                  onChanged: (_) async {
                    await ref.read(settingsProvider.notifier).toggleAiEnabled();
                  },
                  secondary: const Icon(Icons.auto_awesome),
                ),
                if (settings.aiEnabled) ...[
                ListTile(
                  title: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    controller: _urlController,
                    onChanged: (v) async {
                      setState(() => _modelLoaded = false);
                      await ref
                          .read(settingsProvider.notifier)
                          .updateLmStudioUrl(v);
                    },
                  ),
                  subtitle: const Text('Default: http://localhost:1234'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _testing ? null : () => _testConnection(settings.lmStudioUrl),
                          icon: _testing
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_find, size: 18),
                          label: Text(_testing ? 'Testing...' : 'Test Connection'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh model list',
                        onPressed: () => ref.invalidate(availableModelsProvider),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.memory),
                  title: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: modelsAsync.when(
                      data: (models) => models.isEmpty
                          ? Text('No models found',
                              style: theme.textTheme.bodySmall)
                          : DropdownButton<String>(
                              value: settings.selectedModel,
                              isExpanded: true,
                              hint: const Text('Select model'),
                              underline: const SizedBox(),
                              items: models
                                  .map((m) => DropdownMenuItem(
                                        value: m.id,
                                        child: Text(m.name,
                                            overflow:
                                                TextOverflow.ellipsis),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                _modelLoaded = false;
                                ref
                                    .read(settingsProvider.notifier)
                                    .setSelectedModel(v);
                              },
                            ),
                      loading: () => const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2)),
                      error: (e, _) => IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () =>
                            ref.invalidate(availableModelsProvider),
                      ),
                    ),
                  ),
                  subtitle: const Text('AI model for formatting'),
                ),
                ListTile(
                  title: TextField(
                    decoration: const InputDecoration(
                      labelText: 'LM Studio Preset Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: 'e.g. MyPreset',
                    ),
                    controller: _presetController,
                    onChanged: (v) async {
                      await ref
                          .read(settingsProvider.notifier)
                          .setLmPreset(v.isEmpty ? null : v);
                    },
                  ),
                  subtitle: const Text('Optional: load model with saved preset'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: (_modelLoaded || settings.selectedModel == null)
                          ? null
                          : () async {
                              final modelId = settings.selectedModel!;
                              final repo = LmStudioRepository(settings.lmStudioUrl);
                              final ok = await repo.loadModel(
                                modelId,
                                preset: settings.lmPreset,
                              );
                              if (ok) setState(() => _modelLoaded = true);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(ok
                                      ? 'Model loaded'
                                      : 'Load failed — check server at ${settings.lmStudioUrl}')),
                                );
                              }
                            },
                      icon: const Icon(Icons.download),
                      label: const Text('Load Model'),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Refresh model list'),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ref.invalidate(availableModelsProvider),
                  ),
                ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.tune, size: 20,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Preferences',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: const Text('Keep screen on'),
                  subtitle:
                      const Text('Prevent screen from sleeping while reading'),
                  value: settings.keepScreenOn,
                  onChanged: (_) async {
                    await ref
                        .read(settingsProvider.notifier)
                        .toggleKeepScreenOn();
                  },
                  secondary: const Icon(Icons.screen_lock_portrait),
                ),
                SwitchListTile(
                  title: const Text('Dark mode'),
                  value: settings.darkMode,
                  onChanged: (_) async {
                    await ref
                        .read(settingsProvider.notifier)
                        .toggleDarkMode();
                  },
                  secondary: const Icon(Icons.dark_mode),
                ),
                ListTile(
                  title: const Text('Default alarm sound'),
                  subtitle: Text(soundDisplayName(settings.defaultTimerSound)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SoundPreviewButton(soundFile: settings.defaultTimerSound),
                      DropdownButton<String>(
                        value: settings.defaultTimerSound,
                        items: kTimerSounds.map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(soundDisplayName(s)),
                        )).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            ref.read(settingsProvider.notifier).updateDefaultTimerSound(v);
                          }
                        },
                      ),
                    ],
                  ),
                  leading: const Icon(Icons.music_note_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Icon(Icons.mic, size: 20,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Voice Navigation',
                              style: theme.textTheme.titleMedium),
                        ],
                      ),
                    ),
                SwitchListTile(
                  title: const Text('Enable voice navigation'),
                  subtitle: const Text(
                    'Control the app with spoken commands. Say "hey recipe" followed by your command. All processing happens on-device.',
                  ),
                  value: settings.voiceEnabled,
                  onChanged: (_) async {
                    await ref.read(settingsProvider.notifier).toggleVoiceEnabled();
                  },
                  secondary: const Icon(Icons.mic_outlined),
                ),
                if (settings.voiceEnabled) ...[
                  SwitchListTile(
                    title: const Text('Require "hey recipe" prefix'),
                    subtitle: const Text(
                      'Reduce false triggers by requiring the wake phrase before every command.',
                    ),
                    value: settings.voiceRequireWakePrefix,
                    onChanged: (_) async {
                      await ref.read(settingsProvider.notifier).toggleVoiceRequireWakePrefix();
                    },
                    secondary: const Icon(Icons.warning_amber_outlined),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _showCommandsGuide(context),
                        icon: const Icon(Icons.help_outline, size: 18),
                        label: const Text('View Commands'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmbDiscoverySection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SmbDiscoverySection> createState() => _SmbDiscoverySectionState();
}

class _SmbDiscoverySectionState extends ConsumerState<_SmbDiscoverySection> {
  SmbDiscoveryNotifier? _discoveryNotifier;

  @override
  void initState() {
    super.initState();
    _discoveryNotifier = ref.read(smbDiscoveryProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _discoveryNotifier?.startScan();
    });
  }

  @override
  void dispose() {
    _discoveryNotifier = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smbDiscoveryProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                state.isScanning ? Icons.wifi : Icons.wifi_off,
                size: 16,
                color: state.isScanning
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                state.isScanning ? 'Scanning network...' : 'Network scan',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: state.isScanning
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (state.isScanning) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              state.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (state.servers.isEmpty && !state.isScanning && state.error == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'No servers found. Try Test Connection with a known host.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ...state.servers.map((server) => ListTile(
              dense: true,
              leading: Icon(Icons.dns, size: 20, color: theme.colorScheme.primary),
              title: Text(server.name, style: theme.textTheme.bodyMedium),
              subtitle: Text('${server.host}:${server.port}',
                  style: theme.textTheme.bodySmall),
              trailing: Icon(Icons.add_circle_outline, size: 18,
                  color: theme.colorScheme.primary),
              onTap: () {
                ref.read(settingsProvider.notifier).updateSmbHost(server.host);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Host set to ${server.host}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            )),
      ],
    );
  }
}
