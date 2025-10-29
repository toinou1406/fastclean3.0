import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class FullScreenImageView extends StatelessWidget {
  final AssetEntity asset;

  const FullScreenImageView({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: FutureBuilder(
          future: asset.file,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
              final file = snapshot.data;
              if (file != null) {
                return InteractiveViewer(
                  panEnabled: true,
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                  ),
                );
              }
            }
            return FutureBuilder(
              future: asset.thumbnailDataWithSize(const ThumbnailSize(1080, 1920)),
              builder: (context, thumbSnapshot) {
                if (thumbSnapshot.connectionState == ConnectionState.done && thumbSnapshot.hasData) {
                  return Image.memory(
                    thumbSnapshot.data!,
                    fit: BoxFit.contain,
                  );
                }
                return const Center(child: CircularProgressIndicator());
              },
            );
          },
        ),
      ),
    );
  }
}
