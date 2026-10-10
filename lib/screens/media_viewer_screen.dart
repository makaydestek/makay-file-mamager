import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Yerleşik medya oynatıcı (video ve ses).
///
/// Video: tam genişlik oynatma + gizlenen denetimler.
/// Ses: sanat alanı yer tutucusu + zaman çubuğu.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.file,
    required this.isVideo,
  });

  final File file;
  final bool isVideo;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final VideoPlayerController _controller;
  bool _initialized = false;
  String? _error;
  bool _controlsVisible = true;

  String get _name {
    final segments = widget.file.uri.pathSegments.where((s) => s.isNotEmpty);
    return segments.isEmpty ? widget.file.path : segments.last;
  }

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
        _controller.play();
      }).catchError((Object e) {
        if (mounted) setState(() => _error = '$e');
      })
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Oynatılamadı:\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              )
            : !_initialized
                ? const CircularProgressIndicator()
                : widget.isVideo
                    ? _videoBody()
                    : _audioBody(),
      ),
    );
  }

  Widget _videoBody() {
    final v = _controller.value;
    return GestureDetector(
      onTap: () => setState(() => _controlsVisible = !_controlsVisible),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio,
            child: VideoPlayer(_controller),
          ),
          if (_controlsVisible) ...[
            // Arka plan karartması.
            Positioned.fill(
                child: Container(color: Colors.black45)),
            // Ortada oynat/duraklat.
            IconButton(
              iconSize: 72,
              icon: Icon(
                v.isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
                color: Colors.white,
              ),
              onPressed: () {
                v.isPlaying ? _controller.pause() : _controller.play();
              },
            ),
            // Alt denetimler.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _controlsBar(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _audioBody() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00897B), Color(0xFF26A69A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.music_note_rounded,
                size: 96, color: Colors.white),
          ),
          const SizedBox(height: 24),
          Text(
            _name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 16),
          _controlsBar(),
          const SizedBox(height: 12),
          IconButton(
            iconSize: 64,
            icon: Icon(
              _controller.value.isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: Colors.white,
            ),
            onPressed: () {
              _controller.value.isPlaying
                  ? _controller.pause()
                  : _controller.play();
            },
          ),
        ],
      ),
    );
  }

  Widget _controlsBar() {
    final v = _controller.value;
    final duration = v.duration;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            _fmt(v.position),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Expanded(
            child: Slider(
              value: v.position.inMilliseconds
                  .clamp(0, duration.inMilliseconds)
                  .toDouble(),
              max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
              onChanged: (value) {
                _controller.seekTo(Duration(milliseconds: value.round()));
              },
            ),
          ),
          Text(
            _fmt(duration),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          IconButton(
            icon: Icon(
              v.volume > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: Colors.white,
            ),
            onPressed: () {
              _controller.setVolume(v.volume > 0 ? 0 : 1);
            },
          ),
        ],
      ),
    );
  }
}
