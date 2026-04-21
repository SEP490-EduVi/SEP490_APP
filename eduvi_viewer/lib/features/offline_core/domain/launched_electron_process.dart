class LaunchedElectronProcess {
  final int pid;
  final Future<int> exitCode;

  const LaunchedElectronProcess({
    required this.pid,
    required this.exitCode,
  });
}
