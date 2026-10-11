import 'package:flutter/material.dart';

import '../services/box_service.dart';
import '../services/dropbox_service.dart';
import '../services/onedrive_service.dart';
import 'box_screen.dart';
import 'dropbox_screen.dart';
import 'google_drive_screen.dart';
import 'onedrive_screen.dart';

/// Desteklenen bulut sağlayıcıları.
const kCloudProviders = <String, String>{
  'Nextcloud': 'nextcloud',
  'ownCloud': 'webdav',
  'pCloud': 'webdav',
  'Yandex Disk': 'webdav',
  'WebDAV': 'webdav',
  'Dropbox': 'oauth',
  'Google Drive': 'oauth',
  'OneDrive': 'oauth',
  'Box': 'oauth',
};

/// Google Drive dışındaki OAuth sağlayıcıları (tile/panel sırası).
const kOAuthProviderNames = <String>['Dropbox', 'OneDrive', 'Box'];

/// Sağlayıcı adını gezinme ekranına çevirir.
Widget? oauthScreenFor(String provider) => switch (provider) {
  'Google Drive' => const GoogleDriveScreen(),
  'Dropbox' => const DropboxScreen(),
  'OneDrive' => const OneDriveScreen(),
  'Box' => const BoxScreen(),
  _ => null,
};

/// OAuth sağlayıcısının servis uçları (panel ve durum yenileme için).
typedef OauthApi = ({
  Future<bool> Function() hasTokens,
  Future<String?> Function() loadClientSecret,
  Future<void> Function(String) connect,
  Future<void> Function() disconnect,
});

/// Dropbox / OneDrive / Box servis uçları.
OauthApi? oauthApiFor(String provider) => switch (provider) {
  'Dropbox' => (
    hasTokens: DropboxService.hasTokens,
    loadClientSecret: DropboxService.loadClientSecret,
    connect: DropboxService.connect,
    disconnect: DropboxService.disconnect,
  ),
  'OneDrive' => (
    hasTokens: OneDriveService.hasTokens,
    loadClientSecret: OneDriveService.loadClientSecret,
    connect: OneDriveService.connect,
    disconnect: OneDriveService.disconnect,
  ),
  'Box' => (
    hasTokens: BoxService.hasTokens,
    loadClientSecret: BoxService.loadClientSecret,
    connect: BoxService.connect,
    disconnect: BoxService.disconnect,
  ),
  _ => null,
};
