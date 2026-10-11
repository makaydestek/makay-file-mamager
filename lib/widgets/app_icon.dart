import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/platform_service.dart';

/// Yüklü uygulama ikonu — **tembel yüklenir**.
///
/// İkon üretmek (bitmap rasterleştirme + PNG sıkıştırma) paket başına
/// ağırdır; yüzlerce uygulamayı liste halinde ikonla getirmek Android ana iş
/// parçacığını bloklayıp "yanıt vermiyor (Bekle)" diyaloğuna yol açıyordu.
/// Bu bileşen ikonu tek tek, yalnızca ekrana gelen satır için ister; sonuç
/// [PlatformService] önbelleğinde tutulur, kaydırınca tekrar istenmez.
class AppIcon extends StatefulWidget {
  const AppIcon(this.app, {super.key, this.size = 36});

  final InstalledApp app;
  final double size;

  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  Uint8List? _bytes;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(AppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.packageName != widget.app.packageName) {
      _bytes = null;
      _requested = false;
      _load();
    }
  }

  void _load() {
    // Önce önbellek (yeniden kullanımda anında gelir), yoksa platformdan iste.
    final cached = PlatformService.cachedIcon(widget.app.packageName);
    if (cached != null) {
      _bytes = cached;
      _requested = true;
      return;
    }
    if (_requested) return;
    _requested = true;
    final pkg = widget.app.packageName;
    PlatformService.appIcon(pkg).then((bytes) {
      if (!mounted || bytes == null) return;
      setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final fallback = Icon(Icons.android_rounded, size: widget.size);
    if (bytes == null) return fallback;
    return Image.memory(
      bytes,
      width: widget.size,
      height: widget.size,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}