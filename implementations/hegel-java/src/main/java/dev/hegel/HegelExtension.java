package dev.hegel;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.junit.jupiter.api.extension.InvocationInterceptor;
import org.junit.jupiter.api.extension.ParameterContext;
import org.junit.jupiter.api.extension.ParameterResolver;
import org.junit.jupiter.api.extension.ReflectiveInvocationContext;

/**
 * JUnit 5 extension that powers {@link HegelTest}.
 *
 * <p>Intercepts the test method invocation and runs it through the Hegel engine, which executes the
 * method body multiple times with different generated inputs and shrinks any failures to the
 * minimal counterexample.
 */
public class HegelExtension implements InvocationInterceptor, ParameterResolver {

  @Override
  public boolean supportsParameter(ParameterContext parameterContext, ExtensionContext ctx) {
    return parameterContext.getParameter().getType() == TestCase.class;
  }

  @Override
  public Object resolveParameter(ParameterContext parameterContext, ExtensionContext ctx) {
    // Placeholder: the real TestCase is provided by the Hegel engine via interceptTestMethod.
    return null;
  }

  @Override
  public void interceptTestMethod(
      Invocation<Void> invocation,
      ReflectiveInvocationContext<Method> invocationContext,
      ExtensionContext extensionContext)
      throws Throwable {
    // Skip JUnit's normal invocation; Hegel will call the method many times.
    invocation.skip();

    Method method = invocationContext.getExecutable();
    Object target = invocationContext.getTarget().orElse(null);
    method.setAccessible(true);

    HegelTest ann = method.getAnnotation(HegelTest.class);
    Settings.Builder sb = Settings.builder();
    if (ann != null) {
      sb.testCases(ann.testCases());
      if (ann.seed() != Long.MIN_VALUE) {
        sb.seed(ann.seed());
      }
      if (ann.derandomize()) {
        sb.derandomize(true);
      }
    }

    boolean hasTestCaseParam =
        method.getParameterCount() == 1 && method.getParameterTypes()[0] == TestCase.class;

    Hegel.test(
        method.getName(), sb.build(), tc -> invokeTestMethod(method, target, tc, hasTestCaseParam));
  }

  /** Invoke the test method, unwrapping reflection exceptions. Package-private for testing. */
  static void invokeTestMethod(Method method, Object target, TestCase tc, boolean hasTestCase) {
    try {
      if (hasTestCase) {
        method.invoke(target, tc);
      } else {
        method.invoke(target);
      }
    } catch (InvocationTargetException e) {
      Throwable cause = e.getTargetException();
      if (cause instanceof RuntimeException re) throw re;
      if (cause instanceof Error err) throw err;
      throw new RuntimeException(cause);
    } catch (IllegalAccessException e) {
      throw new RuntimeException(e);
    }
  }
}
