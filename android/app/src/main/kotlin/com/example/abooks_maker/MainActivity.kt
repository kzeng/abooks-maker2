package com.example.abooks_maker

import android.os.Environment
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "abooks_maker/storage"
        ).setMethodCallHandler { call, result ->
            if (call.method == "publicDownloadsDirectory") {
                result.success(
                    Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS
                    ).absolutePath
                )
            } else {
                result.notImplemented()
            }
        }
    }
}
