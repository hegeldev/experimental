package dev.hegel.conformance.binaries;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.Hegel;
import dev.hegel.Settings;
import dev.hegel.conformance.ConformanceHelper;
import dev.hegel.generators.Generators;

/** Conformance binary: generates integer values and writes metrics. */
public class TestIntegers {
    public static void main(String[] args) {
        JsonNode params = ConformanceHelper.parseParams(args);
        int testCases = ConformanceHelper.getTestCases();

        // Parse optional bounds
        Long minValue = params.has("min_value") && !params.get("min_value").isNull()
                ? params.get("min_value").longValue() : null;
        Long maxValue = params.has("max_value") && !params.get("max_value").isNull()
                ? params.get("max_value").longValue() : null;

        var gen = Generators.integers();
        if (minValue != null) gen = gen.minValue(minValue);
        if (maxValue != null) gen = gen.maxValue(maxValue);

        final var finalGen = gen;
        Hegel.test("integers", Settings.builder().testCases(testCases).build(), tc -> {
            long value = tc.draw(finalGen);
            ObjectNode metrics = ConformanceHelper.mapper().createObjectNode();
            metrics.put("value", value);
            ConformanceHelper.writeMetrics(metrics);
        });
    }
}
