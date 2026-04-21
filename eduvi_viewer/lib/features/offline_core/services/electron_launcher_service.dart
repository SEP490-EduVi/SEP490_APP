import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/launched_electron_process.dart';

abstract class ElectronProcessLauncher {
  Future<LaunchedElectronProcess> launch({
    required String contractPath,
    String? executablePath,
  });
}

class RealElectronProcessLauncher implements ElectronProcessLauncher {
  static const _appSettingKey = 'electron_executable_path';
  final String _workingDirectory;
  final Map<String, String> _environment;
  final String _resolvedExecutablePath;

  RealElectronProcessLauncher({
    String? workingDirectory,
    Map<String, String>? environment,
    String? resolvedExecutablePath,
  }) : _workingDirectory = workingDirectory ?? Directory.current.path,
       _environment = environment ?? Platform.environment,
       _resolvedExecutablePath = resolvedExecutablePath ?? Platform.resolvedExecutable;

  @override
  Future<LaunchedElectronProcess> launch({
    required String contractPath,
    String? executablePath,
  }) async {
    final command = await resolveLaunchCommand(executablePath: executablePath);

    final process = await Process.start(command.executablePath, [
      ...command.bootstrapArgs,
      '--launch-contract=$contractPath',
    ]);
    return LaunchedElectronProcess(pid: process.pid, exitCode: process.exitCode);
  }

  Future<ResolvedElectronLaunchCommand> resolveLaunchCommand({
    String? executablePath,
  }) async {
    if (executablePath != null && executablePath.trim().isNotEmpty) {
      final direct = ResolvedElectronLaunchCommand(
        executablePath: executablePath,
      );
      if (await File(direct.executablePath).exists()) {
        return direct;
      }
      throw FileSystemException(
        'Không tìm thấy Electron runtime executable',
        direct.executablePath,
      );
    }

    final envValue = _environment['EDUVI_ELECTRON_EXE'];
    if (envValue != null && envValue.trim().isNotEmpty) {
      final envCommand = ResolvedElectronLaunchCommand(executablePath: envValue);
      if (await File(envCommand.executablePath).exists()) {
        return envCommand;
      }
    }

    final candidates = _candidateCommands();
    for (final candidate in candidates) {
      if (await File(candidate.executablePath).exists()) {
        return candidate;
      }
    }

    final searched = candidates
        .map((candidate) => candidate.executablePath)
        .toList()
        .join(' | ');
    throw FileSystemException(
      'Không tìm thấy Electron runtime executable. Da thu cac duong dan: $searched',
      candidates.first.executablePath,
    );
  }

  List<ResolvedElectronLaunchCommand> _candidateCommands() {
    final appRuntimeDir = p.join(_workingDirectory, 'apps', 'electron_game_runtime');
    final runningExeDir = File(_resolvedExecutablePath).parent.path;

    final commands = <ResolvedElectronLaunchCommand>[
      ResolvedElectronLaunchCommand(
        executablePath: p.join(runningExeDir, 'game-runtime-v2', 'EduVi Game.exe'),
      ),
      ResolvedElectronLaunchCommand(
        executablePath: p.join(
          runningExeDir,
          'game-runtime-v2',
          'win-unpacked',
          'EduVi Game.exe',
        ),
      ),
      ResolvedElectronLaunchCommand(
        executablePath: p.join(runningExeDir, 'game-runtime', 'EduVi Game.exe'),
      ),
      ResolvedElectronLaunchCommand(
        executablePath: p.join(
          runningExeDir,
          'game-runtime',
          'win-unpacked',
          'EduVi Game.exe',
        ),
      ),
      ResolvedElectronLaunchCommand(
        executablePath: p.join(runningExeDir, 'electron_runtime', 'eduvi-game-runtime.exe'),
      ),
      ResolvedElectronLaunchCommand(
        executablePath: p.join(
          _workingDirectory,
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
          'game-runtime-v2',
          'EduVi Game.exe',
        ),
      ),
      ResolvedElectronLaunchCommand(
        executablePath: p.join(
          _workingDirectory,
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
          'game-runtime-v2',
          'win-unpacked',
          'EduVi Game.exe',
        ),
      ),
      ResolvedElectronLaunchCommand(
        executablePath: p.join(
          _workingDirectory,
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
          'game-runtime',
          'EduVi Game.exe',
        ),
      ),
      ResolvedElectronLaunchCommand(
        executablePath: p.join(
          _workingDirectory,
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
          'game-runtime',
          'win-unpacked',
          'EduVi Game.exe',
        ),
      ),
      ResolvedElectronLaunchCommand(
        executablePath: p.join(
          _workingDirectory,
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
          'electron_runtime',
          'eduvi-game-runtime.exe',
        ),
      ),
      ResolvedElectronLaunchCommand(
        executablePath: p.join(appRuntimeDir, 'dist', 'eduvi-game-runtime.exe'),
      ),
      ResolvedElectronLaunchCommand(
        executablePath: p.join(
          appRuntimeDir,
          'dist',
          'eduvi-game-runtime-win32-x64',
          'eduvi-game-runtime.exe',
        ),
      ),
      ResolvedElectronLaunchCommand(
        executablePath: p.join(
          appRuntimeDir,
          'node_modules',
          'electron',
          'dist',
          'electron.exe',
        ),
        bootstrapArgs: [appRuntimeDir],
      ),
    ];

    final unique = <String>{};
    return commands.where((command) => unique.add(command.executablePath)).toList();
  }

  static String get appSettingKey => _appSettingKey;
}

class ResolvedElectronLaunchCommand {
  final String executablePath;
  final List<String> bootstrapArgs;

  const ResolvedElectronLaunchCommand({
    required this.executablePath,
    this.bootstrapArgs = const <String>[],
  });
}
