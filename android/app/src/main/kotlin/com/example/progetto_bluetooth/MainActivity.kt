package com.example.progetto_bluetooth

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context

class MainActivity: FlutterActivity() {

    private val CHANNEL = "com.example.progetto_bluetooth/gatt"
    private var gattServerHelper: GattServerHelper? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Inizializza il GattServerHelper con il contesto dell'applicazione.
        gattServerHelper = GattServerHelper(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when(call.method) {
                "startGattServer" -> {
                    val started = gattServerHelper?.startServer() ?: false
                    if (started) {
                        result.success("GATT server started")
                    } else {
                        result.error("SERVER_ERROR", "Could not start GATT server", null)
                    }
                }
                "stopGattServer" -> {
                    gattServerHelper?.stopServer()
                    result.success("GATT server stopped")
                }
                "getConnectedDevice" -> {
                    val deviceAddress = gattServerHelper?.getConnectedDevice()
                    result.success(deviceAddress)
                }
                "sendNotification" -> {
                    val message = call.argument<String>("message")
                    if (message != null) {
                        val success = gattServerHelper?.sendNotification(message) ?: false
                        if (success) {
                            result.success("Notification sent")
                        } else {
                            result.error("NOTIF_ERROR", "Failed to send notification", null)
                        }
                    } else {
                        result.error("ARG_ERROR", "Missing argument: message", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
