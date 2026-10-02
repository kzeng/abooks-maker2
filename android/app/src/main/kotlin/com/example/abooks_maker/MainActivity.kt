package com.example.abooks_maker

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Environment
import android.os.Build
import android.provider.DocumentsContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "abooks_maker/storage"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "publicDownloadsDirectory" -> result.success(
                    Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS
                    ).absolutePath
                )
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "abooks_maker/foreground_service"
        ).setMethodCallHandler { call, result ->
            val serviceIntent = Intent(this, ConversionForegroundService::class.java)
            when (call.method) {
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.POST_NOTIFICATIONS
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            4001
                        )
                    }
                    result.success(null)
                }
                "start" -> {
                    serviceIntent.action = ConversionForegroundService.ACTION_START
                    serviceIntent.putExtra("title", call.argument<String>("title"))
                    serviceIntent.putExtra("total", call.argument<Int>("total") ?: 0)
                    ContextCompat.startForegroundService(this, serviceIntent)
                    result.success(null)
                }
                "update" -> {
                    serviceIntent.action = ConversionForegroundService.ACTION_UPDATE
                    serviceIntent.putExtra("progress", call.argument<Int>("completed") ?: 0)
                    serviceIntent.putExtra("total", call.argument<Int>("total") ?: 0)
                    serviceIntent.putExtra("message", call.argument<String>("message"))
                    startService(serviceIntent)
                    result.success(null)
                }
                "pause", "resume", "cancel", "stop" -> {
                    serviceIntent.action = when (call.method) {
                        "pause" -> ConversionForegroundService.ACTION_PAUSE
                        "resume" -> ConversionForegroundService.ACTION_RESUME
                        "cancel" -> ConversionForegroundService.ACTION_CANCEL
                        else -> ConversionForegroundService.ACTION_STOP
                    }
                    startService(serviceIntent)
                    result.success(null)
                }
                "command" -> result.success(
                    getSharedPreferences("conversion_service", MODE_PRIVATE)
                        .getString(ConversionForegroundService.COMMAND_KEY, null)
                )
                "clearCommand" -> {
                    getSharedPreferences("conversion_service", MODE_PRIVATE)
                        .edit().remove(ConversionForegroundService.COMMAND_KEY).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "abooks_maker/files"
        ).setMethodCallHandler { call, result ->
            if (call.method != "openDirectory") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("INVALID_PATH", "目录路径为空", null)
                return@setMethodCallHandler
            }
            try {
                val root = Environment.getExternalStorageDirectory()
                val relativePath = java.io.File(path).relativeTo(root).path
                val uri = DocumentsContract.buildTreeDocumentUri(
                    "com.android.externalstorage.documents",
                    "primary:$relativePath"
                )
                startActivity(
                    Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
                        }
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                        )
                    }
                )
                result.success(null)
            } catch (error: Exception) {
                result.error("OPEN_DIRECTORY_FAILED", error.message, null)
            }
        }
    }
}
