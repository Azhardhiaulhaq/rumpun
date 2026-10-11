package app.rumpun.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rumpun/location").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val intent = Intent(this, LocationSharingService::class.java)
                    for (key in listOf("session", "token", "base", "device")) intent.putExtra(key, call.argument<String>(key))
                    intent.putExtra("remaining", call.argument<Number>("remaining")?.toLong() ?: 0L)
                    intent.putExtra("areas", org.json.JSONArray(call.argument<List<Any>>("areas") ?: emptyList<Any>()).toString())
                    startForegroundService(intent)
                    result.success(null)
                }
                "extend" -> {
                    startService(Intent(this, LocationSharingService::class.java).setAction("extend")
                        .putExtra("remaining", call.argument<Number>("remaining")?.toLong() ?: 0L)
                        .putExtra("token", call.argument<String>("token")))
                    result.success(null)
                }
                "device" -> {
                    val prefs = getSharedPreferences("location_device", MODE_PRIVATE)
                    val id = prefs.getString("id", null) ?: java.util.UUID.randomUUID().toString().also {
                        prefs.edit().putString("id", it).apply()
                    }
                    result.success(id)
                }
                "status" -> result.success(LocationSharingService.activeSession)
                "stop" -> {
                    startService(Intent(this, LocationSharingService::class.java).setAction("stop"))
                    result.success(null)
                }
                "interrupted" -> result.success(getSharedPreferences("sharing", MODE_PRIVATE).getString("interrupted", null))
                "clear" -> { getSharedPreferences("sharing", MODE_PRIVATE).edit().clear().apply(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    // Without a named channel Android files Rumpun's notifications under
    // Firebase's generic "Miscellaneous" channel in system settings.
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            getString(R.string.rumpun_notification_channel_id),
            getString(R.string.rumpun_notification_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = getString(R.string.rumpun_notification_channel_description)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
