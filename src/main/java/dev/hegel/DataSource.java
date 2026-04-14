package dev.hegel;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Abstraction over the data generation backend.
 *
 * <p>All methods that can be interrupted by the server sending StopTest
 * throw {@link StopTestException} rather than returning normally.
 */
public interface DataSource {

    /** Send a CBOR schema to the server and receive a generated value. */
    JsonNode generate(JsonNode schema) throws StopTestException;

    /** Begin a labeled span (used for composite generator structure). */
    void startSpan(long label) throws StopTestException;

    /** End the current span. If {@code discard} is true, the span's choices are discarded. */
    void stopSpan(boolean discard);

    /** Create a new server-managed collection. Returns an opaque collection ID. */
    long newCollection(long minSize, Long maxSize) throws StopTestException;

    /** Ask whether the collection should produce another element. */
    boolean collectionMore(long collectionId) throws StopTestException;

    /** Reject the last element drawn from a collection. */
    void collectionReject(long collectionId, String why) throws StopTestException;

    /** Signal that the test case is complete. */
    void markComplete(String status, String origin);

    /** Returns true if a previous request was aborted (StopTest). */
    boolean testAborted();
}
