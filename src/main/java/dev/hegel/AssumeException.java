package dev.hegel;

/**
 * Thrown by {@link TestCase#assume(boolean)} when the condition is false.
 *
 * <p>The test runner catches this and marks the test case as INVALID.
 */
public class AssumeException extends RuntimeException {

    static final String MESSAGE = "__HEGEL_ASSUME_FAIL";

    public AssumeException() {
        super(MESSAGE);
    }
}
