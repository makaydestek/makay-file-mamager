package com.makay.makay_file_manager

import android.app.usage.StorageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.StatFs
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/// Makay Dosya Yöneticisi ana aktivitesi.
///
/// Ek olarak uygulama genelinde kullanılan platform kanallarını sunar:
///  - Depolama bilgisi (StatFs): toplam/boş bayt  → Bellek Analizi (A4)
///  - Yüklü uygulamalar (liste, ikon, boyut)     → Uygulamalar ekranı (A6)
///
/// **ANR notu**: uygulama listesi ve ikon üretimi ağır işlerdir (paket başına
/// binder çağrısı + bitmap rasterleştirme + PNG sıkıştırma). Bunlar eskiden
/// platform kanalı işleyicisinde, yani Android ana iş parçacığında çalışıyor
/// ve ana ekran her açıldığında "yanıt vermiyor (Bekle)" diyaloğuna yol
/// açıyordu. Artık [_bg] iş parçacığında çalışır; sonuç ana iş parçacığına
/// `result.success` ile geri verilir.
class MainActivity : FlutterActivity() {

    private val channelName = "com.makay.filemanager/platform"

    /// Ağır paket kanalı işleri için tek iş parçacıklı yürütücü.
    private val _bg: ExecutorService = Executors.newSingleThreadExecutor()

    /// Sonuçları ana iş parçacığına döndürmek için.
    private val _main = Handler(Looper.getMainLooper())

    /// Medya izni istek kodu.
    private val REQ_MEDIA = 4201

    /// Ağır kanal çağrısını arka planda çalıştırıp sonucu ana iş parçacığında
    /// teslim eder. Platform kanalı işleyicisi ana iş parçacığında döndüğü için
    /// [result.success] yalnızca oradan çağrılmalıdır.
    private fun <T> runBackground(result: MethodChannel.Result, work: () -> T) {
        _bg.execute {
            var value: Any? = null
            var failure: Exception? = null
            try {
                value = work()
            } catch (e: Exception) {
                failure = e
            }
            _main.post {
                val err = failure
                if (err != null) result.error("platform_error", err.message, null)
                else result.success(value)
            }
        }
    }

    /// Android 11+ "tüm dosyalara erişim" verildi mi?
    private fun hasAllFilesAccess(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager()

    /// Granüler medya (Android 13+) veya READ_EXTERNAL_STORAGE (eski) verildi mi?
    private fun hasMediaPermissions(): Boolean {
        val granted = { p: String ->
            androidx.core.content.ContextCompat.checkSelfPermission(this, p) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        }
        return if (Build.VERSION.SDK_INT >= 33) {
            granted(android.Manifest.permission.READ_MEDIA_IMAGES) &&
                granted(android.Manifest.permission.READ_MEDIA_VIDEO) &&
                granted(android.Manifest.permission.READ_MEDIA_AUDIO)
        } else {
            granted(android.Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

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
                        // Ağır iş: ana iş parçacığında kalırsa ANR olur.
                        // İkon YOK — listeler görünür oldukça tek tek istenir.
                        runBackground(result) { installedApps() }
                    }

                    "hasUsageAccess" -> {
                        // StorageStats yalnız bu izinle tüm paketler için okunur.
                        try {
                            result.success(hasUsageAccess())
                        } catch (e: Exception) {
                            result.error("usage_error", e.message, null)
                        }
                    }

                    "openUsageAccessSettings" -> {
                        // "Kullanım erişimi" yalnız sistem ayar ekranından verilir.
                        try {
                            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
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

                    "openAppSettings" -> {
                        // Android 13+ "kısıtlı ayarlar": sideload edilmiş
                        // uygulamalara özel erişim (kullanım erişimi) ANCAK
                        // Uygulama bilgisindeki ⋮ menüsünden verilir. Kullanıcıyı
                        // doğrudan o sayfaya götürürüz.
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    android.net.Uri.parse("package:$packageName")
                                )
                            )
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

                    "canRequestPackageInstalls" -> {
                        // APK kurulumu için "bilinmeyen kaynaklar" izni durumu
                        // (Android 8 altı her zaman izinli sayılır).
                        try {
                            val ok = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                                packageManager.canRequestPackageInstalls()
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("install_error", e.message, null)
                        }
                    }

                    "openInstallUnknownSources" -> {
                        // Yalnız bu paket için "Bilinmeyen kaynaklar" ekranı;
                        // açılamazsa genel güvenlik ayarlarına düşülür.
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    android.net.Uri.parse("package:$packageName")
                                )
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
                                result.success(true)
                            } catch (e2: Exception) {
                                result.success(false)
                            }
                        }
                    }

                    "getApkInfo" -> {
                        // İndirilenler'de APK'ya dokununca kurulum öncesi bilgi.
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("not_found", "APK yolu boş", null)
                        } else {
                            runBackground(result) { apkInfo(path) }
                        }
                    }

