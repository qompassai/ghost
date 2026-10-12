package ai.qompass.ghost.pgp

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Recipient address normalization: the picker, the store, and the send
 * gate must all agree on what "the same recipient" means, or a key
 * imported for one spelling silently misses at send time.
 */
class RecipientKeyStoreTest {

    @Test
    fun plainAddressIsUnchanged() {
        assertEquals("alice@ghost.onion", normalizeRecipientEmail("alice@ghost.onion"))
    }

    @Test
    fun surroundingWhitespaceIsTrimmed() {
        assertEquals("alice@ghost.onion", normalizeRecipientEmail("  alice@ghost.onion  "))
    }

    @Test
    fun caseIsFolded() {
        assertEquals("alice@ghost.onion", normalizeRecipientEmail("Alice@Ghost.ONION"))
    }

    @Test
    fun plusTagSurvivesNormalization() {
        assertEquals(
            "alice+lists@ghost.onion",
            normalizeRecipientEmail(" Alice+Lists@Ghost.Onion ")
        )
    }

    @Test
    fun blankNormalizesToBlank() {
        assertEquals("", normalizeRecipientEmail("   "))
        assertEquals("", normalizeRecipientEmail(""))
    }
}
