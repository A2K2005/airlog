package app.airlog.airlog

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.text.TextPaint
import android.text.TextUtils
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetFonts
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan
import org.json.JSONObject

// The home-screen widgets' shared renderer (docs/WIDGETS_PLAN.md). Each
// widget is ONE bitmap drawn here on a Canvas: the tile's glow recipe
// clipped to its squircle, and text placed by pen x and baseline at the
// design's own coordinates, as lib/design/components/tile.dart does. The
// recipes, inks and type come from res/raw/airlog_widget_glows.json, which
// test/data/widget_glows_test.dart generates from the Dart tokens. Fonts are
// read in place from the Flutter assets in the APK (HomeWidgetFonts): the
// personal-use dot face is never copied into res/.

/** Widget-only strings (WIDGETS_PLAN §4). Everything else comes from Dart. */
object WidgetCopy {
    const val SAMPLE = "Sample data"
    const val NO_DATA = "No data yet"
    const val START = "Open Airlog to get started"
    const val LATEST_PLAN = "Open Airlog for the latest plan"
    const val MISSING = "--" // DotMatrixNumber.missing: the dot face has no en dash
    const val NOTHING = "Nothing to change today." // PlanTile's empty-actions line

    private val day = DateTimeFormatter.ofPattern("d MMM", Locale.ENGLISH)

    /** "From 29 Sep": the day a stale snapshot shows (QA-08). */
    fun from(date: String): String =
        runCatching { "From ${LocalDate.parse(date).format(day)}" }.getOrDefault("From $date")
}

/** The snapshot airlog_snapshot_v1 that widget_sink.dart writes. */
class WidgetSnapshot(private val j: JSONObject) {
    val date: String = j.optString("date", "")
    val demo: Boolean = j.optBoolean("demo", false)
    val empty: Boolean get() = date.isEmpty()

    /**
     * QA-08: the day shown isn't today. Checked here too, on every draw, so
     * the label appears at midnight even when no Dart has run since.
     */
    val stale: Boolean get() = date.isNotEmpty() && date != LocalDate.now().toString()

    val recovery: Int? = if (j.isNull("recovery")) null else j.optInt("recovery", -1).takeIf { it >= 0 }
    val recStatus: String = j.optString("recStatus", "").ifEmpty { if (recovery == null) "No data" else "" }
    val recBasis: String = j.optString("recBasis", "")
    val sleepText: String = j.optString("sleep", "").takeIf { it != "–" } ?: ""

    /** A dot-matrix slot: "--" when missing. Pre-v2 payloads map the en dash. */
    fun dots(key: String): String {
        val d = j.optJSONObject("dots")
        if (d != null) return d.optString(key, WidgetCopy.MISSING)
        return when (key) {
            "recovery" -> recovery?.toString() ?: WidgetCopy.MISSING
            "strain" -> j.optString("strain", "").takeIf { it.isNotEmpty() && it != "–" } ?: WidgetCopy.MISSING
            else -> WidgetCopy.MISSING
        }
    }

    val plan: JSONObject? = j.optJSONObject("plan")

    companion object {
        fun read(prefs: SharedPreferences): WidgetSnapshot = WidgetSnapshot(
            runCatching { JSONObject(prefs.getString("airlog_snapshot_v1", "{}") ?: "{}") }
                .getOrElse { JSONObject() },
        )
    }
}

/** A text style from the generated JSON (F.* in lib/design/tokens/type.dart). */
class TypeSpec(val family: String, val size: Float, val weight: Int, val tracking: Float, val opsz: Float?)

/** The generated tokens: glow recipes, inks and type. Read once per process. */
object WidgetStyle {
    @Volatile private var cache: JSONObject? = null

    fun json(context: Context): JSONObject = cache ?: synchronized(this) {
        cache ?: runCatching {
            context.resources.openRawResource(R.raw.airlog_widget_glows).use {
                JSONObject(it.readBytes().toString(Charsets.UTF_8))
            }
        }.getOrElse {
            Log.w("AirlogWidget", "glow tokens unreadable", it)
            JSONObject()
        }.also { cache = it }
    }

    fun ink(context: Context, name: String, fallback: Int = 0xFFFFFFFF.toInt()): Int =
        json(context).optJSONObject("ink")?.let { if (it.has(name)) it.getLong(name).toInt() else null } ?: fallback

