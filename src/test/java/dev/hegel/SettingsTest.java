package dev.hegel;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for Settings and its Builder.
 */
class SettingsTest {

    @AfterEach
    void resetCiOverride() {
        Settings.testCiOverride = null;
    }

    // -----------------------------------------------------------------------
    // Builder methods
    // -----------------------------------------------------------------------

    @Test
    void defaultSettings() {
        Settings s = Settings.defaults();
        assertEquals(100, s.testCases());
    }

    @Test
    void testCasesBuilder() {
        Settings s = Settings.builder().testCases(42).build();
        assertEquals(42, s.testCases());
    }

    @Test
    void seedBuilder() {
        Settings s = Settings.builder().seed(12345L).build();
        assertEquals(12345L, s.seed());
    }

    @Test
    void seedDefaultIsNull() {
        Settings s = Settings.builder().build();
        assertNull(s.seed());
    }

    @Test
    void derandomizeBuilder() {
        Settings s = Settings.builder().derandomize(true).build();
        assertTrue(s.derandomize());
        Settings s2 = Settings.builder().derandomize(false).build();
        assertFalse(s2.derandomize());
    }

    @Test
    void databaseBuilder() {
        Settings s = Settings.builder().database("/tmp/my.db").build();
        assertEquals("/tmp/my.db", s.database());
    }

    @Test
    void databaseEmptyDisables() {
        Settings s = Settings.builder().database("").build();
        assertEquals("", s.database());
    }

    @Test
    void suppressHealthCheckBuilder() {
        Settings s = Settings.builder()
            .suppressHealthCheck("too_slow", "large_base_example")
            .build();
        List<String> checks = s.suppressHealthCheck();
        assertEquals(2, checks.size());
        assertTrue(checks.contains("too_slow"));
        assertTrue(checks.contains("large_base_example"));
    }

    @Test
    void suppressHealthCheckEmpty() {
        Settings s = Settings.builder().build();
        assertTrue(s.suppressHealthCheck().isEmpty());
    }

    // -----------------------------------------------------------------------
    // CI detection
    // -----------------------------------------------------------------------

    @Test
    void isInCiReturnsFalseWhenOverriddenFalse() {
        Settings.testCiOverride = false;
        assertFalse(Settings.isInCI());
    }

    @Test
    void isInCiReturnsTrueWhenOverriddenTrue() {
        Settings.testCiOverride = true;
        assertTrue(Settings.isInCI());
    }

    @Test
    void ciOverrideAffectsBuilder() {
        Settings.testCiOverride = true;
        Settings s = Settings.builder().build();
        assertTrue(s.derandomize());
        assertEquals("", s.database()); // CI disables database
    }

    @Test
    void nonCiOverrideAffectsBuilder() {
        Settings.testCiOverride = false;
        Settings s = Settings.builder().build();
        assertFalse(s.derandomize());
        assertNull(s.database());
    }

    // -----------------------------------------------------------------------
    // isInCIFromEnv injectable overload (Settings.java:144)
    // -----------------------------------------------------------------------

    @Test
    void isInCIFromEnvReturnsTrueWhenVarSet() {
        // The injected env lookup returns non-null for any var → return true (line 144)
        assertTrue(Settings.isInCIFromEnv(v -> "true"));
    }

    @Test
    void isInCIFromEnvReturnsFalseWhenNoVarsSet() {
        // The injected env lookup always returns null → return false
        assertFalse(Settings.isInCIFromEnv(v -> null));
    }
}
