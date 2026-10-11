package app.rumpun.mobile

import android.location.Location
import org.json.JSONArray
import kotlin.math.*

/**
 * Mirrors src/backend/app/location_arrivals.py so arrivals still confirm while
 * the phone is briefly offline. The server applies the same rules to uploaded
 * positions, and per-area deduplication means whichever reports first wins.
 */
class ArrivalDetector(snapshot: String) {
    private enum class Phase { UNKNOWN, STARTING, OUTSIDE, ENTERING, NOTIFIED }
    private class Area(val id: String, val vertices: List<Pair<Double, Double>>) {
        var phase = Phase.UNKNOWN
        var since = 0L
        var last = 0L
    }
    private val areas = mutableListOf<Area>()
    private var previous = -1L

    init {
        val json = JSONArray(snapshot)
        for (i in 0 until json.length()) {
            val item = json.getJSONObject(i)
            val vertices = item.getJSONArray("vertices")
            areas.add(Area(item.getString("id"), (0 until vertices.length()).map {
                val p = vertices.getJSONArray(it); Pair(p.getDouble(0), p.getDouble(1))
            }))
        }
    }

    fun observe(location: Location): List<String> {
        val now = location.elapsedRealtimeNanos / 1_000_000
        if (now <= previous) return emptyList()
        previous = now
        val accuracy = if (location.hasAccuracy()) location.accuracy.toDouble() else -1.0
        val result = mutableListOf<String>()
        for (area in areas) {
            if (area.phase == Phase.NOTIFIED) continue
            val inside = classify(area.vertices, location.latitude, location.longitude, accuracy) ?: continue
            when (area.phase) {
                Phase.UNKNOWN -> area.phase = if (inside) Phase.STARTING else Phase.OUTSIDE
                Phase.STARTING -> if (!inside) area.phase = Phase.OUTSIDE
                Phase.OUTSIDE -> if (inside) { area.phase = Phase.ENTERING; area.since = now; area.last = now }
                Phase.ENTERING -> {
                    if (!inside) { area.phase = Phase.OUTSIDE; continue }
                    if (now - area.last > MAX_SILENCE_MS) area.since = now
                    area.last = now
                    if (now - area.since >= DWELL_MS) { area.phase = Phase.NOTIFIED; result.add(area.id) }
                }
                Phase.NOTIFIED -> Unit
            }
        }
        return result
    }

    /** true inside, false clearly outside, null when the reading cannot tell. */
    private fun classify(vertices: List<Pair<Double, Double>>, lat: Double, lng: Double, accuracy: Double): Boolean? {
        if (accuracy <= 0 || accuracy > MAX_ACCURACY_M || vertices.size < 3) return null
        val scale = METRES_PER_DEGREE * cos(lat * PI / 180)
        val points = vertices.map { Pair((it.second - lng) * scale, (it.first - lat) * METRES_PER_DEGREE) }
        var inside = false
        var nearest = Double.MAX_VALUE
        for (i in points.indices) {
            val (ax, ay) = points[i]; val (bx, by) = points[(i + 1) % points.size]
            val dx = bx - ax; val dy = by - ay
            val length = dx * dx + dy * dy
            val t = if (length == 0.0) 0.0 else (-(ax * dx + ay * dy) / length).coerceIn(0.0, 1.0)
            nearest = min(nearest, hypot(ax + t * dx, ay + t * dy))
            if ((ay > 0) != (by > 0) && 0 < ax + (bx - ax) * (-ay) / (by - ay)) inside = !inside
        }
        if (inside || nearest <= min(INSIDE_TOLERANCE_M, accuracy / 2)) return true
        if (nearest >= max(OUTSIDE_MIN_M, accuracy)) return false
        return null
    }

    companion object {
        const val MAX_ACCURACY_M = 100.0
        const val INSIDE_TOLERANCE_M = 15.0
        const val OUTSIDE_MIN_M = 30.0
        const val DWELL_MS = 30_000L
        const val MAX_SILENCE_MS = 180_000L
        const val METRES_PER_DEGREE = 111_320.0
    }
}
