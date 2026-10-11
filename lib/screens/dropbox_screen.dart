import 'package:flutter/material.dart';

import '../services/dropbox_service.dart';
import 'cloud_screen.dart';

/// Dropbox gezinme ekranı.
///
/// Ortak [CloudOAuthBrowseScreen] sarmalayıcısıdır: liste, indirme,
/// yeni klasör ve silme işlemleri [DropboxService] üzerinden yürür.
class DropboxScreen extends StatelessWidget {
  const DropboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CloudOAuthBrowseScreen(
      title: 'Dropbox',
      // Dropbox kökünün yolu boş metindir.
      rootFolderId: '',
      list: DropboxService.list,
      download: DropboxService.download,
      createFolder: DropboxService.createFolder,
      remove: DropboxService.remove,
      about: DropboxService.about,
      onDisconnect: DropboxService.disconnect,
    );
  }
}
