package dev.hegel;

/**
 * Thrown when the hegel-core server signals that the current test case should be stopped (data
 * exhausted or StopTest received).
 *
 * <p>This is an internal control-flow exception and should not escape the library.
 */
public class StopTestException extends RuntimeException {

  public StopTestException() {
    super("hegel-core: test case data exhausted (StopTest)");
  }

  public StopTestException(String message) {
    super(message);
  }
}
