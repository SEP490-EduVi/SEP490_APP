import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/game_launch_contract.dart';

class GameLaunchContractService {
  Future<String> writeContract(GameLaunchContract contract) async {
    final outputDir = Directory(contract.outputDir);
    await outputDir.create(recursive: true);

    final contractPath = p.join(outputDir.path, 'launch.contract.json');
    final tempPath = '$contractPath.tmp';

    final encoded = const JsonEncoder.withIndent('  ').convert(contract.toJson());
    await File(tempPath).writeAsString(encoded);

    final destination = File(contractPath);
    if (await destination.exists()) {
      await destination.delete();
    }

    await File(tempPath).rename(contractPath);
    return contractPath;
  }
}
