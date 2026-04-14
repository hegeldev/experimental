package dev.hegel.conformance.binaries;

import static dev.hegel.generators.Generators.booleans;

import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.Hegel;
import dev.hegel.Settings;
import dev.hegel.conformance.ConformanceHelper;

/** Conformance binary: generates boolean values and writes metrics. */
public class TestBooleans {
  public static void main(String[] args) {
    ConformanceHelper.parseParams(args); // no params needed
    int testCases = ConformanceHelper.getTestCases();

    Hegel.test(
        "booleans",
        Settings.builder().testCases(testCases).build(),
        tc -> {
          boolean value = tc.draw(booleans());
          ObjectNode metrics = ConformanceHelper.mapper().createObjectNode();
          metrics.put("value", value);
          ConformanceHelper.writeMetrics(metrics);
        });
  }
}
