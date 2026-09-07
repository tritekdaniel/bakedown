import 'dart:io' if (dart.library.html) 'package:recipe_app/shared/stubs/io_stub.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:recipe_app/shared/utils/android_saf_helper.dart';
import 'package:recipe_app/shared/utils/web_fs_helper.dart';
import 'package:recipe_app/shared/widgets/file_browser.dart';
import '../../../ai_transcoder/presentation/providers/ai_providers.dart';
import '../../../ai_transcoder/data/repositories/lm_studio_repository.dart';
import '../../../recipes/data/repositories/http_recipe_repository.dart';
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
  late final TextEditingController _httpBridgeController;
  bool _testing = false;
  bool _httpTesting = false;
  String _httpStatus = '';
  bool _modelLoaded = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _urlController = TextEditingController(text: s.lmStudioUrl);
    _presetController = TextEditingController(text: s.lmPreset ?? '');
    _httpBridgeController = TextEditingController(text: s.httpBridgeUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _presetController.dispose();
    _httpBridgeController.dispose();
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

  Future<void> _testHttpBridge() async {
    final url = _httpBridgeController.text.trim();
    if (url.isEmpty) {
      setState(() => _httpStatus = 'Enter bridge URL first');
      return;
    }
    setState(() {
      _httpTesting = true;
      _httpStatus = '';
    });
    try {
      final repo = HttpRecipeRepository(url);
      final ok = await repo.testConnection();
      if (!mounted) return;
      if (ok) {
        final folders = await repo.listFolders();
        setState(() => _httpStatus = 'OK — ${folders.length} folder(s) found');
        ref.read(smbConnectRequestProvider.notifier).state++;
        if (ref.read(settingsProvider).httpBridgeEnabled == false) {
          await ref.read(settingsProvider.notifier).toggleHttpBridge();
        }
        await ref.read(settingsProvider.notifier).updateHttpBridgeUrl(url);
      } else {
        setState(() => _httpStatus = 'No response — check URL, bridge must allow CORS and be running');
      }
    } catch (e) {
      if (mounted) setState(() => _httpStatus = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _httpTesting = false);
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

  Future<void> _pickRecipeFolder() async {
    if (kIsWeb) {
      if (!isSecureContext) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Blocked: $currentOrigin is not secure. Use ${localhostAlternative} on this Ubuntu machine or serve with HTTPS.')),
        );
        return;
      }
      final handle = await WebFsHelper.pickDirectory();
      if (handle != null) {
        ref.read(webUseBrowserStorageProvider.notifier).state = false;
        ref.read(webFsHandleRevisionProvider.notifier).state++;
        ref.invalidate(recipeRepositoryProvider);
        ref.invalidate(foldersProvider);
        await ref.read(settingsProvider.notifier).updateDirectory(WebFsHelper.rootName ?? 'web-fs');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Using folder: ${WebFsHelper.rootName}')),
          );
        }
        return;
      }
      if (isFileSystemAccessSupported) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No folder selected or browser denied access')),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File System Access not available — using browser storage. Try Chrome/Edge on localhost.')),
      );
      _showManualPathDialog();
      return;
    }
    final initial = ref.read(settingsProvider).recipeDirectory;
    final isContentUri = initial.startsWith('content://');
    String? result;
    try {
      result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Recipe Folder',
        initialDirectory: initial.isEmpty || isContentUri ? null : initial,
        lockParentWindow: true,
      );
    } catch (e) {
      debugPrint('[PICKER] FilePicker failed: $e — falling back to in-app browser');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('System picker failed ($e) — trying in-app browser')),
      );
      final fallback = await showFolderBrowser(context, initialPath: initial);
      if (fallback == null || fallback == '__native__') return;
      result = fallback;
    }
    if (result == null) {
      if (defaultTargetPlatform == TargetPlatform.linux) {
        if (!mounted) return;
        final tryInApp = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('System picker unavailable'),
            content: const Text('Install zenity (sudo apt install zenity) or use in-app browser.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open In-App Browser')),
            ],
          ),
        );
        if (tryInApp == true) {
          final fallback = await showFolderBrowser(context, initialPath: initial);
          if (fallback == null || fallback == '__native__') return;
          result = fallback;
        } else {
          return;
        }
      } else {
        return;
      }
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && result.startsWith('content://')) {
      await AndroidSafHelper.takePersistablePermission(result);
      await AndroidSafHelper.listFiles(result);
    }
    await ref.read(settingsProvider.notifier).updateDirectory(result);
  }

  Future<void> _resetAllSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all settings?'),
        content: const Text('Clears folder, network share, bridge and AI settings. Fixes frozen launch due to bad config.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(settingsProvider.notifier).resetAll();
    ref.invalidate(recipeRepositoryProvider);
    ref.invalidate(foldersProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings reset')));
      context.go('/');
    }
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
                  subtitle: const Text('Tap to browse • long-press for manual path'),
                  leading: const Icon(Icons.folder_outlined),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.folder_open),
                        tooltip: 'Browse folders',
                        onPressed: _pickRecipeFolder,
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                  onTap: _pickRecipeFolder,
                  onLongPress: _showManualPathDialog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (kIsWeb)
            Card(
              child: ListTile(
                leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
                title: const Text('Network Share on Web'),
                subtitle: const Text('Pick a local folder or \\\\server\\share via the OS picker (Chrome/Edge on localhost/HTTPS). Otherwise recipes use browser storage.'),
              ),
            )
          else
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
                ListTile(
                  leading: const Icon(Icons.folder_shared),
                  title: const Text('Network share'),
                  subtitle: const Text('Pick via OS file picker: choose a local folder or \\\\server\\share directly. No manual host/share needed.'),
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
                      Icon(Icons.http, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('HTTP Bridge', style: theme.textTheme.titleMedium),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: kIsWeb ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(kIsWeb ? 'Web' : 'Optional', style: theme.textTheme.labelSmall?.copyWith(color: kIsWeb ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: const Text('Use HTTP Bridge'),
                  subtitle: Text(kIsWeb
                      ? 'Required for web — browser cannot use SMB directly. Run bridge on your NAS/PC and enter its URL.'
                      : 'Alternative to SMB/CIFS — works on all platforms including web via bridge.'),
                  value: settings.httpBridgeEnabled,
                  onChanged: (_) async {
                    await ref.read(settingsProvider.notifier).toggleHttpBridge();
                    ref.invalidate(recipeRepositoryProvider);
                  },
                  secondary: const Icon(Icons.language),
                ),
                if (settings.httpBridgeEnabled) ...[
                  ListTile(
                    title: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Bridge URL',
                        hintText: 'http://192.168.1.100:8787',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: _httpBridgeController,
                      keyboardType: TextInputType.url,
                      onChanged: (v) async {
                        await ref.read(settingsProvider.notifier).updateHttpBridgeUrl(v);
                      },
                    ),
                    subtitle: const Text('Bridge exposes recipe folders via HTTP. See bridge/README.'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _httpTesting ? null : () => _testHttpBridge(),
                            icon: _httpTesting
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.wifi_find, size: 18),
                            label: Text(_httpTesting ? 'Testing...' : 'Test Bridge'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_httpStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Icon(_httpStatus.startsWith('OK') ? Icons.check_circle : Icons.error, size: 16, color: _httpStatus.startsWith('OK') ? Colors.green : theme.colorScheme.error),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_httpStatus, style: theme.textTheme.bodySmall)),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary), const SizedBox(width: 6), Text('How to run bridge', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600))]),
                        const SizedBox(height: 6),
                        Text('Web browsers block raw SMB (TCP 445). Run the companion bridge on the machine hosting your recipes:', style: theme.textTheme.bodySmall),
                        const SizedBox(height: 6),
                        SelectableText('  python bridge/server.py --dir /path/to/recipes --port 8787\n  # or: dart run bridge/server.dart', style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 11)),
                        const SizedBox(height: 6),
                        Text('Then set Bridge URL above. Bridge handles SMB/network discovery server-side and serves recipes over HTTP with CORS.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ]),
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
                              value: models.any((m) => m.id == settings.selectedModel)
                                  ? settings.selectedModel
                                  : null,
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
                      Icon(Icons.bug_report_outlined, size: 20, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Text('Troubleshooting', style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('Reset all settings'),
                  subtitle: const Text('Fix frozen launch due to bad config'),
                  trailing: OutlinedButton(onPressed: _resetAllSettings, child: const Text('Reset')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (kIsWeb)
            Card(
              child: ListTile(
                leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
                title: const Text('Voice Navigation not available on web'),
                subtitle: const Text('On-device wake-word requires native build. Use Android/Windows.'),
              ),
            )
          else
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
