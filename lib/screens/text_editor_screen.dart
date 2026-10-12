import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/category_size_service.dart';

/// Metin görüntüleyici/editörü: .txt/.md/.json/.xml/.csv/.log gibi düz
/// metin dosyalarını açar, düzenler ve kaydeder.
class TextEditorScreen extends StatefulWidget {
  const TextEditorScreen({super.key, required this.file, this.title});

  final File file;
  final String? title;

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  bool _truncated = false;
  String? _error;
  late String _original;

  /// Düzenleme için üst boyut sınırı (1 MB); üstünde salt okunur.
  static const int _editLimit = 1024 * 1024;

  /// Salt-okunur görünümde çizilecek azami karakter (çizim performansı için).
  static const int _displayLimit = 120 * 1024;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name => widget.title ??
      widget.file.path.split(Platform.pathSeparator).last;

  Future<void> _load() async {
    try {
      final size = await widget.file.length();
      // Çok büyük dosyaların başı okunur; tamamı belleği zorlamaz.
      final raf = await widget.file.open();
      final take = size > _editLimit ? _editLimit : size;
      final bytes = await raf.read(take);
      await raf.close();
      final text = utf8.decode(bytes, allowMalformed: true);
      _truncated = size > _editLimit;
      _original = text;
      _controller.text = text;
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Dosya açılamadı: $e';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.file.writeAsString(_controller.text, flush: true);
      _original = _controller.text;
      // Boyut değişti (ör. içerik tümüyle temizlenip 0 B oldu) → ana ekran
      // kategori etiketleri bayat boyut göstermeye devam etmemeli.
      await CategorySizeService.invalidate();
      if (!mounted) return;
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_name kaydedildi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydedilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Kaydedilmemiş değişiklik varsa sorar; true dönerse çıkışa izin var.
  Future<bool> _confirmLeave() async {
    if (_editing && _controller.text != _original) {
      final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kaydedilmemiş değişiklik'),
          content: Text('$_name için kaydedilmemiş değişiklikler var.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kaydet ve çık'),
            ),
          ],
        ),
      );
      if (save == true) {
        await _save();
        return true;
      }
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (_editing)
              IconButton(
                icon: const Icon(Icons.save_rounded),
                tooltip: 'Kaydet',
                onPressed: _saving ? null : _save,
              ),
            IconButton(
              icon: Icon(_editing
                  ? Icons.visibility_outlined
                  : Icons.edit_outlined),
              tooltip: _editing ? 'Salt okunur' : 'Düzenle',
              onPressed: _loading || _error != null
                  ? null
                  : () => setState(() => _editing = !_editing),
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
                : Column(
                    children: [
                      if (_editing && _saving) const LinearProgressIndicator(),
                      if (_truncated)
                        MaterialBanner(
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          content: const Text(
                            'Dosyanın yalnızca ilk 1 MB\'ı yüklendi; '
                            'büyük dosyalar salt okunurdur.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => setState(() {}),
                              child: const Text('Anlaşıldı'),
                            ),
                          ],
                        ),
                      Expanded(
                        child: _editing
                            ? TextField(
                                controller: _controller,
                                maxLines: null,
                                expands: true,
                                keyboardType: TextInputType.multiline,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(12),
                                ),
                              )
                            : SingleChildScrollView(
                                padding: const EdgeInsets.all(12),
                                // Uzun dosyalarda tüm metin çizilmez;
                                // performans için başı gösterilir.
                                child: SelectableText(
                                  _controller.text.length > _displayLimit
                                      ? '${_controller.text.substring(0, _displayLimit)}\n\n… (devamı görüntülenmiyor; düzenleyip kaydedebilirsiniz)'
                                      : _controller.text,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Text(
                          '${_controller.text.split('\n').length} satır • '
                          '${_controller.text.length} karakter',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
