package dev.hegel.conformance.binaries;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.Generator;
import dev.hegel.Hegel;
import dev.hegel.Settings;
import dev.hegel.conformance.ConformanceHelper;
import dev.hegel.generators.Generators;

import java.util.List;

/** Conformance binary: generates lists of integers and writes metrics.
 *
 * <p>Writes: {@code size}, {@code min_element}, {@code max_element}.
 */
public class TestLists {
    public static void main(String[] args) {
        JsonNode params = ConformanceHelper.parseParams(args);
        int testCases = ConformanceHelper.getTestCases();

        int minSize = params.path("min_size").asInt(0);
        Integer maxSize = params.has("max_size") && !params.get("max_size").isNull()
                ? params.get("max_size").asInt() : null;
        Long minValue = params.has("min_value") && !params.get("min_value").isNull()
                ? params.get("min_value").longValue() : null;
        Long maxValue = params.has("max_value") && !params.get("max_value").isNull()
                ? params.get("max_value").longValue() : null;

        // Build the element generator
        var elemGen = Generators.integers();
        if (minValue != null) elemGen = elemGen.minValue(minValue);
        if (maxValue != null) elemGen = elemGen.maxValue(maxValue);

        var listGen = Generators.lists(elemGen).minSize(minSize);
        if (maxSize != null) listGen = listGen.maxSize(maxSize);

        final var finalListGen = listGen;

        Hegel.test("lists", Settings.builder().testCases(testCases).build(), tc -> {
            List<Long> elements = tc.draw(finalListGen);
            int size = elements.size();

            ObjectNode metrics = ConformanceHelper.mapper().createObjectNode();
            metrics.put("size", size);

            if (size > 0) {
                long minElem = elements.stream().mapToLong(Long::longValue).min().orElse(0);
                long maxElem = elements.stream().mapToLong(Long::longValue).max().orElse(0);
                metrics.put("min_element", minElem);
                metrics.put("max_element", maxElem);
            }

            ConformanceHelper.writeMetrics(metrics);
        });
    }
}
