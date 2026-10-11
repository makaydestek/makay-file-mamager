import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Hex görüntüleyici: dosyayı 16 bayt/satır olarak (offset + hex + ASCII)
/// gösterir. Satırlar sanaldır (ListView.builder) — büyük dosyalarda da akıcı.
class HexViewerScreen extends StatefulWidget {
  const HexViewerScreen({super.key, required this.file, this.title});

  final File file;
  final String? title;

  @override
  State<HexViewerScreen> createState() => _HexViewerScreenState();
}

class _HexViewerScreenState extends State<HexViewerScreen> {
  static const int _bytesPerRow = 16;

  int _size = 0;
  bool _loading = true;
  String? _error;
  RandomAccessFile? _raf;
  final Map<int, List<int>> _cache = {};

  /// Satır bazlı Future önbelleği: FutureBuilder aynı Future nesnesini
  /// görürse yeniden abone olmaz (aksi halde sonsuz rebuild döngüsü olur).
  final Map<int, Future<List<int>>> _futures = {};
  static const int _cacheLimit = 512;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final raf = await widget.file.open();
      final size = await raf.length();
      _raf = raf;
      if (mounted) {
        setState(() {
          _size = size;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Dosya açılamadı: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _raf?.close();
    super.dispose();
  }

  /// Satırın baytlarını okur; Future nesnesi önbelleklenir ki
  /// FutureBuilder her rebuild'te aynı nesneyi görsün.
  Future<List<int>> _rowFuture(int rowIndex) =>
      _futures.putIfAbsent(rowIndex, () => _row(rowIndex));

  /// Satırın başladığı bayttan itibaren 16 baytı okur (önbellekli).
  Future<List<int>> _row(int rowIndex) async {
    final cached = _cache[rowIndex];
    if (cached != null) return cached;
    final raf = _raf;
    if (raf == null) return const [];
    final offset = rowIndex * _bytesPerRow;
    final remaining = _size - offset;
    if (remaining <= 0) return const [];
    final take = remaining < _bytesPerRow ? remaining : _bytesPerRow;
    try {
      await raf.setPosition(offset);
      final bytes = await raf.read(take);
      if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
      _cache[rowIndex] = bytes;
      return bytes;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.title ??
        widget.file.path.split(Platform.pathSeparator).last;
    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'Bilgi',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Boyut: $_size bayt'),
                    Text('Satır genişliği: $_bytesPerRow bayt'),
                    Text('Toplam satır: ${(_size / _bytesPerRow).ceil()}'),
                  ],
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tamam'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _size == 0
                  ? const Center(child: Text('Boş dosya'))
                  : Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Text(
                            '00000000  00 01 02 03 04 05 06 07  '
                            '08 09 0A 0B 0C 0D 0E 0F   ASCII',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: (_size / _bytesPerRow).ceil(),
                            itemBuilder: (context, index) =>
                                _HexRow(index: index, load: _rowFuture),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

/// Tek bir hex satırı: offset, 16 bayt hex ve ASCII karşılığı.
class _HexRow extends StatelessWidget {
  const _HexRow({required this.index, required this.load});

  final int index;
  final Future<List<int>> Function(int) load;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: load(index),
      builder: (context, snapshot) {
        final bytes = snapshot.data ?? const <int>[];
        final offset =
            (index * 16).toRadixString(16).padLeft(8, '0').toUpperCase();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  offset,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppTheme.accent),
                ),
              ),
              SizedBox(
                width: 300,
                child: Text(
                  _hexText(bytes),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              Expanded(
                child: Text(
                  _asciiText(bytes),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _hexText(List<int> bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i < bytes.length) {
        buffer.write(bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
      } else {
        buffer.write('  ');
      }
      buffer.write(i == 7 ? '  ' : ' ');
    }
    return buffer.toString();
  }

  static String _asciiText(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b >= 0x20 && b < 0x7f ? String.fromCharCode(b) : '.');
    }
    return buffer.toString();
  }
}
