package com.example.progetto_bluetooth

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {

    private val GATT_CHANNEL = "com.example.progetto_bluetooth/gatt"
    private val GATT_EVENTS_CHANNEL = "com.example.progetto_bluetooth/gatt_events"
    private var gattServerHelper: GattServerHelper? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        gattServerHelper = GattServerHelper(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GATT_CHANNEL).setMethodCallHandler { call, result ->
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

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, GATT_EVENTS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    GattServerHelper.eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    GattServerHelper.eventSink = null
                }
            }
        )
    }
}
