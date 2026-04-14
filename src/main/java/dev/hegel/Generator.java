package dev.hegel;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.Optional;
import java.util.function.Function;
import java.util.function.Predicate;

/**
 * A generator that can produce values of type {@code T}.
 *
 * <p>Generators may be <em>basic</em> (they have a CBOR schema and an optional
 * client-side transform) or <em>non-basic</em> (they produce values through
 * back-and-forth compositional generation with the server).
 *
 * <p>Use {@link #asBasic()} to check whether a generator is basic.
 *
 * @param <T> the type of values this generator produces
 */
public interface Generator<T> {

    /**
     * Draw a value from this generator using the given test case context.
     * This is the primary generation entry point.
     */
    T generate(TestCase tc);

    /**
     * Return a {@link BasicGenerator} view of this generator, if it is basic.
     * Returns {@link Optional#empty()} for non-basic generators.
     */
    default Optional<BasicGenerator<T>> asBasic() {
        return Optional.empty();
    }

    // -----------------------------------------------------------------------
    // Combinators
    // -----------------------------------------------------------------------

    /**
     * Transform generated values with {@code f}.
     *
     * <p>If this generator is basic, the result is also basic (the transform
     * is composed into the existing transform, preserving the schema).
     * If this generator is non-basic, the result is a non-basic mapped generator.
     */
    default <U> Generator<U> map(Function<T, U> f) {
        Optional<BasicGenerator<T>> basic = asBasic();
        if (basic.isPresent()) {
            return basic.get().mapBasic(f);
        }
        // Non-basic: wrap with MAPPED span
        Generator<T> self = this;
        return tc -> {
            tc.startSpan(Labels.MAPPED);
            try {
                T raw = self.generate(tc);
                return f.apply(raw);
            } finally {
                tc.stopSpan(false);
            }
        };
    }

    /**
     * Filter generated values by a predicate.
     *
     * <p>Tries up to 3 times to generate a value satisfying the predicate.
     * If all attempts fail, calls {@code tc.assume(false)} to reject the test case.
     * Always non-basic.
     */
    default Generator<T> filter(Predicate<T> predicate) {
        Generator<T> self = this;
        return tc -> {
            for (int attempt = 0; attempt < 3; attempt++) {
                tc.startSpan(Labels.FILTER);
                T value = self.generate(tc);
                if (predicate.test(value)) {
                    tc.stopSpan(false);
                    return value;
                }
                tc.stopSpan(true);
            }
            tc.assume(false);
            throw new AssertionError("unreachable");
        };
    }

    /**
     * Dependent generation: the output of this generator determines the next generator.
     * Always non-basic.
     */
    default <U> Generator<U> flatMap(Function<T, Generator<U>> f) {
        Generator<T> self = this;
        return tc -> {
            tc.startSpan(Labels.FLAT_MAP);
            try {
                T raw = self.generate(tc);
                Generator<U> next = f.apply(raw);
                return next.generate(tc);
            } finally {
                tc.stopSpan(false);
            }
        };
    }
}