    fun type(context: Context, name: String): TypeSpec {
        val t = json(context).optJSONObject("type")?.optJSONObject(name)
        return TypeSpec(
            family = t?.optString("family", "DM Sans") ?: "DM Sans",
            size = (t?.optDouble("size", 14.0) ?: 14.0).toFloat(),
            weight = t?.optInt("weight", 500) ?: 500,
            tracking = (t?.optDouble("tracking", 0.0) ?: 0.0).toFloat(),
            opsz = t?.let { if (it.isNull("opsz")) null else it.optDouble("opsz").toFloat() },
        )
    }

    /** The recipe a widget paints: "recovery", "today", or a plan state. */
    fun recipe(context: Context, widget: String? = null, planState: String? = null): JSONObject? {
        val j = json(context)
        val name = when {
            planState != null -> j.optJSONObject("plan")?.optString(planState, "m8")
            else -> j.optJSONObject("widgets")?.optString(widget ?: "", "")
        }
        return name?.let { j.optJSONObject("recipes")?.optJSONObject(it) }
    }
}

/** Typefaces from flutter_assets (pubspec fonts), cached by HomeWidgetFonts. */
object WidgetFonts {
    fun of(context: Context, family: String): Typeface =
        HomeWidgetFonts.typeface(context, family)
            ?: HomeWidgetFonts.typeface(context, "DM Sans")
            ?: Typeface.DEFAULT

    /** True when the dot face is in the APK (a fresh clone may lack it). */
    fun hasDots(context: Context): Boolean = HomeWidgetFonts.typeface(context, "Subway Ticker Grid") != null
}

/**
 * One tile drawn at design coordinates ([dw] × [dh] logical px, the PNG's 1×
 * size) into a bitmap of [scale] px per design px.
 */
class TileCanvas(private val context: Context, val dw: Float, val dh: Float, val scale: Float) {
    val bitmap: Bitmap = Bitmap.createBitmap(
        max(1, (dw * scale).toInt()),
        max(1, (dh * scale).toInt()),
        Bitmap.Config.ARGB_8888,
    )
    private val canvas = Canvas(bitmap).also { it.scale(scale, scale) }

    /** The tile outline (tilePath: Figma corner smoothing, R.tile 24.1, .98). */
    val outline: Path = tilePath(RectF(0f, 0f, dw, dh), 24.1f, 0.98f)

