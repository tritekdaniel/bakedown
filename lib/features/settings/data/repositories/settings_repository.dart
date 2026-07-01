import 'package:shared_preferences/shared_preferences.dart';
import 'package:recipe_app/core/constants/app_constants.dart';
import '../../domain/models/app_settings.dart';

class SettingsRepository {
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      recipeDirectory: prefs.getString(AppConstants.settingsKeyDirectory) ?? '',
      lmStudioUrl: prefs.getString(AppConstants.settingsKeyLmUrl) ??
          AppConstants.defaultLmStudioUrl,
      keepScreenOn: prefs.getBool(AppConstants.settingsKeyKeepScreenOn) ?? false,
      darkMode: prefs.getBool(AppConstants.settingsKeyDarkMode) ?? false,
      selectedModel: prefs.getString(AppConstants.settingsKeySelectedModel),
      lmPreset: prefs.getString(AppConstants.settingsKeyLmPreset),
      smbEnabled: prefs.getBool(AppConstants.settingsKeySmbEnabled) ?? false,
      smbHost: prefs.getString(AppConstants.settingsKeySmbHost) ?? '',
      smbShare: prefs.getString(AppConstants.settingsKeySmbShare) ?? '',
      smbUser: prefs.getString(AppConstants.settingsKeySmbUser) ?? '',
      smbPassword: prefs.getString(AppConstants.settingsKeySmbPassword) ?? '',
      smbDomain: prefs.getString(AppConstants.settingsKeySmbDomain) ?? '',
      smbPath: prefs.getString(AppConstants.settingsKeySmbPath) ?? '',
      voiceEnabled: prefs.getBool(AppConstants.settingsKeyVoiceEnabled) ?? false,
      voiceRequireWakePrefix: prefs.getBool(AppConstants.settingsKeyVoiceRequireWake) ?? false,
      defaultTimerSound: prefs.getString(AppConstants.settingsKeyDefaultTimerSound) ?? 'audio/Helium.mp3',
      aiEnabled: prefs.getBool(AppConstants.settingsKeyAiEnabled) ?? true,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        AppConstants.settingsKeyDirectory, settings.recipeDirectory);
    await prefs.setString(
        AppConstants.settingsKeyLmUrl, settings.lmStudioUrl);
    await prefs.setBool(
        AppConstants.settingsKeyKeepScreenOn, settings.keepScreenOn);
    await prefs.setBool(
        AppConstants.settingsKeyDarkMode, settings.darkMode);
    if (settings.selectedModel != null) {
      await prefs.setString(
          AppConstants.settingsKeySelectedModel, settings.selectedModel!);
    }
    if (settings.lmPreset != null) {
      await prefs.setString(
          AppConstants.settingsKeyLmPreset, settings.lmPreset!);
    }
    await prefs.setBool(
        AppConstants.settingsKeySmbEnabled, settings.smbEnabled);
    await prefs.setString(
        AppConstants.settingsKeySmbHost, settings.smbHost);
    await prefs.setString(
        AppConstants.settingsKeySmbShare, settings.smbShare);
    await prefs.setString(
        AppConstants.settingsKeySmbUser, settings.smbUser);
    await prefs.setString(
        AppConstants.settingsKeySmbPassword, settings.smbPassword);
    await prefs.setString(
        AppConstants.settingsKeySmbDomain, settings.smbDomain);
    await prefs.setString(
        AppConstants.settingsKeySmbPath, settings.smbPath);
    await prefs.setBool(
        AppConstants.settingsKeyVoiceEnabled, settings.voiceEnabled);
    await prefs.setBool(
        AppConstants.settingsKeyVoiceRequireWake, settings.voiceRequireWakePrefix);
    await prefs.setString(
        AppConstants.settingsKeyDefaultTimerSound, settings.defaultTimerSound);
    await prefs.setBool(
        AppConstants.settingsKeyAiEnabled, settings.aiEnabled);
  }

  Future<void> saveDirectory(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.settingsKeyDirectory, path);
  }
}
