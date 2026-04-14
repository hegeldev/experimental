package dev.hegel.conformance.binaries;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.Hegel;
import dev.hegel.Settings;
import dev.hegel.conformance.ConformanceHelper;
import dev.hegel.generators.Generators;

/** Conformance binary: generates float values and writes metrics. */
public class TestFloats {
    public static void main(String[] args) {
        JsonNode params = ConformanceHelper.parseParams(args);
        int testCases = ConformanceHelper.getTestCases();

        var gen = Generators.floats();

        if (params.has("min_value") && !params.get("min_value").isNull()) {
            gen = gen.minValue(params.get("min_value").doubleValue());
        }
        if (params.has("max_value") && !params.get("max_value").isNull()) {
            gen = gen.maxValue(params.get("max_value").doubleValue());
        }
        if (params.has("exclude_min") && !params.get("exclude_min").isNull()) {
            gen = gen.excludeMin(params.get("exclude_min").booleanValue());
        }
        if (params.has("exclude_max") && !params.get("exclude_max").isNull()) {
            gen = gen.excludeMax(params.get("exclude_max").booleanValue());
        }
        // allow_nan/allow_infinity: null means use library defaults
        if (params.has("allow_nan") && !params.get("allow_nan").isNull()) {
            gen = gen.allowNan(params.get("allow_nan").booleanValue());
        }
        if (params.has("allow_infinity") && !params.get("allow_infinity").isNull()) {
            gen = gen.allowInfinity(params.get("allow_infinity").booleanValue());
        }

        final var finalGen = gen;
        Hegel.test("floats", Settings.builder().testCases(testCases).build(), tc -> {
            double value = tc.draw(finalGen);
            ObjectNode metrics = ConformanceHelper.mapper().createObjectNode();
            if (Double.isNaN(value)) {
                metrics.put("is_nan", true);
                metrics.put("value", 0.0); // placeholder
            } else if (Double.isInfinite(value)) {
                metrics.put("is_infinite", true);
                metrics.put("value", value > 0 ? Double.MAX_VALUE : -Double.MAX_VALUE);
            } else {
                metrics.put("value", value);
            }
            ConformanceHelper.writeMetrics(metrics);
        });
    }
}
