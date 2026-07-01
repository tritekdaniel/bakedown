class AppSettings {
  final String recipeDirectory;
  final String lmStudioUrl;
  final bool keepScreenOn;
  final bool darkMode;
  final String? selectedModel;
  final String? lmPreset;
  final bool smbEnabled;
  final String smbHost;
  final String smbShare;
  final String smbUser;
  final String smbPassword;
  final String smbDomain;
  final String smbPath;
  final bool voiceEnabled;
  final bool voiceRequireWakePrefix;
  final String defaultTimerSound;
  final bool aiEnabled;
  final bool isLoaded;

  const AppSettings({
    this.recipeDirectory = '',
    this.lmStudioUrl = 'http://localhost:1234',
    this.keepScreenOn = false,
    this.darkMode = false,
    this.selectedModel,
    this.lmPreset,
    this.smbEnabled = false,
    this.smbHost = '',
    this.smbShare = '',
    this.smbUser = '',
    this.smbPassword = '',
    this.smbDomain = '',
    this.smbPath = '',
    this.voiceEnabled = false,
    this.voiceRequireWakePrefix = false,
    this.defaultTimerSound = 'audio/Helium.mp3',
    this.aiEnabled = true,
    this.isLoaded = false,
  });

  AppSettings copyWith({
    String? recipeDirectory,
    String? lmStudioUrl,
    bool? keepScreenOn,
    bool? darkMode,
    String? selectedModel,
    String? lmPreset,
    bool? smbEnabled,
    String? smbHost,
    String? smbShare,
    String? smbUser,
    String? smbPassword,
    String? smbDomain,
    String? smbPath,
    bool? voiceEnabled,
    bool? voiceRequireWakePrefix,
    String? defaultTimerSound,
    bool? aiEnabled,
    bool? isLoaded,
  }) {
    return AppSettings(
      recipeDirectory: recipeDirectory ?? this.recipeDirectory,
      lmStudioUrl: lmStudioUrl ?? this.lmStudioUrl,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      darkMode: darkMode ?? this.darkMode,
      selectedModel: selectedModel ?? this.selectedModel,
      lmPreset: lmPreset ?? this.lmPreset,
      smbEnabled: smbEnabled ?? this.smbEnabled,
      smbHost: smbHost ?? this.smbHost,
      smbShare: smbShare ?? this.smbShare,
      smbUser: smbUser ?? this.smbUser,
      smbPassword: smbPassword ?? this.smbPassword,
      smbDomain: smbDomain ?? this.smbDomain,
      smbPath: smbPath ?? this.smbPath,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      voiceRequireWakePrefix: voiceRequireWakePrefix ?? this.voiceRequireWakePrefix,
      defaultTimerSound: defaultTimerSound ?? this.defaultTimerSound,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}
