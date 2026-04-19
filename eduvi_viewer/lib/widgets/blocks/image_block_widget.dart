import 'package:flutter/material.dart';

import '../../models/block_model.dart';
import '../../services/asset_service.dart';

class ImageBlockWidget extends StatelessWidget {
  final EduViBlock block;
  final AssetService assetService;

  const ImageBlockWidget({
    super.key,
    required this.block,
    required this.assetService,
  });

  @override
  Widget build(BuildContext context) {
    if (block.missingMedia || block.src.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_not_supported, color: Colors.white38, size: 48),
            if (block.alt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  block.alt,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      );
    }

    final bytes = assetService.resolve(block.src);
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(bytes, fit: BoxFit.contain),
      );
    }

    if (block.src.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(block.src, fit: BoxFit.contain),
      );
    }

    return const SizedBox.shrink();
  }
}
