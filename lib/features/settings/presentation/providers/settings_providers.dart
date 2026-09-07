import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:recipe_app/core/constants/app_constants.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/http_discovery_repository.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/discovered_server.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsRepository _repo;

  SettingsNotifier(this._repo) : super(const AppSettings());

  Future<void> load() async {
    final settings = await _repo.load();
    state = settings.copyWith(isLoaded: true);
    if (kIsWeb) return;
    try {
      if (settings.keepScreenOn) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  Future<void> updateDirectory(String path) async {
    state = state.copyWith(recipeDirectory: path);
    await _repo.save(state);
  }

  Future<void> updateLmStudioUrl(String url) async {
    state = state.copyWith(lmStudioUrl: AppConstants.normalizeUrl(url));
    await _repo.save(state);
  }

  Future<void> toggleKeepScreenOn() async {
    final newVal = !state.keepScreenOn;
    state = state.copyWith(keepScreenOn: newVal);
    if (!kIsWeb) {
      try {
        if (newVal) {
          await WakelockPlus.enable();
        } else {
          await WakelockPlus.disable();
        }
      } catch (_) {}
    }
    await _repo.save(state);
  }

  Future<void> toggleDarkMode() async {
    state = state.copyWith(darkMode: !state.darkMode);
    await _repo.save(state);
  }

  Future<void> setSelectedModel(String? model) async {
    state = state.copyWith(selectedModel: model);
    await _repo.save(state);
  }

  Future<void> setLmPreset(String? preset) async {
    state = state.copyWith(lmPreset: preset);
    await _repo.save(state);
  }

  Future<void> toggleSmb() async {
    state = state.copyWith(smbEnabled: !state.smbEnabled);
    await _repo.save(state);
  }

  Future<void> updateSmbHost(String host) async {
    state = state.copyWith(smbHost: host);
    await _repo.save(state);
  }

  Future<void> updateSmbShare(String share) async {
    state = state.copyWith(smbShare: share);
    await _repo.save(state);
  }

  Future<void> updateSmbUser(String user) async {
    state = state.copyWith(smbUser: user);
    await _repo.save(state);
  }

  Future<void> updateSmbPassword(String password) async {
    state = state.copyWith(smbPassword: password);
    await _repo.save(state);
  }

  Future<void> updateSmbDomain(String domain) async {
    state = state.copyWith(smbDomain: domain);
    await _repo.save(state);
  }

  Future<void> updateSmbPath(String path) async {
    state = state.copyWith(smbPath: path);
    await _repo.save(state);
  }

  Future<void> toggleVoiceEnabled() async {
    state = state.copyWith(voiceEnabled: !state.voiceEnabled);
    await _repo.save(state);
  }

  Future<void> toggleVoiceRequireWakePrefix() async {
    state = state.copyWith(voiceRequireWakePrefix: !state.voiceRequireWakePrefix);
    await _repo.save(state);
  }

  Future<void> updateDefaultTimerSound(String soundFile) async {
    state = state.copyWith(defaultTimerSound: soundFile);
    await _repo.save(state);
  }

  Future<void> toggleAiEnabled() async {
    state = state.copyWith(aiEnabled: !state.aiEnabled);
    await _repo.save(state);
  }

  Future<void> toggleHttpBridge() async {
    state = state.copyWith(httpBridgeEnabled: !state.httpBridgeEnabled);
    await _repo.save(state);
  }

  Future<void> updateHttpBridgeUrl(String url) async {
    state = state.copyWith(httpBridgeUrl: AppConstants.normalizeUrl(url));
    await _repo.save(state);
  }

  Future<void> resetAll() async {
    await _repo.clearAll();
    state = const AppSettings(isLoaded: true);
    await _repo.save(state);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return SettingsNotifier(repo);
});

final settingsLoadedProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider.select((s) => s.isLoaded));
});

class SmbDiscoveryState {
  final bool isScanning;
  final List<DiscoveredServer> servers;
  final String? error;

  const SmbDiscoveryState({
    this.isScanning = false,
    this.servers = const [],
    this.error,
  });

  SmbDiscoveryState copyWith({
    bool? isScanning,
    List<DiscoveredServer>? servers,
    String? error,
  }) {
    return SmbDiscoveryState(
      isScanning: isScanning ?? this.isScanning,
      servers: servers ?? this.servers,
      error: error,
    );
  }
}

class SmbDiscoveryNotifier extends StateNotifier<SmbDiscoveryState> {
  final HttpDiscoveryRepository _httpRepo = HttpDiscoveryRepository();
  final Ref _ref;
  bool _disposed = false;

  SmbDiscoveryNotifier(this._ref) : super(const SmbDiscoveryState());

  Future<void> startScan() async {
    if (_disposed) return;
    state = state.copyWith(isScanning: true, error: null, servers: []);
    try {
      final settings = _ref.read(settingsProvider);
      final bridgeUrl = settings.httpBridgeUrl;
      if (bridgeUrl.isNotEmpty) {
        final servers = await _httpRepo.discoverViaBridge(bridgeUrl);
        if (servers.isNotEmpty) {
          if (_disposed) return;
          state = state.copyWith(isScanning: false, servers: servers);
          return;
        }
      }
      final bridges = await _httpRepo.scanCommonBridges();
      if (bridges.isNotEmpty) {
        if (_disposed) return;
        state = state.copyWith(isScanning: false, servers: bridges);
        return;
      }
      if (_disposed) return;
      if (kIsWeb) {
        state = state.copyWith(isScanning: false, error: 'No bridge found. Web already uses the shared host folder (~/Recipes) via node server/index.js — check the server is running.');
      } else {
        state = state.copyWith(isScanning: false, error: 'No bridge found. On desktop/mobile, just pick a folder (local or \\server\\share) via the OS file picker — no SMB config needed.');
      }
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isScanning: false, error: e.toString());
    }
  }

  Future<List<String>> browseSharesFor(String host) async => [];

  void stopScan() {}

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final smbDiscoveryProvider = StateNotifierProvider.autoDispose<
    SmbDiscoveryNotifier, SmbDiscoveryState>((ref) {
  return SmbDiscoveryNotifier(ref);
});