    /** GlowRecipe.paint, clipped to the outline, scaled to the tile. */
    fun glow(recipe: JSONObject?) {
        canvas.save()
        canvas.clipPath(outline)
        if (recipe == null) {
            canvas.drawColor(0xFF141414.toInt())
            canvas.restore()
            return
        }
        val rw = recipe.optDouble("w", dw.toDouble()).toFloat()
        val rh = recipe.optDouble("h", dh.toDouble()).toFloat()
        canvas.scale(dw / rw, dh / rh)
        canvas.drawRect(0f, 0f, rw, rh, Paint().apply { color = recipe.optLong("base").toInt() })
        val blobs = recipe.optJSONArray("blobs")
        for (i in 0 until (blobs?.length() ?: 0)) {
            val b = blobs!!.getJSONObject(i)
            val cArr = b.getJSONArray("colors")
            val sArr = b.getJSONArray("stops")
            val colors = IntArray(cArr.length()) { cArr.getLong(it).toInt() }
            val stops = FloatArray(sArr.length()) { sArr.getDouble(it).toFloat() }
            val reach = b.getDouble("reach").toFloat()
            canvas.save()
            canvas.translate(b.getDouble("cx").toFloat(), b.getDouble("cy").toFloat())
            canvas.rotate(Math.toDegrees(b.optDouble("rot", 0.0)).toFloat())
            canvas.scale(b.getDouble("rx").toFloat(), b.getDouble("ry").toFloat())
            val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = RadialGradient(0f, 0f, reach, colors, stops, Shader.TileMode.CLAMP)
            }
            canvas.drawCircle(0f, 0f, reach, p)
            canvas.restore()
        }
        canvas.restore()
    }

    fun paint(spec: TypeSpec, color: Int, weight: Int = spec.weight): TextPaint =
        TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            typeface = WidgetFonts.of(context, spec.family)
            textSize = spec.size
            this.color = color
            letterSpacing = if (spec.size > 0) spec.tracking / spec.size else 0f
            if (spec.family == "DM Sans") {
                setFontVariationSettings("'wght' $weight, 'opsz' ${spec.opsz ?: spec.size}")
            } else {
                fontFeatureSettings = "tnum"
            }
        }

    /** Text with its pen at [x] and alphabetic baseline at [baseline]; returns its advance. */
    fun text(s: String, x: Float, baseline: Float, p: TextPaint, maxWidth: Float? = null): Float {
        val t = if (maxWidth != null) ellipsize(s, p, maxWidth) else s
        canvas.withClip { drawText(t, x, baseline, p) }
        return p.measureText(t)
    }

    fun textCentered(s: String, cx: Float, baseline: Float, p: TextPaint, maxWidth: Float? = null) {
        val t = if (maxWidth != null) ellipsize(s, p, maxWidth) else s
        canvas.withClip { drawText(t, cx - p.measureText(t) / 2f, baseline, p) }
    }

    fun textRight(s: String, right: Float, baseline: Float, p: TextPaint): Float {
        val w = p.measureText(s)
        canvas.withClip { drawText(s, right - w, baseline, p) }
        return w
    }

    /** Up to [lines] lines wrapped at [maxWidth], the last one ellipsised. Returns the last baseline. */
    fun paragraph(s: String, x: Float, baseline: Float, p: TextPaint, maxWidth: Float, lineHeight: Float, lines: Int): Float {
        var rest = s.trim()
        var y = baseline
        for (i in 0 until lines) {
            if (rest.isEmpty()) break
            val n = p.breakText(rest, true, maxWidth, null)
            var cut = if (n >= rest.length) rest.length else rest.lastIndexOf(' ', n).takeIf { it > 0 } ?: n
            if (i == lines - 1) cut = rest.length
            val line = rest.substring(0, cut)
            text(line, x, y, p, maxWidth)
            rest = rest.substring(cut).trim()
            if (rest.isEmpty()) break
            y += lineHeight
        }
        return y
    }

    fun roundRect(l: Float, t: Float, r: Float, b: Float, radius: Float, color: Int) {
        canvas.withClip { drawRoundRect(RectF(l, t, r, b), radius, radius, Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }) }
    }

    fun stroke(path: Path, width: Float, color: Int, round: Boolean = false) {
        canvas.withClip {
            drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = width
                this.color = color
                if (round) strokeCap = Paint.Cap.ROUND
            })
        }
    }

    private fun chipPaint(): TextPaint =
        paint(WidgetStyle.type(context, "micro"), WidgetStyle.ink(context, "chipInk", 0xFFF7B955.toInt()))

    /** The "Sample data" chip's width (SampleDataChip: 10 px side padding). */
    fun sampleChipWidth(): Float = chipPaint().measureText(WidgetCopy.SAMPLE) + 2 * CHIP_PAD_X

    /** The "Sample data" chip (amber wash, micro 600), its left edge at [left]. */
    fun sampleChip(left: Float, top: Float) {
        val p = chipPaint()
        val w = sampleChipWidth()
        val h = CHIP_HEIGHT
        roundRect(left, top, left + w, top + h, h / 2, WidgetStyle.ink(context, "chipBg", 0x29F79009))
        val fm = p.fontMetrics
        val base = top + h / 2 - (fm.ascent + fm.descent) / 2
        canvas.withClip { drawText(WidgetCopy.SAMPLE, left + CHIP_PAD_X, base, p) }
    }

    private inline fun Canvas.withClip(block: Canvas.() -> Unit) {
        save()
        clipPath(outline)
        block()
        restore()
    }

    private fun ellipsize(s: String, p: TextPaint, w: Float): String =
        TextUtils.ellipsize(s, p, w, TextUtils.TruncateAt.END).toString()

    val drawCanvas: Canvas get() = canvas

    companion object {
        const val CHIP_PAD_X = 10f
        const val CHIP_HEIGHT = 21f

        /**
         * tilePath (lib/design/components/tile.dart), ported from
         * figma-squircle (MIT). The circular arc of each corner is centred on
         * the corner's circle and symmetric about its diagonal.
         */
        fun tilePath(r: RectF, radius: Float, smoothing: Float): Path {
            val budget = min(r.width(), r.height()) / 2
            val rad = min(radius, budget)
            if (rad <= 0) return Path().apply { addRect(r, Path.Direction.CW) }
            var s = smoothing
            var p = (1 + s) * rad
            val maxS = budget / rad - 1
            s = min(s, maxS)
            p = min(p, budget)
            fun deg(d: Float) = Math.toRadians(d.toDouble())
            val arcMeasure = 90f * (1 - s)
            val arcLen = (sin(deg(arcMeasure / 2)) * rad * sqrt(2.0)).toFloat()
            val alpha = (90f - arcMeasure) / 2
            val p3ToP4 = (rad * tan(deg(alpha / 2))).toFloat()
            val beta = 45f * s
            val c = (p3ToP4 * cos(deg(beta))).toFloat()
            val d = (c * tan(deg(beta))).toFloat()
            val b = (p - arcLen - c - d) / 3
            val a = 2 * b
            val w = r.width()
            val h = r.height()
            val path = Path()
            fun arc(cx: Float, cy: Float, mid: Float) {
                path.arcTo(RectF(cx - rad, cy - rad, cx + rad, cy + rad), mid - arcMeasure / 2, arcMeasure, false)
            }
            path.moveTo(r.left + w - p, r.top)
            // top right
            path.rCubicTo(a, 0f, a + b, 0f, a + b + c, d)
            arc(r.left + w - rad, r.top + rad, -45f)
            path.rCubicTo(d, c, d, b + c, d, a + b + c)
            path.lineTo(r.left + w, r.top + h - p)
            // bottom right
            path.rCubicTo(0f, a, 0f, a + b, -d, a + b + c)
            arc(r.left + w - rad, r.top + h - rad, 45f)
            path.rCubicTo(-c, d, -(b + c), d, -(a + b + c), d)
            path.lineTo(r.left + p, r.top + h)
            // bottom left
            path.rCubicTo(-a, 0f, -(a + b), 0f, -(a + b + c), -d)
            arc(r.left + rad, r.top + h - rad, 135f)
            path.rCubicTo(-d, -c, -d, -(b + c), -d, -(a + b + c))
            path.lineTo(r.left, r.top + p)
            // top left
            path.rCubicTo(0f, -a, 0f, -(a + b), d, -(a + b + c))
            arc(r.left + rad, r.top + rad, 225f)
            path.rCubicTo(c, -d, b + c, -d, a + b + c, -d)
            path.close()
            return path
        }
    }
}

