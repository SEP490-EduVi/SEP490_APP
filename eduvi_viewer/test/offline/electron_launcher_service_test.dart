import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:eduvi_viewer/features/offline_core/services/electron_launcher_service.dart';

void main() {
  group('RealElectronProcessLauncher', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('electron_launcher_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolves executable from EDUVI_ELECTRON_EXE environment', () async {
      final exe = File('${tempDir.path}/runtime/custom-runtime.exe');
      await exe.parent.create(recursive: true);
      await exe.writeAsString('mock');

      final launcher = RealElectronProcessLauncher(
        workingDirectory: tempDir.path,
        environment: {'EDUVI_ELECTRON_EXE': exe.path},
      );

      final resolved = await launcher.resolveLaunchCommand();
      expect(p.normalize(resolved.executablePath), p.normalize(exe.path));
    });

    test('resolves packaged runtime executable in dist folder', () async {
      final exe = File(
        '${tempDir.path}/apps/electron_game_runtime/dist/eduvi-game-runtime-win32-x64/eduvi-game-runtime.exe',
      );
      await exe.parent.create(recursive: true);
      await exe.writeAsString('mock');

      final launcher = RealElectronProcessLauncher(
        workingDirectory: tempDir.path,
        environment: const <String, String>{},
      );

      final resolved = await launcher.resolveLaunchCommand();
      expect(p.normalize(resolved.executablePath), p.normalize(exe.path));
      expect(resolved.bootstrapArgs, isEmpty);
    });

    test('prefers packaged MediaPipe game-runtime executable', () async {
      final gameRuntimeExe = File(
        '${tempDir.path}/build/windows/x64/runner/Release/game-runtime/EduVi Game.exe',
      );
      await gameRuntimeExe.parent.create(recursive: true);
      await gameRuntimeExe.writeAsString('mock');

      final legacyRuntimeExe = File(
        '${tempDir.path}/build/windows/x64/runner/Release/electron_runtime/eduvi-game-runtime.exe',
      );
      await legacyRuntimeExe.parent.create(recursive: true);
      await legacyRuntimeExe.writeAsString('mock');

      final launcher = RealElectronProcessLauncher(
        workingDirectory: tempDir.path,
        environment: const <String, String>{},
      );

      final resolved = await launcher.resolveLaunchCommand();
      expect(
        p.normalize(resolved.executablePath),
        p.normalize(gameRuntimeExe.path),
      );
      expect(resolved.bootstrapArgs, isEmpty);
    });

    test('prefers game-runtime next to running executable', () async {
      final runningExe = File('${tempDir.path}/app/eduvi_viewer.exe');
      await runningExe.parent.create(recursive: true);
      await runningExe.writeAsString('mock');

      final gameRuntimeExe = File(
        '${tempDir.path}/app/game-runtime/EduVi Game.exe',
      );
      await gameRuntimeExe.parent.create(recursive: true);
      await gameRuntimeExe.writeAsString('mock');

      final legacyRuntimeExe = File(
        '${tempDir.path}/app/electron_runtime/eduvi-game-runtime.exe',
      );
      await legacyRuntimeExe.parent.create(recursive: true);
      await legacyRuntimeExe.writeAsString('mock');

      final launcher = RealElectronProcessLauncher(
        workingDirectory: '${tempDir.path}/no-build-here',
        environment: const <String, String>{},
        resolvedExecutablePath: runningExe.path,
      );

      final resolved = await launcher.resolveLaunchCommand();
      expect(p.normalize(resolved.executablePath), p.normalize(gameRuntimeExe.path));
      expect(resolved.bootstrapArgs, isEmpty);
    });

    test('prefers game-runtime-v2 next to running executable', () async {
      final runningExe = File('${tempDir.path}/app/eduvi_viewer.exe');
      await runningExe.parent.create(recursive: true);
      await runningExe.writeAsString('mock');

      final gameRuntimeV2Exe = File(
        '${tempDir.path}/app/game-runtime-v2/EduVi Game.exe',
      );
      await gameRuntimeV2Exe.parent.create(recursive: true);
      await gameRuntimeV2Exe.writeAsString('mock');

      final gameRuntimeExe = File(
        '${tempDir.path}/app/game-runtime/EduVi Game.exe',
      );
      await gameRuntimeExe.parent.create(recursive: true);
      await gameRuntimeExe.writeAsString('mock');

      final launcher = RealElectronProcessLauncher(
        workingDirectory: '${tempDir.path}/no-build-here',
        environment: const <String, String>{},
        resolvedExecutablePath: runningExe.path,
      );

      final resolved = await launcher.resolveLaunchCommand();
      expect(
        p.normalize(resolved.executablePath),
        p.normalize(gameRuntimeV2Exe.path),
      );
      expect(resolved.bootstrapArgs, isEmpty);
    });

    test('prefers side-by-side runtime over stale workspace build runtime', () async {
      final runningExe = File('${tempDir.path}/app/eduvi_viewer.exe');
      await runningExe.parent.create(recursive: true);
      await runningExe.writeAsString('mock');

      final sideBySideRuntime = File(
        '${tempDir.path}/app/game-runtime-v2/EduVi Game.exe',
      );
      await sideBySideRuntime.parent.create(recursive: true);
      await sideBySideRuntime.writeAsString('new-runtime');

      final staleBuildRuntime = File(
        '${tempDir.path}/workspace/build/windows/x64/runner/Release/game-runtime-v2/EduVi Game.exe',
      );
      await staleBuildRuntime.parent.create(recursive: true);
      await staleBuildRuntime.writeAsString('old-runtime');

      final launcher = RealElectronProcessLauncher(
        workingDirectory: '${tempDir.path}/workspace',
        environment: const <String, String>{},
        resolvedExecutablePath: runningExe.path,
      );

      final resolved = await launcher.resolveLaunchCommand();
      expect(
        p.normalize(resolved.executablePath),
        p.normalize(sideBySideRuntime.path),
      );
      expect(resolved.bootstrapArgs, isEmpty);
    });

    test('resolves side-by-side game-runtime-v2 win-unpacked layout', () async {
      final runningExe = File('${tempDir.path}/app/eduvi_viewer.exe');
      await runningExe.parent.create(recursive: true);
      await runningExe.writeAsString('mock');

      final unpackedV2Exe = File(
        '${tempDir.path}/app/game-runtime-v2/win-unpacked/EduVi Game.exe',
      );
      await unpackedV2Exe.parent.create(recursive: true);
      await unpackedV2Exe.writeAsString('mock');

      final fallbackRuntimeExe = File(
        '${tempDir.path}/app/game-runtime/EduVi Game.exe',
      );
      await fallbackRuntimeExe.parent.create(recursive: true);
      await fallbackRuntimeExe.writeAsString('mock');

      final launcher = RealElectronProcessLauncher(
        workingDirectory: '${tempDir.path}/workspace',
        environment: const <String, String>{},
        resolvedExecutablePath: runningExe.path,
      );

      final resolved = await launcher.resolveLaunchCommand();
      expect(
        p.normalize(resolved.executablePath),
        p.normalize(unpackedV2Exe.path),
      );
      expect(resolved.bootstrapArgs, isEmpty);
    });

    test('resolves build game-runtime-v2 win-unpacked layout', () async {
      final unpackedV2Exe = File(
        '${tempDir.path}/build/windows/x64/runner/Release/game-runtime-v2/win-unpacked/EduVi Game.exe',
      );
      await unpackedV2Exe.parent.create(recursive: true);
      await unpackedV2Exe.writeAsString('mock');

      final launcher = RealElectronProcessLauncher(
        workingDirectory: tempDir.path,
        environment: const <String, String>{},
      );

      final resolved = await launcher.resolveLaunchCommand();
      expect(
        p.normalize(resolved.executablePath),
        p.normalize(unpackedV2Exe.path),
      );
      expect(resolved.bootstrapArgs, isEmpty);
    });

    test('falls back to electron.exe with app dir bootstrap arg', () async {
      final electronExe = File(
        '${tempDir.path}/apps/electron_game_runtime/node_modules/electron/dist/electron.exe',
      );
      await electronExe.parent.create(recursive: true);
      await electronExe.writeAsString('mock');

      final appDir = Directory('${tempDir.path}/apps/electron_game_runtime');
      await appDir.create(recursive: true);

      final launcher = RealElectronProcessLauncher(
        workingDirectory: tempDir.path,
        environment: const <String, String>{},
      );

      final resolved = await launcher.resolveLaunchCommand();
      expect(p.normalize(resolved.executablePath), p.normalize(electronExe.path));
      expect(
        resolved.bootstrapArgs.map(p.normalize).toList(),
        [p.normalize(appDir.path)],
      );
    });

    test('throws helpful error when no runtime executable is found', () async {
      final launcher = RealElectronProcessLauncher(
        workingDirectory: tempDir.path,
        environment: const <String, String>{},
      );

      expect(
        () => launcher.resolveLaunchCommand(),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('Da thu cac duong dan'),
          ),
        ),
      );
    });
  });
}
