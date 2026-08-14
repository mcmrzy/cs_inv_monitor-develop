package com.csergy.app1

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 自研 WiFi 扫描通道（替代停更的 wifi_scan 插件，消除 KGP 警告）
        flutterEngine.plugins.add(WifiScanPlugin())
    }
}
