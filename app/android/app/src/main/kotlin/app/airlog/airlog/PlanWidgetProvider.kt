package app.airlog.airlog

import android.content.Context

/**
 * "Today plan" (medium, 348 × 164): the PlanTile vocabulary
 * (lib/design/tiles/plan_tile.dart) cut to one panel: the basis eyebrow,
 * the headline, and the first action with its why. Every string comes from
 * TodayPlanner via the snapshot; the glow follows PlanTile.glowFor(state).
 * After the planner's next phase boundary (plan.until) the action was
 * advice for the other phase, so it is replaced by "Open Airlog for the
 * latest plan". Opens Today, where the plan lives.
 */
class PlanWidgetProvider : AirlogTileProvider() {
    override val designWidth = 348f
    override val designHeight = 164f
    override val rootRoute = "/"

    override fun draw(context: Context, snap: WidgetSnapshot, tile: TileCanvas): String {
        val plan = snap.plan
        val state = plan?.optString("state", "noData") ?: "noData"
        tile.glow(WidgetStyle.recipe(context, planState = state))
        val left = 20f
        val width = 308f
        val headerLeft = headerRight(context, tile, snap, right = 328f, baseline = 30f, notes = false)

        val eyebrow = listOf(
            if (snap.stale) WidgetCopy.from(snap.date) else "",
            plan?.optString("eyebrow", "") ?: "",
        ).filter { it.isNotEmpty() }.joinToString(" · ")
        val headline = plan?.optString("headline", "")?.ifEmpty { null } ?: WidgetCopy.START
        val expired = plan != null && System.currentTimeMillis() >= plan.optLong("until", Long.MAX_VALUE)
        val action: String?
        val why: String?
        when {
            plan == null -> { action = null; why = null }
            expired -> { action = WidgetCopy.LATEST_PLAN; why = null }
            plan.isNull("action") -> { action = WidgetCopy.NOTHING; why = null }
            else -> { action = plan.optString("action"); why = plan.optString("why", "").ifEmpty { null } }
        }

        var y = 30f
        if (eyebrow.isNotEmpty()) {
            val p = tile.paint(WidgetStyle.type(context, "tileMicro"), WidgetStyle.ink(context, "unit"))
            tile.text(eyebrow, left, y, p, maxWidth = headerLeft - left)
            y += 34f
        } else {
            y += 20f
        }
        tile.text(headline, left, y, tile.paint(WidgetStyle.type(context, "tileHeadline"), WidgetStyle.ink(context, "primary")), maxWidth = if (eyebrow.isEmpty()) headerLeft - left else width)
        if (action != null) {
            y += 30f
            val ink = if (action == WidgetCopy.NOTHING || action == WidgetCopy.LATEST_PLAN) "secondary" else "primary"
            tile.text(action, left, y, tile.paint(WidgetStyle.type(context, "tileBody"), WidgetStyle.ink(context, ink)), maxWidth = width)
        }
        if (why != null) {
            val p = tile.paint(WidgetStyle.type(context, "tileLabel"), WidgetStyle.ink(context, "secondary"), weight = 400)
            tile.paragraph(why, left, y + 18f, p, width, lineHeight = 15.6f, lines = if (eyebrow.isEmpty()) 3 else 2)
        }

        return listOfNotNull(
            "Airlog plan",
            eyebrow.ifEmpty { null },
            headline,
            action,
            why,
        ).joinToString(". ")
    }
}
