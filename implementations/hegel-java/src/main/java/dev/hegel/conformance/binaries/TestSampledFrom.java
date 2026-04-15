package dev.hegel.conformance.binaries;

import static dev.hegel.generators.Generators.sampledFrom;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.Hegel;
import dev.hegel.Settings;
import dev.hegel.conformance.ConformanceHelper;
import java.util.ArrayList;
import java.util.List;

/** Conformance binary: samples from a list of options and writes metrics. */
public class TestSampledFrom {
  public static void main(String[] args) {
    JsonNode params = ConformanceHelper.parseParams(args);
    int testCases = ConformanceHelper.getTestCases();

    List<Long> options = new ArrayList<>();
    for (JsonNode opt : params.path("options")) {
      options.add(opt.longValue());
    }
    if (options.isEmpty()) {
      System.err.println("options must not be empty");
      System.exit(1);
    }

    final var gen = sampledFrom(options);
    Hegel.test(
        "sampled_from",
        Settings.builder().testCases(testCases).build(),
        tc -> {
          long value = tc.draw(gen);
          ObjectNode metrics = ConformanceHelper.mapper().createObjectNode();
          metrics.put("value", value);
          ConformanceHelper.writeMetrics(metrics);
        });
  }
}
