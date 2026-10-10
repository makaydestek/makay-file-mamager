package com.makay.makay_file_manager

import android.app.usage.StorageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Environment
import android.os.Process
import android.os.StatFs
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/// Makay Dosya Yöneticisi ana aktivitesi.
///
/// Ek olarak uygulama genelinde kullanılan platform kanallarını sunar:
///  - Depolama bilgisi (StatFs): toplam/boş bayt  → Bellek Analizi (A4)
///  - Yüklü uygulamalar (liste, ikon, boyut)     → Uygulamalar ekranı (A6)
class MainActivity : FlutterActivity() {

    private val channelName = "com.makay.filemanager/platform"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStorageInfo" -> {
                        try {
                            val stat = StatFs(Environment.getExternalStorageDirectory().path)
                            result.success(
                                mapOf(
                                    "total" to stat.totalBytes,
                                    "free" to stat.freeBytes
                                )
                            )
                        } catch (e: Exception) {
                            result.error("storage_error", e.message, null)
                        }
                    }

                    "getInstalledApps" -> {
                        try {
                            result.success(installedApps())
                        } catch (e: Exception) {
                            result.error("apps_error", e.message, null)
                        }
                    }

                    "isTv" -> {
                        // Android TV: leanback veya dokunmatik ekran yok.
                        val pm = packageManager
                        val isTv =
                            pm.hasSystemFeature(android.content.pm.PackageManager.FEATURE_LEANBACK) ||
                            !pm.hasSystemFeature(android.content.pm.PackageManager.FEATURE_TOUCHSCREEN)
                        result.success(isTv)
                    }

                    "getSupportedAbis" -> {
                        // Otomatik guncelleme: cihazin birincil mimarisi (A16).
                        try {
                            result.success(Build.SUPPORTED_ABIS.toList())
                        } catch (e: Exception) {
                            result.error("abi_error", e.message, null)
                        }
                    }

                    "openDefaultAppsSettings" -> {
                        // Ayarlar → Varsayılan uygulamalar (A15).
                        try {
                            startActivity(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_SETTINGS))
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("settings_error", e2.message, null)
                            }
                        }
                    }

                    "installApk" -> {
                        // Otomatik güncelleme: indirilen APK'yı kur (A15).
                        val path = call.argument<String>("path")
                        val file = if (path != null) java.io.File(path) else null
                        if (file == null || !file.exists()) {
                            result.error("not_found", "APK dosyası bulunamadı", null)
                        } else {
                            try {
                                val uri = androidx.core.content.FileProvider.getUriForFile(
                                    this, "$packageName.fileprovider", file
                                )
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_ACTIVITY_NEW_TASK
                                    )
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("install_error", e.message, null)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /// Yüklü uygulamalar: ad, paket adı, sürüm, sistem uygulaması mı,
    /// boyut (StorageStats; izin yoksa -1) ve PNG ikon.
    private fun installedApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val packages = pm.getInstalledPackages(0)
        return packages.mapNotNull { pi ->
            val ai = pi.applicationInfo ?: return@mapNotNull null
            mapOf(
                "name" to pm.getApplicationLabel(ai).toString(),
                "packageName" to pi.packageName,
                "versionName" to (pi.versionName ?: ""),
                "isSystem" to ((ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                "size" to packageSize(pi.packageName, ai.uid),
                "icon" to iconPng(pm.getApplicationIcon(ai))
            )
        }
    }

    /// Paket boyutu (API 26+); PACKAGE_USAGE_STATS izni yoksa -1 döner.
    private fun packageSize(packageName: String, uid: Int): Long {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val statsManager =
                    getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
                // Varsayılan depolama birimi: 00000000-0000-0000-0000-000000000000
                val defaultUuid = java.util.UUID(0L, 0L)
                val stats = statsManager
                    .queryStatsForPackage(defaultUuid, packageName, Process.myUserHandle())
                stats.appBytes + stats.dataBytes
            } else {
                -1L
            }
        } catch (e: Exception) {
            -1L
        }
    }

    private fun iconPng(drawable: Drawable): ByteArray {
        val bitmap = drawableToBitmap(drawable)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 70, stream)
        return stream.toByteArray()
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            return drawable.bitmap
        }
        val width = drawable.intrinsicWidth.coerceAtLeast(1)
        val height = drawable.intrinsicHeight.coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }
}
