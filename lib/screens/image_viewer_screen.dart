import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Tam ekran resim görüntüleyici (dosya veya bellek baytları).
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({
    super.key,
    this.file,
    this.bytes,
    this.title,
  });

  final File? file;
  final Uint8List? bytes;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: GestureDetector(
        onDoubleTap: () => Navigator.of(context).pop(),
        child: InteractiveViewer(
          maxScale: 8,
          minScale: 0.5,
          child: Center(
            child: file != null
                ? Image.file(file!, fit: BoxFit.contain, gaplessPlayback: true)
                : Image.memory(bytes!, fit: BoxFit.contain, gaplessPlayback: true),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'Parmakla yakınlaştır • Çift dokunarak kapat',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }
}
