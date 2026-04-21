class VideoTrackState {
  final String trackId;
  final int positionMs;
  final bool paused;
  final String updatedAt;

  const VideoTrackState({
    required this.trackId,
    required this.positionMs,
    required this.paused,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'trackId': trackId,
    'positionMs': positionMs,
    'paused': paused,
    'updatedAt': updatedAt,
  };

  factory VideoTrackState.fromJson(Map<String, dynamic> json) {
    return VideoTrackState(
      trackId: json['trackId'] as String? ?? 'unknown',
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      paused: json['paused'] as bool? ?? false,
      updatedAt: json['updatedAt'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
}
