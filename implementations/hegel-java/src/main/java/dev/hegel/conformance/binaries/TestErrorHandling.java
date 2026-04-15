package dev.hegel.conformance.binaries;

import static dev.hegel.generators.Generators.integers;

import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.Hegel;
import dev.hegel.Settings;
import dev.hegel.conformance.ConformanceHelper;

/**
 * Conformance binary for error handling tests.
 *
 * <p>Used for: stop_test_on_generate, stop_test_on_mark_complete, stop_test_on_collection_more,
 * stop_test_on_new_collection, error_response, empty_test.
 *
 * <p>The binary runs a simple integer generator test. The HEGEL_PROTOCOL_TEST_MODE env var is set
 * by the conformance framework to inject specific error conditions. The binary must exit cleanly
 * (exit code 0).
 */
public class TestErrorHandling {
  public static void main(String[] args) {
    ConformanceHelper.parseParams(args);
    int testCases = ConformanceHelper.getTestCases();

    try {
      Hegel.test(
          "error_handling",
          Settings.builder().testCases(testCases).build(),
          tc -> {
            long value = tc.draw(integers());
            ObjectNode metrics = ConformanceHelper.mapper().createObjectNode();
            metrics.put("value", value);
            ConformanceHelper.writeMetrics(metrics);
          });
    } catch (Exception e) {
      // Error handling tests expect the binary to exit cleanly
      // even when the server injects errors. Exit with 0.
      System.err.println("Error handling test caught: " + e.getMessage());
    }
    System.exit(0);
  }
}
