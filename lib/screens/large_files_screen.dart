import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import '../services/analysis_service.dart';
import '../utils/formats.dart';
import '../utils/text_utils.dart';

/// Büyük dosyaların tam listesi ("DAHA FAZLA" ekranı).
class LargeFilesScreen extends StatefulWidget {
  const LargeFilesScreen({super.key, this.title = 'Büyük dosyalar'});

  final String title;

  @override
  State<LargeFilesScreen> createState() => _LargeFilesScreenState();
}

class _LargeFilesScreenState extends State<LargeFilesScreen> {
  static const _analysis = AnalysisService();

  var _loading = true;
  List<FileEntry> _files = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await _analysis.largeFiles(limit: 500);
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text('10 MB üzerinde dosya bulunamadı'))
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final f = _files[index];
                    return ListTile(
                      leading: Icon(f.icon, color: f.color),
                      title: Text(f.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        f.path
                            .replaceAll('/storage/emulated/0', '')
                            .ifEmpty('/'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(Formats.size(f.size)),
                    );
                  },
                ),
    );
  }
}
