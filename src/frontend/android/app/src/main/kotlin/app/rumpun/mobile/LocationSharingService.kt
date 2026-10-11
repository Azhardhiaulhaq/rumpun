package app.rumpun.mobile

import android.app.*
import android.content.Intent
import android.location.*
import android.os.*
import android.content.pm.PackageManager
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.concurrent.Executors

class LocationSharingService : Service(), LocationListener {
    companion object { @Volatile var activeSession: String? = null }
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var manager: LocationManager
    private var deadline = 0L
    private var session = ""
    private var token = ""
    private var base = ""
    private var device = ""
    private var sequence = 0L
    private var detector = ArrivalDetector("[]")
    private val pendingArrivals = mutableListOf<JSONObject>()
    private val networkLock = Any()
    private var latestPosition: JSONObject? = null
    private var draining = false
    @Volatile private var connection: HttpURLConnection? = null
    private var lastUpload = 0L
    @Volatile private var running = false
    private val watchdog = object : Runnable {
        override fun run() {
            if (!running) return
            if (SystemClock.elapsedRealtime() >= deadline ||
                checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED ||
                !manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                finishSharing()
            } else handler.postDelayed(this, 1000)
        }
    }
    override fun onBind(intent: Intent?) = null
    override fun onCreate() {
        super.onCreate()
        manager = getSystemService(LocationManager::class.java)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") { finishSharing(); return START_NOT_STICKY }
        if (intent?.action == "extend") {
            if (running) {
                deadline = SystemClock.elapsedRealtime() + intent.getLongExtra("remaining", 0)
                token = intent.getStringExtra("token") ?: token
            } else stopSelf()
            return START_NOT_STICKY
        }
        if (intent == null) { stopSelf(); return START_NOT_STICKY }
        session = intent.getStringExtra("session") ?: ""
        token = intent.getStringExtra("token") ?: ""
        base = intent.getStringExtra("base") ?: ""
        device = intent.getStringExtra("device") ?: ""
        val remaining = intent.getLongExtra("remaining", 0)
        if (remaining <= 0 || session.isEmpty()) { stopSelf(); return START_NOT_STICKY }
        deadline = SystemClock.elapsedRealtime() + remaining
        detector = ArrivalDetector(intent.getStringExtra("areas") ?: "[]")
        getSharedPreferences("sharing", MODE_PRIVATE).edit().putString("interrupted", session).apply()
        val notifications = getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(NotificationChannel("location_sharing", "Berbagi lokasi aktif", NotificationManager.IMPORTANCE_LOW))
        val stop = PendingIntent.getService(this, 2, Intent(this, LocationSharingService::class.java).setAction("stop"), PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 3, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        startForeground(701, Notification.Builder(this, "location_sharing")
            .setSmallIcon(R.drawable.ic_stat_rumpun).setContentTitle("Berbagi lokasi aktif")
            .setContentText("Ketuk untuk membuka Rumpun. Berbagi berakhir sesuai timer.")
            .setContentIntent(open).setOngoing(true).addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stop).build())
        try {
            running = true
            activeSession = session
            manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 10000, 0f, this)
            if (manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                manager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 10000, 0f, this)
            }
            handler.removeCallbacks(watchdog)
            handler.post(watchdog)
        } catch (_: SecurityException) { finishSharing() }
        return START_NOT_STICKY
    }
    override fun onLocationChanged(location: Location) {
        if (!running || SystemClock.elapsedRealtime() >= deadline) return
        val payload = JSONObject().put("device_id", device).put("latitude", location.latitude)
            .put("longitude", location.longitude).put("accuracy", location.accuracy.toDouble())
            .put("observed_at", Instant.ofEpochMilli(location.time).toString()).put("sequence", ++sequence)
        val arrived = detector.observe(location)
        synchronized(networkLock) {
            if (arrived.isNotEmpty()) pendingArrivals.add(JSONObject().put("device_id", device)
                .put("area_ids", org.json.JSONArray(arrived)).put("arrived_at", Instant.ofEpochMilli(location.time).toString()))
            val interval = if (location.hasSpeed() && location.speed > 1f) 10000L else 30000L
            if (SystemClock.elapsedRealtime() - lastUpload >= interval) latestPosition = payload
            if (draining) return
            draining = true
        }
        executor.execute {
            try {
                val newest = synchronized(networkLock) { latestPosition.also { latestPosition = null } }
                if (running && newest != null && request("PUT", "/sessions/$session/position", newest)) {
                    lastUpload = SystemClock.elapsedRealtime()
                }
                while (running && SystemClock.elapsedRealtime() < deadline) {
                    val event = synchronized(networkLock) { pendingArrivals.firstOrNull() } ?: break
                    if (!request("POST", "/sessions/$session/arrivals", event)) break
                    synchronized(networkLock) { pendingArrivals.remove(event) }
                }
            } finally { synchronized(networkLock) { draining = false } }
        }
    }
    private fun request(method: String, path: String, body: JSONObject? = null): Boolean {
        try {
            if (path.endsWith("/position") || path.endsWith("/arrivals")) {
                if (!running || SystemClock.elapsedRealtime() >= deadline) return false
            }
            val connection = URL("$base/location$path").openConnection() as HttpURLConnection
            this.connection = connection
            connection.requestMethod = method
            connection.connectTimeout = 10000; connection.readTimeout = 10000
            connection.setRequestProperty("Authorization", "Bearer $token")
            connection.setRequestProperty("Content-Type", "application/json")
            if (body != null) { connection.doOutput = true; connection.outputStream.use { it.write(body.toString().toByteArray()) } }
            val status = connection.responseCode
            connection.disconnect()
            this.connection = null
            if (status == 401 || status == 403 || status == 409) handler.post { finishSharing() }
            return status in 200..299
        } catch (_: Exception) { return false }
    }
    private fun finishSharing() {
        if (!running) { stopSelf(); return }
        activeSession = null
        running = false
        connection?.disconnect()
        synchronized(networkLock) { pendingArrivals.clear(); latestPosition = null }
        manager.removeUpdates(this)
        handler.removeCallbacks(watchdog)
        executor.execute { request("POST", "/sessions/$session/stop") }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
    override fun onDestroy() {
        activeSession = null
        running = false
        manager.removeUpdates(this)
        handler.removeCallbacks(watchdog)
        connection?.disconnect()
        synchronized(networkLock) { pendingArrivals.clear(); latestPosition = null }
        executor.shutdown()
        super.onDestroy()
    }
}
