package dev.hegel.conformance;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;

/**
 * Helper utilities for Hegel conformance test binaries.
 *
 * <p>Conformance test binaries receive JSON params as a command-line argument,
 * run a Hegel test, and write metrics (one JSON line per test case) to
 * {@code CONFORMANCE_METRICS_FILE}.
 */
public final class ConformanceHelper {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static PrintWriter metricsWriter;

    private ConformanceHelper() {}

    /**
     * Parse the JSON params argument from {@code args[0]}.
     * Returns an empty ObjectNode if args is empty or params is empty.
     */
    public static JsonNode parseParams(String[] args) {
        if (args.length == 0 || args[0].isBlank() || args[0].equals("{}")) {
            return MAPPER.createObjectNode();
        }
        try {
            return MAPPER.readTree(args[0]);
        } catch (IOException e) {
            System.err.println("Failed to parse params: " + e.getMessage());
            System.exit(1);
            throw new AssertionError("unreachable");
        }
    }

    /**
     * Return the number of test cases from the {@code CONFORMANCE_TEST_CASES} env var.
     * Defaults to 50.
     */
    public static int getTestCases() {
        String val = System.getenv("CONFORMANCE_TEST_CASES");
        if (val == null || val.isBlank()) return 50;
        try {
            return Integer.parseInt(val.trim());
        } catch (NumberFormatException e) {
            return 50;
        }
    }

    /**
     * Write a metrics object to the metrics file (one JSON line).
     * Must be called inside the Hegel test body for each test case.
     */
    public static void writeMetrics(ObjectNode metrics) {
        if (metricsWriter == null) {
            String metricsFile = System.getenv("CONFORMANCE_METRICS_FILE");
            if (metricsFile == null || metricsFile.isBlank()) {
                System.err.println("CONFORMANCE_METRICS_FILE not set");
                System.exit(1);
            }
            try {
                metricsWriter = new PrintWriter(new FileWriter(metricsFile, true));
            } catch (IOException e) {
                System.err.println("Cannot open metrics file: " + e.getMessage());
                System.exit(1);
            }
        }
        try {
            metricsWriter.println(MAPPER.writeValueAsString(metrics));
            metricsWriter.flush();
        } catch (IOException e) {
            System.err.println("Failed to write metrics: " + e.getMessage());
            System.exit(1);
        }
    }

    public static ObjectMapper mapper() {
        return MAPPER;
    }
}
