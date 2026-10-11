import 'package:flutter/material.dart';

import '../services/onedrive_service.dart';
import 'cloud_screen.dart';

/// OneDrive (Microsoft Graph) gezinme ekranı.
///
/// Ortak [CloudOAuthBrowseScreen] sarmalayıcısıdır: liste, indirme,
/// yeni klasör ve silme işlemleri [OneDriveService] üzerinden yürür.
class OneDriveScreen extends StatelessWidget {
  const OneDriveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CloudOAuthBrowseScreen(
      title: 'OneDrive',
      rootFolderId: 'root',
      list: OneDriveService.list,
      download: OneDriveService.download,
      createFolder: OneDriveService.createFolder,
      remove: OneDriveService.remove,
      about: OneDriveService.about,
      onDisconnect: OneDriveService.disconnect,
    );
  }
}