                    "getAppIcon" -> {
                        // Tek uygulamanın ikonu (liste ekranı tembel yükler).
                        val pkg = call.argument<String>("packageName")
                        runBackground(result) {
                            appIconPng(pkg ?: return@runBackground null)
                        }
                    }

                    "getVideoThumbnail" -> {
                        // Video liste/ızgara önizlemesi: ilk kare JPEG.
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.success(null)
                        } else {
                            runBackground(result) { videoThumbnailJpeg(path) }
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

                    "checkPermissions" -> {
                        // İlk açılış izin onayı (A18): durumu bildir.
                        try {
                            result.success(
                                mapOf(
                                    "allFiles" to hasAllFilesAccess(),
                                    "media" to hasMediaPermissions()
                                )
                            )
                        } catch (e: Exception) {
                            result.error("perm_error", e.message, null)
                        }
                    }

                    "requestAllFilesAccess" -> {
                        // "Tüm dosyalara erişim" yalnızca sistem ayar ekranından
                        // verilebilir; kullanıcıyı o ekrana yönlendiriyoruz.
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                    android.net.Uri.parse("package:$packageName")
                                )
                            )
                        } catch (e: Exception) {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                            )
                        }
                        result.success(hasAllFilesAccess())
                    }

                    "requestMediaPermissions" -> {
                        // Android 13+ granüler medya, alt sürümlerde READ_EXTERNAL_STORAGE.
                        try {
                            val perms = if (Build.VERSION.SDK_INT >= 33) {
                                arrayOf(
                                    android.Manifest.permission.READ_MEDIA_IMAGES,
                                    android.Manifest.permission.READ_MEDIA_VIDEO,
                                    android.Manifest.permission.READ_MEDIA_AUDIO
                                )
                            } else {
                                arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE)
                            }
                            requestPermissions(perms, REQ_MEDIA)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("perm_error", e.message, null)
                        }
                    }

                    "getStorageVolumes" -> {
                        // USB OTG / SD kart algılama: silinabilir birimler.
                        try {
                            result.success(storageVolumes())
                        } catch (e: Exception) {
                            result.error("volumes_error", e.message, null)
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
    /// boyut (StorageStats; izin yoksa -1) ve APK kaynak yolu.
    ///
    /// **İkon bilerek dönülmez**: ikon üretmek bitmap rasterleştirme + PNG
    /// sıkıştırmadır ve yüzlerce uygulamada onlarca saniye sürerdi. İkonlar
    /// `getAppIcon` ile tek tek, ekranda görünür oldukça istenir.
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
                "size" to packageSize(pi.packageName, ai.uid, ai.sourceDir ?: ""),
                // APK yedekleme: kurulum APK'sının gerçek yolu.
                "sourceDir" to (ai.sourceDir ?: "")
            )
        }
    }

    /// Tek bir uygulamanın ikonu (PNG baytları); bulunamazsa null.
    private fun appIconPng(packageName: String): ByteArray? {
        return try {
            val pm = packageManager
            iconPng(pm.getApplicationIcon(pm.getApplicationInfo(packageName, 0)))
        } catch (e: PackageManager.NameNotFoundException) {
            null
        } catch (e: Exception) {
            null
        }
    }

    /// Videonun ilk karesini ~256px JPEG olarak döndürür (önizleme).
    ///
    /// `MediaMetadataRetriever` dosyanın ilk senkron karesini verir; büyük
    /// videolarda bile tek kare okunduğu için hızlıdır. Okunamazsa null
    /// döner ve arayüz ikon geri düşmesi yapar.
    private fun videoThumbnailJpeg(path: String): ByteArray? {
        val retriever = android.media.MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val frame = retriever.getFrameAtTime(
                0,
                android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            ) ?: return null
            val maxDim = 256
            val scale = minOf(
                maxDim.toFloat() / frame.width.coerceAtLeast(1),
                maxDim.toFloat() / frame.height.coerceAtLeast(1),
                1f
            )
            val w = (frame.width * scale).toInt().coerceAtLeast(1)
            val h = (frame.height * scale).toInt().coerceAtLeast(1)
            val small = android.graphics.Bitmap.createScaledBitmap(frame, w, h, true)
            val out = java.io.ByteArrayOutputStream()
            small.compress(android.graphics.Bitmap.CompressFormat.JPEG, 78, out)
            out.toByteArray()
        } catch (e: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    /// Bağlı depolama birimleri (USB OTG / SD kart / dahili).
    ///
    /// `isRemovable` true olanlar harici (OTG/SD) olarak işaretlenir; Android 9
    /// ve öncesinde `getStorageVolumes()` API 21+ olduğundan her sürümde çalışır.
    private fun storageVolumes(): List<Map<String, Any?>> {
        val sm = getSystemService(Context.STORAGE_SERVICE)
            as android.os.storage.StorageManager
        return sm.storageVolumes.map { vol ->
            val state = try { vol.state } catch (e: Exception) { "" }
            val dir = try { vol.directory?.path ?: "" } catch (e: Exception) { "" }
            mapOf(
                "description" to (vol.getDescription(this) ?: ""),
                "isRemovable" to vol.isRemovable,
                "isEmulated" to vol.isEmulated,
                "state" to state,
                "path" to dir
            )
        }
    }

    override fun onDestroy() {
        _bg.shutdownNow()
        super.onDestroy()
    }

    /// Paket boyutu (API 26+).
    ///
    /// [hasUsageAccess] yoksa yalnızca KENDİ paketimizin boyutu okunabilir;
    /// diğer paketler SecurityException fırlatır. Bu durumda -1 yerine
    /// kurulum APK'sı (base.apk) boyutu döner: ana ekran kartı "0" ya da
    /// yalnız kendi uygulamanın boyutunu göstermez. Tam boyut (app + data)
    /// için kullanıcının Ayarlar → Kullanım erişimi'nden izin vermesi gerekir.
    private fun packageSize(packageName: String, uid: Int, sourceDir: String): Long {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val statsManager =
                    getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
                // Varsayılan depolama birimi: 00000000-0000-0000-0000-000000000000
                val defaultUuid = java.util.UUID(0L, 0L)
                val stats = statsManager
                    .queryStatsForPackage(defaultUuid, packageName, Process.myUserHandle())
                return stats.appBytes + stats.dataBytes
            } catch (e: Exception) {
                // İzin yok: aşağıda APK boyutuna düşülür.
            }
        }
        return try {
            if (sourceDir.isEmpty()) -1L else java.io.File(sourceDir).length().coerceAtLeast(-1L)
        } catch (e: Exception) {
            -1L
        }
    }

    /// "Kullanım erişimi" (PACKAGE_USAGE_STATS) izni verildi mi?
    private fun hasUsageAccess(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE)
                as android.app.AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(), packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(), packageName
                )
            }
            mode == android.app.AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    /// APK dosyasının paket bilgileri (kurulum diyaloğu için).
    ///
    /// [PackageManager.getPackageArchiveInfo] yalnız dosyadan okur; kurulu
    /// sürümle karşılaştırılarak "Kur" mu "Güncelle" mi gösterilir anlaşılır.
    private fun apkInfo(path: String): Map<String, Any?>? {
        val file = java.io.File(path)
        if (!file.exists()) return null
        val pm = packageManager
        val archive = pm.getPackageArchiveInfo(path, 0) ?: return null
        val ai = archive.applicationInfo
        // Etiket/ikon arşivden okunabilmesi için kaynak yolları dosyaya çevrilir.
        ai?.sourceDir = path
        ai?.publicSourceDir = path
        val label = ai?.let { pm.getApplicationLabel(it).toString() } ?: archive.packageName
        val installed = try {
            pm.getPackageInfo(archive.packageName, 0)
        } catch (e: Exception) {
            null
        }
        return mapOf(
            "name" to label,
            "packageName" to archive.packageName,
            "versionName" to (archive.versionName ?: ""),
            "versionCode" to versionCodeOf(archive),
            "installed" to (installed != null),
            "installedVersionName" to (installed?.versionName ?: ""),
            "installedVersionCode" to (installed?.let { versionCodeOf(it) } ?: -1L),
            "size" to file.length()
        )
    }

    /// PackageInfo sürüm numarası (API 28'de longVersionCode'a geçildi).
    private fun versionCodeOf(info: android.content.pm.PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else @Suppress("DEPRECATION") info.versionCode.toLong()

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
