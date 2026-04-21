enum GameLaunchMode {
  newSession,
  resume,
}

extension GameLaunchModeX on GameLaunchMode {
  String get value {
    switch (this) {
      case GameLaunchMode.newSession:
        return 'new';
      case GameLaunchMode.resume:
        return 'resume';
    }
  }
}

class GameLaunchContract {
  final String packagePath;
  final String sessionId;
  final String outputDir;
  final GameLaunchMode mode;
  final String? entryFile;
  final Map<String, dynamic>? gamePayload;

  const GameLaunchContract({
    required this.packagePath,
    required this.sessionId,
    required this.outputDir,
    required this.mode,
    this.entryFile,
    this.gamePayload,
  });

  Map<String, dynamic> toJson() => {
    'packagePath': packagePath,
    'sessionId': sessionId,
    'outputDir': outputDir,
    'mode': mode.value,
    if (entryFile != null && entryFile!.isNotEmpty) 'entryFile': entryFile,
    if (gamePayload != null) 'gamePayload': gamePayload,
  };
}
