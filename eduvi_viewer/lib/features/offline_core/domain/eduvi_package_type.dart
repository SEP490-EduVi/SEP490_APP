enum EduviPackageType {
  slide,
  video,
  game,
}

extension EduviPackageTypeX on EduviPackageType {
  String get value {
    switch (this) {
      case EduviPackageType.slide:
        return 'slide';
      case EduviPackageType.video:
        return 'video';
      case EduviPackageType.game:
        return 'game';
    }
  }
}

EduviPackageType eduviPackageTypeFromString(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'game':
      return EduviPackageType.game;
    case 'video':
      return EduviPackageType.video;
    case 'slide':
    default:
      return EduviPackageType.slide;
  }
}
