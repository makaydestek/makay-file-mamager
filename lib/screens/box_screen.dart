import 'package:flutter/material.dart';

import '../services/box_service.dart';
import 'cloud_screen.dart';

/// Box gezinme ekranı.
///
/// Ortak [CloudOAuthBrowseScreen] sarmalayıcısıdır: liste, indirme,
/// yeni klasör ve silme işlemleri [BoxService] üzerinden yürür.
class BoxScreen extends StatelessWidget {
  const BoxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CloudOAuthBrowseScreen(
      title: 'Box',
      // Box kök klasörünün kimliği 0'dır.
      rootFolderId: '0',
      list: BoxService.list,
      download: BoxService.download,
      createFolder: BoxService.createFolder,
      remove: BoxService.remove,
      about: BoxService.about,
      onDisconnect: BoxService.disconnect,
    );
  }
}
