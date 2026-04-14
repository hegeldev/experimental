package dev.hegel;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Configuration for a Hegel test run.
 *
 * <p>Obtain via the builder: {@code Settings.builder().testCases(200).build()}.
 * For default settings use {@link #defaults()}.
 */
public final class Settings {

    /** Number of test cases to run. Default: 100. */
    private final int testCases;

    /** Random seed, or {@code null} to use Hypothesis's default. */
    private final Long seed;

    /** Output verbosity. Default: {@link Verbosity#NORMAL}. */
    private final Verbosity verbosity;

    /** When true, use the database for deterministic replay. Default: auto (true in CI). */
    private final boolean derandomize;

    /** Database path, or {@code null} for default, or empty string to disable. */
    private final String database;

    /** Health checks to suppress. */
    private final List<String> suppressHealthCheck;

    private Settings(Builder b) {
        this.testCases = b.testCases;
        this.seed = b.seed;
        this.verbosity = b.verbosity;
        this.derandomize = b.derandomize;
        this.database = b.database;
        this.suppressHealthCheck = Collections.unmodifiableList(new ArrayList<>(b.suppressHealthCheck));
    }

    // -----------------------------------------------------------------------
    // Accessors
    // -----------------------------------------------------------------------

    public int testCases() { return testCases; }
    public Long seed() { return seed; }
    public Verbosity verbosity() { return verbosity; }
    public boolean derandomize() { return derandomize; }
    public String database() { return database; }
    public List<String> suppressHealthCheck() { return suppressHealthCheck; }

    // -----------------------------------------------------------------------
    // Factory
    // -----------------------------------------------------------------------

    /** Return default settings, auto-detecting CI environment. */
    public static Settings defaults() {
        return builder().build();
    }

    public static Builder builder() {
        return new Builder();
    }

    // -----------------------------------------------------------------------
    // Builder
    // -----------------------------------------------------------------------

    public static final class Builder {

        private int testCases = 100;
        private Long seed = null;
        private Verbosity verbosity = Verbosity.NORMAL;
        private boolean derandomize = isInCI();
        private String database = isInCI() ? "" : null; // "" means disabled
        private List<String> suppressHealthCheck = new ArrayList<>();

        private Builder() {}

        public Builder testCases(int testCases) {
            this.testCases = testCases;
            return this;
        }

        public Builder seed(long seed) {
            this.seed = seed;
            return this;
        }

        public Builder verbosity(Verbosity verbosity) {
            this.verbosity = verbosity;
            return this;
        }

        public Builder derandomize(boolean derandomize) {
            this.derandomize = derandomize;
            return this;
        }

        /** Set the database path. Pass empty string to disable. */
        public Builder database(String database) {
            this.database = database;
            return this;
        }

        public Builder suppressHealthCheck(String... checks) {
            for (String check : checks) {
                this.suppressHealthCheck.add(check);
            }
            return this;
        }

        public Settings build() {
            return new Settings(this);
        }
    }

    // -----------------------------------------------------------------------
    // CI detection
    // -----------------------------------------------------------------------

    private static boolean isInCI() {
        String[] ciVars = {
            "CI", "BITBUCKET_COMMIT", "BUILDKITE", "CIRCLECI",
            "CIRRUS_CI", "CODEBUILD_BUILD_ID", "GITHUB_ACTIONS",
            "GITLAB_CI", "HEROKU_TEST_RUN_ID", "TEAMCITY_VERSION",
            "TF_BUILD"
        };
        for (String var : ciVars) {
            if (System.getenv(var) != null) return true;
        }
        return false;
    }

    // -----------------------------------------------------------------------
    // Verbosity enum
    // -----------------------------------------------------------------------

    public enum Verbosity {
        QUIET("quiet"),
        NORMAL("normal"),
        VERBOSE("verbose"),
        DEBUG("debug");

        private final String value;

        Verbosity(String value) { this.value = value; }

        public String value() { return value; }
    }
}
