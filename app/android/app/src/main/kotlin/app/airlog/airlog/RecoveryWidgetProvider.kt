package app.airlog.airlog

import android.content.Context
import android.graphics.Path
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * "Recovery" (small, 164 × 218): RingScoreTile (Small/5,
 * lib/design/tiles/score_tiles.dart) with today's Recovery %. The ring's
 * squiggle sits at the score; the caption is the status word Today's
 * Recovery tile uses (Good / Fair / Low, Learning, No data) plus the
 * score's basis. Opens /recovery.
 */
class RecoveryWidgetProvider : AirlogTileProvider() {
    override val designWidth = 164f
    override val designHeight = 218f
    override val rootRoute = "/recovery"

    override fun draw(context: Context, snap: WidgetSnapshot, tile: TileCanvas): String {
        tile.glow(WidgetStyle.recipe(context, widget = "recovery"))
        val primary = WidgetStyle.ink(context, "primary")
        tile.textCentered("Recovery", 82f, 36f, tile.paint(WidgetStyle.type(context, "tileTitle"), primary), maxWidth = 136f)

        // _RingPainter: centre (82.5, 113.5), r 59.2, 2 px, C.ring.
        val cx = 82.5f
        val cy = 113.5f
        val r = 59.2f
        tile.stroke(Path().apply { addCircle(cx, cy, r, Path.Direction.CW) }, 2f, WidgetStyle.ink(context, "ring"))
        snap.recovery?.let { score ->
            // A short wave riding the ring, ending at the value.
            val end = -90.0 + 360.0 * (score / 100.0).coerceIn(0.0, 1.0)
            val span = 34.0
            val wave = Path()
            for (i in 0..24) {
                val t = i / 24.0
                val a = Math.toRadians(end - span + span * t)
                val rr = r + 4.5 * sin(t * 2 * PI)
                val x = (cx + cos(a) * rr).toFloat()
                val y = (cy + sin(a) * rr).toFloat()
                if (i == 0) wave.moveTo(x, y) else wave.lineTo(x, y)
            }
            tile.stroke(wave, 2f, WidgetStyle.ink(context, "lime"), round = true)
        }

        val value = snap.dots("recovery")
        tile.textCentered(value, 82f, 130f, tile.paint(WidgetStyle.type(context, "dot40"), primary))

        val caption = listOf(
            if (snap.stale) WidgetCopy.from(snap.date) else "",
            if (snap.empty) WidgetCopy.NO_DATA else snap.recStatus,
            snap.recBasis,
        ).filter { it.isNotEmpty() }.joinToString(" · ")
        val micro = tile.paint(WidgetStyle.type(context, "tileMicro"), WidgetStyle.ink(context, "tertiary"))
        tile.textCentered(caption, 82f, 194.75f, micro, maxWidth = 136f)

        return listOfNotNull(
            "Airlog Recovery",
            snap.recovery?.let { "$it percent" },
            caption.ifEmpty { null },
        ).joinToString(". ")
    }
}
