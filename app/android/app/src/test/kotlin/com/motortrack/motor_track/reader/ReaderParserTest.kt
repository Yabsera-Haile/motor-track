package com.motortrack.motor_track.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderParserTest {
    // SmsTemplate.mtnDefault.regexSource from the Dart side; sms_template_test.dart pins the same string.
    private val mtnRegex =
        "^\\s*\\s*You\\s*have\\s*received\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)\\s*RWF\\s*from\\s*(.+?)\\s*\\(\\s*([*0-9][*0-9 ]*?)\\s*\\)" +
            "\\s*at\\s*(\\d{4}-\\d{2}-\\d{2}\\s+\\d{1,2}:\\d{2}(?::\\d{2})?)\\s*\\.\\s*Balance:\\s*(?:.*?)\\s*RWF\\.\\s*FT\\s*Id:\\s*([A-Za-z0-9]+)\\s*\\.\\s*"
    private val parser = ReaderParser(mtnRegex, listOf("amount", "name", "phone", "datetime", "txid"))

    @Test
    fun readsTheRealSample() {
        val p = parser.parse(
            "You have received 6000 RWF from Xxx MUGABO (*********123) at 2026-11-02 19:57:24 . Balance:25000 RWF. FT Id: 30012345678.",
        )!!
        assertEquals(6000, p.amount)
        assertEquals("Xxx MUGABO", p.name)
        assertEquals("*********123", p.phone)
        assertEquals("30012345678", p.txId)
        // 19:57:24 in Kigali is 17:57:24 UTC.
        assertEquals(1793642244000L, p.paidAtMillis)
    }

    @Test
    fun handlesSeparatorsSpacingAndLineBreaks() {
        val p = parser.parse(
            "You have received  12,000 RWF from Jean Claude  NIYONSABA (*********021)\nat 2026-11-03 07:05:00. Balance:28,917 RWF.FT Id:31670000001.",
        )!!
        assertEquals(12000, p.amount)
        assertEquals("Jean Claude NIYONSABA", p.name)
        assertEquals("31670000001", p.txId)
    }

    @Test
    fun ignoresOtherMessages() {
        assertNull(parser.parse("You have transferred 5000 RWF to Grace (*********777) at 2026-11-03 10:00:00. Fee: 100 RWF."))
        assertNull(parser.parse("Your bundle balance is 1.2 GB"))
    }

    @Test
    fun spotsIncomingMoneyAndNormalizesNames() {
        assertTrue(ReaderParser.looksLikeIncoming("Y'ello! You have received 6000 RWF from ..."))
        assertFalse(ReaderParser.looksLikeIncoming("Your bundle is active"))
        assertEquals("XXX MUGABO", ReaderParser.normName("  xxx   Mugabo "))
    }
}
