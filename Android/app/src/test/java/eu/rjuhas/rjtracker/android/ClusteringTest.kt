package eu.rjuhas.rjtracker.android

import eu.rjuhas.rjtracker.android.data.Pt
import eu.rjuhas.rjtracker.android.ui.common.clusterRoute
import eu.rjuhas.rjtracker.android.ui.common.dropSpikes
import org.junit.Assert.assertEquals
import org.junit.Test

class ClusteringTest {
    private fun pt(northM: Double, ts: Long, acc: Double = 20.0) = Pt(51.43 + northM / 111_000.0, 6.76, acc, ts)

    @Test
    fun consecutiveReportsBecomeOneStay() {
        val stays = clusterRoute(listOf(pt(0.0, 0), pt(10.0, 60), pt(-15.0, 120), pt(2000.0, 900), pt(2010.0, 960)))
        assertEquals(2, stays.size)
        assertEquals(3, stays[0].count)
        assertEquals(120L, stays[0].endTs)
    }

    @Test
    fun singleJumpAwayAndBackIsDroppedFromRoute() {
        val cleaned = dropSpikes(listOf(pt(0.0, 0), pt(1500.0, 120, 300.0), pt(5.0, 240)))
        assertEquals(2, cleaned.size)
    }
}
