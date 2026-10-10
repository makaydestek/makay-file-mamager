import 'package:flutter/material.dart';

import '../services/recycle_bin_service.dart';
import '../utils/formats.dart';

/// Geri dönüşüm kutusu ekranı: liste, geri yükle, kalıcı sil, kutuyu boşalt.
class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  @override
  void initState() {
    super.initState();
    RecycleBinService.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = RecycleBinService.instance;
    final items = service.items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geri Dönüşüm Kutusu'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Kutuyu boşalt'),
                    content: Text(
                        '${items.length} öğe kalıcı olarak silinecek. Emin misiniz?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('İptal'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Boşalt'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await service.empty();
                  if (mounted) setState(() {});
                }
              },
              child: const Text('BOŞALT'),
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('Geri dönüşüm kutusu boş'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: Icon(
                    item.isDirectory
                        ? Icons.folder_rounded
                        : Icons.insert_drive_file_rounded,
                    color: item.isDirectory
                        ? const Color(0xFFF9A825)
                        : Colors.grey,
                    size: 32,
                  ),
                  title: Text(item.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${Formats.size(item.size)} • ${Formats.date(item.deletedAt)}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      switch (v) {
                        case 'restore':
                          await service.restore(item);
                        case 'delete':
                          await service.deletePermanently(item);
                      }
                      if (mounted) setState(() {});
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                          value: 'restore', child: Text('Geri yükle')),
                      PopupMenuItem(
                          value: 'delete', child: Text('Kalıcı sil')),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Toplam: ${Formats.size(service.totalSize)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
    );
  }
}
