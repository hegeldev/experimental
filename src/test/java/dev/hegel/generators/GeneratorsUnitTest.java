package dev.hegel.generators;

import com.fasterxml.jackson.databind.node.BinaryNode;
import com.fasterxml.jackson.databind.node.IntNode;
import com.fasterxml.jackson.databind.node.TextNode;
import dev.hegel.protocol.Cbor;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for package-private utilities in Generators.
 */
class GeneratorsUnitTest {

    // -----------------------------------------------------------------------
    // nodeToText()
    // -----------------------------------------------------------------------

    @Test
    void nodeToTextTextual() {
        String result = Generators.nodeToText(TextNode.valueOf("hello"));
        assertEquals("hello", result);
    }

    @Test
    void nodeToTextBinary() {
        byte[] utf8Bytes = "world".getBytes(StandardCharsets.UTF_8);
        String result = Generators.nodeToText(BinaryNode.valueOf(utf8Bytes));
        assertEquals("world", result);
    }

    @Test
    void nodeToTextFallback() {
        // An integer node: neither textual nor binary — should call asText()
        String result = Generators.nodeToText(IntNode.valueOf(42));
        assertEquals("42", result);
    }

    @Test
    void nodeToTextNull() {
        // Null node: asText() returns "null"
        String result = Generators.nodeToText(Cbor.mapper().nullNode());
        assertEquals("null", result);
    }

    @Test
    void nodeToTextEmptyBinary() {
        String result = Generators.nodeToText(BinaryNode.valueOf(new byte[0]));
        assertEquals("", result);
    }
}
