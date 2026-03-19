package com.vennuzo.app

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.vennuzo.app/maps_config"
        ).setMethodCallHandler { call, result ->
            if (call.method != "getApiKey") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val applicationInfo = packageManager.getApplicationInfo(
                packageName,
                PackageManager.GET_META_DATA
            )
            result.success(
                applicationInfo.metaData?.getString("com.google.android.geo.API_KEY")
            )
        }
    }
}