/** Deep links (WIDGETS_PLAN §6) and the updates every provider shares. */
object AirlogWidgets {
    const val ACTION_OPEN_ROUTE = "app.airlog.airlog.OPEN_ROUTE"
    const val EXTRA_ROUTE = "route"
    const val ACTION_TICK = "app.airlog.airlog.WIDGET_TICK"

    /** Routes a widget may open; MainActivity accepts only these. */
    val ROUTES = listOf("/", "/recovery", "/strain", "/sleep")

    val PROVIDERS: List<Class<out AppWidgetProvider>> = listOf(
        AirlogWidgetProvider::class.java,
        RecoveryWidgetProvider::class.java,
        PlanWidgetProvider::class.java,
    )

    fun open(context: Context, route: String): PendingIntent {
        val i = Intent(context, MainActivity::class.java)
            .setAction(ACTION_OPEN_ROUTE)
            .setData(Uri.parse("airlog://widget$route"))
            .putExtra(EXTRA_ROUTE, route)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            ROUTES.indexOf(route).coerceAtLeast(0) + 100,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Redraws every pinned instance of every Airlog widget. */
    fun updateAll(context: Context) {
        val m = AppWidgetManager.getInstance(context)
        for (cls in PROVIDERS) {
            val ids = m.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isEmpty()) continue
            context.sendBroadcast(
                Intent(context, cls)
                    .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
            )
        }
    }

    /**
     * One inexact, non-wakeup alarm at the next boundary that changes what a
     * widget may show: midnight (stale label) and 05:00 / 18:00 (the plan's
     * phase). RTC (not RTC_WAKEUP): it fires when the phone next wakes, which
     * is when the home screen can be seen. No exact-alarm permission.
     */
    fun scheduleTick(context: Context) {
        val now = LocalDateTime.now()
        val today = now.toLocalDate()
        val next = listOf(
            today.atTime(5, 0), today.atTime(18, 0), today.plusDays(1).atStartOfDay(),
        ).first { it.isAfter(now) }.plusSeconds(30)
        val at = next.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val pi = PendingIntent.getBroadcast(
            context,
            7,
            Intent(context, WidgetTickReceiver::class.java).setAction(ACTION_TICK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        runCatching {
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).set(AlarmManager.RTC, at, pi)
        }
    }
}

/** Receives the boundary alarm and redraws every widget. */
class WidgetTickReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == AirlogWidgets.ACTION_TICK) AirlogWidgets.updateAll(context)
    }
}

