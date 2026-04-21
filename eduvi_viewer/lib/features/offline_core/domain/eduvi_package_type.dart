enum EduviPackageType {
  slide,
  game,
}

extension EduviPackageTypeX on EduviPackageType {
  String get value {
    switch (this) {
      case EduviPackageType.slide:
        return 'slide';
      case EduviPackageType.game:
        return 'game';
    }
  }
}

EduviPackageType eduviPackageTypeFromString(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'game':
      return EduviPackageType.game;
    case 'slide':
    default:
      return EduviPackageType.slide;
  }
}
