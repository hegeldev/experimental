package dev.hegel.conformance.binaries;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.Generator;
import dev.hegel.Hegel;
import dev.hegel.Settings;
import dev.hegel.conformance.ConformanceHelper;
import dev.hegel.generators.Generators;

import java.util.Map;

/** Conformance binary: generates maps (dicts) and writes metrics.
 *
 * <p>Supports two modes:
 * <ul>
 *   <li>{@code basic}: Uses the basic (schema-composition) path.</li>
 *   <li>{@code non_basic}: Forces the compositional path by using a no-op filter.</li>
 * </ul>
 */
public class TestMaps {
    public static void main(String[] args) {
        JsonNode params = ConformanceHelper.parseParams(args);
        int testCases = ConformanceHelper.getTestCases();

        int minSize = params.path("min_size").asInt(0);
        int maxSize = params.path("max_size").asInt(10);
        String keyType = params.path("key_type").asText("integer");
        long minKey = params.path("min_key").asLong(Long.MIN_VALUE);
        long maxKey = params.path("max_key").asLong(Long.MAX_VALUE);
        long minValue = params.path("min_value").asLong(Long.MIN_VALUE);
        long maxValue = params.path("max_value").asLong(Long.MAX_VALUE);
        String mode = params.path("mode").asText("basic");

        // Build value generator
        var valueGen = Generators.integers();
        valueGen = valueGen.minValue(minValue).maxValue(maxValue);
        Generator<Long> valueGenerator = "non_basic".equals(mode)
                ? valueGen.filter(v -> true)
                : valueGen;

        Hegel.test("maps", Settings.builder().testCases(testCases).build(), tc -> {
            ObjectNode metrics = ConformanceHelper.mapper().createObjectNode();

            if ("string".equals(keyType)) {
                // String keys
                var keyGen = Generators.text().minSize(1).maxSize(10).ascii();
                Generator<String> keyGenerator = "non_basic".equals(mode)
                        ? keyGen.filter(s -> true)
                        : keyGen;
                var mapGen = Generators.maps(keyGenerator, valueGenerator)
                        .minSize(minSize).maxSize(maxSize);
                Map<String, Long> map = tc.draw(mapGen);

                metrics.put("size", map.size());
                if (!map.isEmpty()) {
                    metrics.put("min_value", map.values().stream().mapToLong(Long::longValue).min().orElse(0));
                    metrics.put("max_value", map.values().stream().mapToLong(Long::longValue).max().orElse(0));
                } else {
                    metrics.put("min_value", 0);
                    metrics.put("max_value", 0);
                }
            } else {
                // Integer keys
                var keyGen = Generators.integers().minValue(minKey).maxValue(maxKey);
                Generator<Long> keyGenerator = "non_basic".equals(mode)
                        ? keyGen.filter(k -> true)
                        : keyGen;
                var mapGen = Generators.maps(keyGenerator, valueGenerator)
                        .minSize(minSize).maxSize(maxSize);
                Map<Long, Long> map = tc.draw(mapGen);

                metrics.put("size", map.size());
                if (!map.isEmpty()) {
                    metrics.put("min_key", map.keySet().stream().mapToLong(Long::longValue).min().orElse(0));
                    metrics.put("max_key", map.keySet().stream().mapToLong(Long::longValue).max().orElse(0));
                    metrics.put("min_value", map.values().stream().mapToLong(Long::longValue).min().orElse(0));
                    metrics.put("max_value", map.values().stream().mapToLong(Long::longValue).max().orElse(0));
                } else {
                    metrics.put("min_key", 0);
                    metrics.put("max_key", 0);
                    metrics.put("min_value", 0);
                    metrics.put("max_value", 0);
                }
            }

            ConformanceHelper.writeMetrics(metrics);
        });
    }
}