/**
 * Base of the Airlog widgets: reads the snapshot, draws a face at the size
 * the launcher gives the instance, and re-arms the boundary alarm.
 */
abstract class AirlogTileProvider : HomeWidgetProvider() {

    /** The design size of the tile (TileSize), in logical px. */
    abstract val designWidth: Float
    abstract val designHeight: Float

    abstract fun draw(context: Context, snap: WidgetSnapshot, tile: TileCanvas): String

    /** Adds click targets to [views] (R.id.widget_root opens [rootRoute]). */
    open fun clicks(context: Context, views: RemoteViews) {}

    abstract val rootRoute: String

    /** The RemoteViews layout: one ImageView (plus click zones, if any). */
    open val layoutId: Int = R.layout.airlog_tile_widget

    /**
     * The top-right corner of a medium tile: the "Sample data" chip in demo
     * mode, and the day shown when it isn't today (QA-08) or "No data yet".
     * Returns the left edge of what it drew.
     */
    protected fun headerRight(
        context: Context,
        tile: TileCanvas,
        snap: WidgetSnapshot,
        right: Float,
        chipTop: Float,
        baseline: Float,
        notes: Boolean = true,
    ): Float {
        var x = right
        if (snap.demo) {
            val w = tile.sampleChipWidth()
            tile.sampleChip(x - w, chipTop)
            x -= w + 8f
        }
        val note = when {
            !notes -> null
            snap.empty -> if (snap.demo) null else WidgetCopy.NO_DATA
            snap.stale -> WidgetCopy.from(snap.date)
            else -> null
        }
        if (note != null) {
            val p = tile.paint(WidgetStyle.type(context, "tileLabel"), WidgetStyle.ink(context, "secondary"))
            x -= tile.textRight(note, x, baseline, p) + 8f
        }
        return x
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in CLOCK_ACTIONS) {
            AirlogWidgets.updateAll(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val snap = WidgetSnapshot.read(widgetData)
        for (id in appWidgetIds) render(context, appWidgetManager, id, snap)
        AirlogWidgets.scheduleTick(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId, WidgetSnapshot.read(HomeWidgetPlugin.getData(context)))
    }

    private fun render(context: Context, m: AppWidgetManager, id: Int, snap: WidgetSnapshot) {
        val views = RemoteViews(context.packageName, layoutId)
        runCatching {
            val tile = TileCanvas(context, designWidth, designHeight, scaleFor(context, m, id))
            val description = draw(context, snap, tile)
            views.setImageViewBitmap(R.id.widget_image, tile.bitmap)
            views.setContentDescription(R.id.widget_image, description)
        }.onFailure { Log.w("AirlogWidget", "draw failed", it) }
        views.setOnClickPendingIntent(R.id.widget_root, AirlogWidgets.open(context, rootRoute))
        clicks(context, views)
        m.updateAppWidget(id, views)
    }

    /**
     * Pixels per design px: the tile fitted (never stretched) into the cell
     * the launcher reports, at most [MAX_DENSITY] px per dp so the bitmap
     * stays well inside the RemoteViews budget (WIDGETS_PLAN §8).
     */
    private fun scaleFor(context: Context, m: AppWidgetManager, id: Int): Float {
        val o = m.getAppWidgetOptions(id)
        val wDp = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0).takeIf { it > 0 }?.toFloat() ?: designWidth
        val hDp = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0).takeIf { it > 0 }?.toFloat() ?: designHeight
        val fit = min(wDp / designWidth, hDp / designHeight).coerceIn(0.4f, 2f)
        val density = context.resources.displayMetrics.density
        return fit * min(density, MAX_DENSITY)
    }

    companion object {
        const val MAX_DENSITY = 2.625f
        val CLOCK_ACTIONS = setOf(
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
        )
    }
}
