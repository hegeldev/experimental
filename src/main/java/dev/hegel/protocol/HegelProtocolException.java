package dev.hegel.protocol;

/** Thrown when the Hegel wire protocol is violated or the server behaves unexpectedly. */
public class HegelProtocolException extends RuntimeException {

    public HegelProtocolException(String message) {
        super(message);
    }

    public HegelProtocolException(String message, Throwable cause) {
        super(message, cause);
    }
}
