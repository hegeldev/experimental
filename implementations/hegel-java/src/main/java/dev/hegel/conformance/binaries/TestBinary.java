package dev.hegel.conformance.binaries;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.Hegel;
import dev.hegel.Settings;
import dev.hegel.conformance.ConformanceHelper;
import dev.hegel.generators.Generators;

/** Conformance binary: generates binary data and writes metrics. */
public class TestBinary {
  public static void main(String[] args) {
    JsonNode params = ConformanceHelper.parseParams(args);
    int testCases = ConformanceHelper.getTestCases();

    var gen = Generators.binary();
    if (params.has("min_size") && !params.get("min_size").isNull()) {
      gen = gen.minSize(params.get("min_size").intValue());
    }
    if (params.has("max_size") && !params.get("max_size").isNull()) {
      gen = gen.maxSize(params.get("max_size").intValue());
    }

    final var finalGen = gen;
    Hegel.test(
        "binary",
        Settings.builder().testCases(testCases).build(),
        tc -> {
          byte[] value = tc.draw(finalGen);
          ObjectNode metrics = ConformanceHelper.mapper().createObjectNode();
          metrics.put("length", value.length);
          ConformanceHelper.writeMetrics(metrics);
        });
  }
}
