package com.example.beehive_app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "beehive.alarm"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAlarm" -> {
                        val hiveName = call.argument<String>("hiveName") ?: "Κυψέλη"
                        val hiveId = call.argument<String>("hiveId") ?: ""
                        try {
                            AlarmForegroundService.start(this, hiveName, hiveId)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ALARM_START_FAILED", e.message, null)
                        }
                    }

                    "stopAlarm" -> {
                        try {
                            AlarmForegroundService.stop(this)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ALARM_STOP_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
