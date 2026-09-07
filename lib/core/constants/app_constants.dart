class AppConstants {
  static const String appTitle = 'Bakedown';
  static const String defaultLmStudioUrl = 'http://localhost:1234';
  static const String settingsKeyDirectory = 'recipe_directory';
  static const String settingsKeyLmUrl = 'lm_studio_url';
  static const String settingsKeyKeepScreenOn = 'keep_screen_on';
  static const String settingsKeyDarkMode = 'dark_mode';
  static const String settingsKeySelectedModel = 'selected_model';
  static const String settingsKeyLmPreset = 'lm_preset';
  static const String settingsKeySmbEnabled = 'smb_enabled';
  static const String settingsKeySmbHost = 'smb_host';
  static const String settingsKeySmbShare = 'smb_share';
  static const String settingsKeySmbUser = 'smb_user';
  static const String settingsKeySmbPassword = 'smb_password';
  static const String settingsKeySmbDomain = 'smb_domain';
  static const String settingsKeySmbPath = 'smb_path';
  static const String settingsKeyHttpBridgeEnabled = 'http_bridge_enabled';
  static const String settingsKeyHttpBridgeUrl = 'http_bridge_url';
  static const String settingsKeyVoiceEnabled = 'voice_enabled';
  static const String settingsKeyVoiceRequireWake = 'voice_require_wake';
  static const String settingsKeyVoicePauseFor = 'voice_pause_for';
  static const String settingsKeyDefaultTimerSound = 'default_timer_sound';
  static const String settingsKeyAiEnabled = 'ai_enabled';

  static String normalizeUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return defaultLmStudioUrl;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}
