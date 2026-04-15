package dev.hegel.conformance.binaries;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.Hegel;
import dev.hegel.Settings;
import dev.hegel.conformance.ConformanceHelper;

/** Conformance binary: generates text strings and writes metrics. */
public class TestText {
  public static void main(String[] args) {
    JsonNode params = ConformanceHelper.parseParams(args);
    int testCases = ConformanceHelper.getTestCases();

    // Build the schema directly from params
    com.fasterxml.jackson.databind.node.ObjectNode schema = dev.hegel.protocol.Cbor.map();
    schema.put("type", "string");
    schema.put("min_size", params.path("min_size").asInt(0));
    if (params.has("max_size") && !params.get("max_size").isNull()) {
      schema.put("max_size", params.get("max_size").asInt());
    }
    if (params.has("codec") && !params.get("codec").isNull()) {
      schema.put("codec", params.get("codec").asText());
    }
    if (params.has("min_codepoint") && !params.get("min_codepoint").isNull()) {
      schema.put("min_codepoint", params.get("min_codepoint").asInt());
    }
    if (params.has("max_codepoint") && !params.get("max_codepoint").isNull()) {
      schema.put("max_codepoint", params.get("max_codepoint").asInt());
    }
    if (params.has("categories") && params.get("categories").isArray()) {
      schema.set("categories", params.get("categories").deepCopy());
    }
    if (params.has("exclude_categories") && params.get("exclude_categories").isArray()) {
      schema.set("exclude_categories", params.get("exclude_categories").deepCopy());
    }
    if (params.has("include_characters") && !params.get("include_characters").isNull()) {
      schema.put("include_characters", params.get("include_characters").asText());
    }
    if (params.has("exclude_characters") && !params.get("exclude_characters").isNull()) {
      schema.put("exclude_characters", params.get("exclude_characters").asText());
    }

    // Use a BasicGenerator directly with the schema
    dev.hegel.BasicGenerator<String> gen =
        new dev.hegel.BasicGenerator<>(
            schema,
            node -> {
              if (node.isTextual()) return node.textValue();
              if (node.isBinary()) {
                try {
                  return new String(node.binaryValue(), java.nio.charset.StandardCharsets.UTF_8);
                } catch (Exception e) {
                  return node.asText();
                }
              }
              return node.asText();
            });

    Hegel.test(
        "text",
        Settings.builder().testCases(testCases).build(),
        tc -> {
          String value = tc.draw(gen);
          ObjectNode metrics = ConformanceHelper.mapper().createObjectNode();
          // Write the codepoints array (as the conformance test expects)
          ArrayNode codepoints = ConformanceHelper.mapper().createArrayNode();
          for (int i = 0; i < value.length(); ) {
            int cp = value.codePointAt(i);
            codepoints.add(cp);
            i += Character.charCount(cp);
          }
          metrics.set("codepoints", codepoints);
          metrics.put("value", value);
          ConformanceHelper.writeMetrics(metrics);
        });
  }
}
