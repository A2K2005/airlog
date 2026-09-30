package app.airlog.airlog

import android.content.Context
import android.widget.RemoteViews

/**
 * "Today" (medium, 348 × 164): Recovery %, Strain and Sleep performance on
 * three plates, in the Medium/19 layout (its macros relabelled with measured
 * metrics, PRODUCT_PLAN §7) on the fitted glow m19. This is the original
 * Airlog widget, migrated: the class name is kept so widgets pinned before
 * the upgrade keep working. Each plate opens its own screen.
 * The provider pattern follows OpenStrap/edge OpenStrapWidgetProvider.kt
 * (MIT, see third_party/edge/LICENSE); layout and copy are ours.
 */
class AirlogWidgetProvider : AirlogTileProvider() {
    override val designWidth = 348f
    override val designHeight = 164f
    override val rootRoute = "/"
    override val layoutId = R.layout.airlog_today_widget

    override fun draw(context: Context, snap: WidgetSnapshot, tile: TileCanvas): String {
        tile.glow(WidgetStyle.recipe(context, widget = "today"))
        val primary = WidgetStyle.ink(context, "primary")
        tile.text("Today", 20f, 36f, tile.paint(WidgetStyle.type(context, "tileTitle"), primary))
        headerRight(context, tile, snap, right = 328f, chipTop = 20f, baseline = 35f)

        val label = tile.paint(WidgetStyle.type(context, "tileLabel"), primary)
        val dots = tile.paint(WidgetStyle.type(context, "dot32"), primary)
        val unit = tile.paint(WidgetStyle.type(context, "tileLabel"), WidgetStyle.ink(context, "unitSoft"), weight = 400)
        val plate = WidgetStyle.ink(context, "plate")
        val slots = listOf(
            Triple("Recovery", snap.dots("recovery"), "%"),
            Triple("Strain", snap.dots("strain"), ""),
            Triple("Sleep", snap.dots("sleep"), "%"),
        )
        // Medium/19's plates, measured from the PNG: x 20 / 125.5 / 231,
        // 97 × 90 at y 54, radius 10, white 9 %; label and value 8 px in.
        for ((i, x) in listOf(20f, 125.5f, 231f).withIndex()) {
            val (name, value, u) = slots[i]
            tile.roundRect(x, 54f, x + 97f, 144f, 10f, plate)
            tile.text(name, x + 8f, 74f, label, maxWidth = 81f)
            val adv = tile.text(value, x + 8f, 128f, dots, maxWidth = 81f)
            if (u.isNotEmpty() && value != WidgetCopy.MISSING) tile.text(u, x + 8f + adv + 2f, 128f, unit)
        }

        return listOfNotNull(
            "Airlog Today",
            if (snap.demo) WidgetCopy.SAMPLE else null,
            if (snap.stale) WidgetCopy.from(snap.date) else null,
            "Recovery " + (snap.recovery?.let { "$it percent, ${snap.recStatus}" } ?: snap.recStatus),
            "Strain " + snap.dots("strain").let { if (it == WidgetCopy.MISSING) "no score" else "$it of 21" },
            "Sleep " + snap.dots("sleep").let { if (it == WidgetCopy.MISSING) "no data" else "$it percent ${snap.sleepText}".trim() },
        ).joinToString(". ")
    }

    override fun clicks(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.zone_recovery, AirlogWidgets.open(context, "/recovery"))
        views.setOnClickPendingIntent(R.id.zone_strain, AirlogWidgets.open(context, "/strain"))
        views.setOnClickPendingIntent(R.id.zone_sleep, AirlogWidgets.open(context, "/sleep"))
    }
}
