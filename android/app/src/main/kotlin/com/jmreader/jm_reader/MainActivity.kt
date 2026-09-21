package com.jmreader.jm_reader

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.net.Uri
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity：
 * 1. 阅读器开启音量键翻页时，拦截音量键并转发给 Flutter
 * 2. 提供下载前台服务的启停通道，保证后台下载不被系统回收
 */
class MainActivity : FlutterActivity() {

    private val channelName = "jm_reader/platform"
    private var methodChannel: MethodChannel? = null

    /** 仅在阅读器页面开启，避免影响系统音量调节 */
    private var volumeKeyEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setVolumeKeyEnabled" -> {
                    volumeKeyEnabled = call.arguments as? Boolean ?: false
                    result.success(true)
                }

                "startForeground" -> {
                    val title = call.argument<String>("title") ?: "EAX管理器"
                    val text = call.argument<String>("text") ?: "正在下载"
                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        putExtra("title", title)
                        putExtra("text", text)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }

                "stopForeground" -> {
                    stopService(Intent(this, DownloadForegroundService::class.java))
                    result.success(true)
                }

                "hasAllFilesAccess" -> result.success(hasAllFilesAccess())

                "requestAllFilesAccess" -> {
                    requestAllFilesAccess()
                    result.success(true)
                }

                "isVpnActive" -> result.success(isVpnActive())

                "systemProxy" -> result.success(systemProxy())

                "scanMedia" -> {
                    scanMedia(call.argument<List<String>>("paths") ?: emptyList())
                    result.success(true)
                }

                "openUrl" -> {
                    result.success(openUrl(call.argument<String>("url") ?: ""))
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * 系统里是否有一条 VPN 连接在跑。
     *
     * 「绕过 DNS 污染」自动模式靠它判断：挂了 VPN 就不要再自己指定 IP，
     * 否则 VPN 的分流规则会因为拿不到域名而认错目标。
     */
    private fun isVpnActive(): Boolean {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return try {
            manager.allNetworks.any { network ->
                val caps = manager.getNetworkCapabilities(network) ?: return@any false
                caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 系统全局 HTTP 代理，形如 "127.0.0.1:7890"；没设置返回 null。
     *
     * Dart 的网络库不读系统代理，所以这种模式的梯子对 App 是隐形的，
     * 需要主动检测出来提示用户手填到设置里。
     */
    private fun systemProxy(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return null
        return try {
            val proxy = manager.defaultProxy ?: return null
            val host = proxy.host ?: return null
            if (host.isEmpty() || proxy.port <= 0) null else "$host:${proxy.port}"
        } catch (e: Exception) {
            null
        }
    }

    /**
     * 让系统相册重新看一眼这些目录。
     *
     * 目录里放了 .nomedia 之后，相册就不会再收录里面的图片。
     *
     * 这里只做「通知扫描」，绝对不能顺手去删媒体库里的记录：部分 ROM 上
     * 按 _data 删 MediaStore 记录会连真实文件一起删掉，用户下载好的本子
     * 会整批消失，只剩一个空目录。相册里以前留下的条目让系统自己刷新就好，
     * 丢几个缩略图是小事，丢用户的下载是大事。
     */
    private fun scanMedia(paths: List<String>) {
        if (paths.isEmpty()) return
        // 目录和目录里的 .nomedia 都交给扫描器：有的 ROM 只认文件路径
        val targets = mutableListOf<String>()
        for (path in paths) {
            targets.add(path)
            targets.add("$path/$NOMEDIA_FILE")
        }
        try {
            MediaScannerConnection.scanFile(this, targets.toTypedArray(), null) { _, _ -> }
        } catch (e: Exception) {
            // 扫描失败不影响 App 使用
        }
    }

    /** 用系统浏览器打开链接（下载页、新版本安装包） */
    private fun openUrl(url: String): Boolean {
        if (url.isEmpty()) return false
        return try {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (e: Exception) {
            // 没有浏览器或链接不合法
            false
        }
    }

    /** 是否已拿到公共目录的写权限 */
    private fun hasAllFilesAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    /** 申请「所有文件访问」：系统设置页授权后返回本应用 */
    private fun requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (Environment.isExternalStorageManager()) return
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                data = Uri.parse("package:$packageName")
            }
            try {
                startActivity(intent)
            } catch (e: Exception) {
                // 部分定制 ROM 没有应用级入口，退回总入口
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            requestPermissions(
                arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQUEST_STORAGE_CODE,
            )
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (volumeKeyEnabled) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    if (event.action == KeyEvent.ACTION_DOWN) {
                        val delta = if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) 1 else -1
                        methodChannel?.invokeMethod("onVolumeKey", delta)
                    }
                    // delta: +1 = 音量上键（往上翻），-1 = 音量下键（往下翻）
                    // 上下都吞掉，避免同时改变系统音量
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    companion object {
        private const val REQUEST_STORAGE_CODE = 1001

        /** 与 Dart 侧 JmStorage.nomediaFileName 保持一致 */
        private const val NOMEDIA_FILE = ".nomedia"
    }
}
