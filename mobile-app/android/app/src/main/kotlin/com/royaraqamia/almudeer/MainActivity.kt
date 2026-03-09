package com.royaraqamia.almudeer

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {
    private val CHANNEL = "com.royaraqamia.almudeer/intent_action"
    private val TRANSFER_CHANNEL = "com.almudeer/background_transfer"
    private var lastAction: String? = null
    private var transferService: TransferForegroundService? = null
    private var serviceBound = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Capture initial intent action
        handleIntent(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getIntentAction") {
                result.success(lastAction)
            } else {
                result.notImplemented()
            }
        }

        // Background transfer method channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TRANSFER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    val channelId = call.argument<String>("channelId") ?: "transfer_channel"
                    val channelName = call.argument<String>("channelName") ?: "File Transfers"
                    val title = call.argument<String>("title") ?: "Transferring files"
                    val body = call.argument<String>("body") ?: "File transfer in progress"

                    startTransferService(title, body)
                    result.success(true)
                }
                "stopForegroundService" -> {
                    stopTransferService()
                    result.success(true)
                }
                "updateNotification" -> {
                    val progress = call.argument<Int>("progress") ?: 0
                    val notifTitle = call.argument<String>("title")
                    val notifBody = call.argument<String>("body")

                    transferService?.updateProgress(progress, notifTitle, notifBody)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        lastAction = intent?.action
    }

    private fun startTransferService(title: String, body: String) {
        val serviceIntent = Intent(this, TransferForegroundService::class.java).apply {
            putExtra("title", title)
            putExtra("body", body)
        }
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopTransferService() {
        val serviceIntent = Intent(this, TransferForegroundService::class.java).apply {
            action = TransferForegroundService.ACTION_STOP
        }
        stopService(serviceIntent)
    }
}
