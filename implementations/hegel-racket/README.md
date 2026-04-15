> **Beta notice:** hegel-racket is in early development. Bugs and API changes are expected. Please report issues at https://github.com/hegeldev/hegel-racket/issues.

> **Note:** This implementation was generated with the assistance of Claude (claude-sonnet-4-6) and has not been extensively used in production. Please report issues.

# Hegel for Racket

**hegel-racket** is a property-based testing library for Racket, based on [Hypothesis](https://hypothesis.readthedocs.io/), using the [Hegel protocol](https://hegel.dev).

## Prerequisites

- Racket 8.0+
- Python and [uv](https://docs.astral.sh/uv/) (for running hegel-core):

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## Installation

Install from the Racket package catalog:

```bash
raco pkg install hegel
```

Or install from source:

```bash
git clone https://github.com/hegeldev/hegel-racket.git
cd hegel-racket
raco pkg install
```

## Quick Start

Property-based testing generates many inputs automatically and shrinks failures to the simplest possible case. Here is a complete example that finds a bug in a sort function.

First, define a sort function with a subtle bug — it uses a set, which silently removes duplicate elements:

```racket
#lang racket

;;; A sort with a bug: list->set removes duplicate elements.
(define (bad-sort lst)
  (sort (set->list (list->set lst)) <))
```

Write a property test that checks that sorting preserves the element count:

```racket
#lang racket
(require hegel rackunit)

(test-case "sort preserves length"
  (run-hegel
   (lambda (tc)
     (define xs (draw tc (lists (integers #:min-value -10 #:max-value 10))))
     (define sorted (bad-sort xs))
     (check-equal? (length sorted) (length xs)
                   (format "Sort must not lose elements: ~a -> ~a" xs sorted)))))
```

Run with `raco test`:

```bash
raco test my-test.rkt
```

Hegel finds the bug and shrinks the failing case to its minimal form:

```
Sort must not lose elements: (0 0) -> (0)
```

Hegel generated 100 lists (the default). When it found a failing case like `(3 3 1 2)`, it automatically shrunk that list until it found `(0 0)` — the simplest possible list that exposes the duplicate-removal bug.

## Tutorial

### Your first passing test

The simplest property to test: a generated integer stays within its declared bounds.

```racket
#lang racket
(require hegel rackunit)

(test-case "integers are in range"
  (run-hegel
   (lambda (tc)
     (define n (draw tc (integers #:min-value 0 #:max-value 100)))
     (check-true (and (>= n 0) (<= n 100))
                 (format "Expected n in [0,100], got ~a" n)))))
```

Run `raco test`. Hegel generates 100 values and the test passes.

### Your first failing test

Now write a property that looks right but is subtly wrong. Racket's `string->number` returns `#f` for invalid input — but what if you forget to check for it?

```racket
(test-case "string->number is always a number"
  (run-hegel
   (lambda (tc)
     (define s (draw tc (text #:min-size 0 #:max-size 10)))
     ;; This fails for strings like "abc" that aren't numeric
     (check-pred number? (string->number s)))))
```

Hegel finds the bug and shrinks it to the simplest non-numeric string:

```
check-pred: wrong type
  predicate: number?
  value: #f
  in: "a"
```

### Constrained generation

If you only want even numbers, use `generator-filter`:

```racket
(define evens
  (generator-filter (integers #:min-value -100 #:max-value 100)
                    even?))
```

Or use `generator-map` to derive a value:

```racket
(define doubled
  (generator-map (integers #:min-value 0 #:max-value 50)
                 (lambda (n) (* n 2))))
```

### Dependent generation

Because drawing values is imperative, you can use an earlier result to configure a later generator. This is one of Hegel's most powerful features:

```racket
(test-case "list index is always valid"
  (run-hegel
   (lambda (tc)
     (define n (draw tc (integers #:min-value 1 #:max-value 10)))
     (define lst (draw tc (lists (integers) #:min-size n #:max-size n)))
     (define index (draw tc (integers #:min-value 0 #:max-value (- n 1))))
     ;; lst always has exactly n elements, so index is always in bounds
     (check-not-false (list-ref lst index)))))
```

First draw the length `n`, then use it to generate a list of exactly that length, then draw a valid index. All three draws are correlated — and Hegel can still shrink the whole thing together.

### Composite objects

Draw multiple values and combine them into a domain object:

```racket
(struct point (x y) #:transparent)

(test-case "points are in first quadrant"
  (run-hegel
   (lambda (tc)
     (define x (draw tc (integers #:min-value 0 #:max-value 1000)))
     (define y (draw tc (integers #:min-value 0 #:max-value 1000)))
     (define p (point x y))
     (check-true (and (>= (point-x p) 0) (>= (point-y p) 0))))))
```

When a test fails, Hegel shrinks all the draws together, so the reported failing `point` is always the simplest one.

### Debugging with `tc-note`

Use `tc-note` to print values during the final shrunk replay:

```racket
(run-hegel
 (lambda (tc)
   (define x (draw tc (integers)))
   (tc-note tc (format "drew x = ~a" x))
   ;; ... rest of test
   ))
```

Notes are suppressed during normal runs and only printed when replaying the shrunk failure, so they do not slow down test execution.

### Filtering test cases with `tc-assume`

Use `tc-assume` to discard test cases that don't satisfy a precondition:

```racket
(run-hegel
 (lambda (tc)
   (define x (draw tc (integers #:min-value 0 #:max-value 10)))
   (tc-assume tc (even? x))   ; skip odd values
   (check-true (even? x))))
```

Prefer using constrained generators (like `generator-filter`) over `tc-assume` when possible. Excessive filtering can trigger a health check.

### Changing the number of test cases

```racket
(run-hegel
 (lambda (tc)
   ;; ... test body
   )
 #:test-cases 500)
```

The default is 100. Increase for properties that need wider coverage; decrease if they are slow.

## API Reference

### Drawing values

Inside `run-hegel`, you receive a test case `tc` that you use to draw generated values:

```racket
(run-hegel
 (lambda (tc)
   (define n1 (draw tc (integers)))                                   ; any exact integer
   (define n2 (draw tc (integers #:min-value 0 #:max-value 100)))     ; in [0, 100]
   (define d1 (draw tc (floats)))                                     ; any real (NaN, ±inf OK)
   (define d2 (draw tc (floats #:min-value 0.0 #:max-value 1.0)))
   (define b1 (draw tc (booleans)))
   (define s1 (draw tc (text)))
   (define s2 (draw tc (text #:min-size 3 #:max-size 20)))
   (define c1 (draw tc (characters)))                                  ; single Unicode character
   (define c2 (draw tc (characters #:codec "ascii")))                  ; single ASCII character
   (define b2 (draw tc (binary #:min-size 1 #:max-size 256)))))
```

### Collection generators

```racket
(define xs1 (draw tc (lists (integers))))
(define xs2 (draw tc (lists (integers #:min-value 0 #:max-value 10)
                            #:min-size 1 #:max-size 5)))
(define xu  (draw tc (lists (integers) #:unique #t)))              ; no duplicates
(define s   (draw tc (sets  (integers #:min-value 0 #:max-value 100))))  ; Racket set
(define hm  (draw tc (hashmaps (integers) (text))))
(define t   (draw tc (tuples (integers) (text) (booleans))))  ; fixed-length list
(define opt (draw tc (optional (integers))))                   ; #f or an integer
(define v1  (draw tc (sampled-from '(1 2 3))))
(define v2  (draw tc (one-of (integers #:min-value 0 #:max-value 5)
                             (booleans))))
```

### Format generators

```racket
(define email (draw tc (emails)))
(define url   (draw tc (urls)))
(define ip4   (draw tc (ipv4-addresses)))
(define ip6   (draw tc (ipv6-addresses)))
(define date  (draw tc (dates)))      ; e.g. "2024-03-15"
(define time  (draw tc (times)))
(define dt    (draw tc (datetimes)))
(define s     (draw tc (from-regex "[a-z]{3,8}")))
```

### Combinators

```racket
;; map: transform a generated value
(define labeled
  (generator-map (integers #:min-value 0 #:max-value 100)
                 (lambda (n) (format "item-~a" n))))

;; filter: constrain generated values
(define positive
  (generator-filter (integers #:min-value -100 #:max-value 100)
                    positive?))

;; flat-map: generate a value that depends on a previously drawn value
(define same-length
  (generator-flat-map
   (integers #:min-value 1 #:max-value 10)
   (lambda (n) (text #:min-size n #:max-size n))))
```

### Control functions

```racket
(tc-assume tc (> x 0))             ; skip this test case if false
(tc-note tc (format "x = ~a" x))   ; print during the final shrunk replay
```

### `run-hegel` options

```racket
(run-hegel
 (lambda (tc) ...)
 #:test-cases 500                  ; number of test cases (default: 100)
 #:seed 42                         ; deterministic seed
 #:derandomize #t                  ; replay known examples only (auto-enabled in CI)
 #:database "/tmp/mydb"            ; example database path (default location)
 #:database 'disabled              ; disable the database
 #:suppress-health-check '("filter_too_much"))
```

## Test Utilities

`test-utils.rkt` provides helpers for asserting properties of generators — useful when writing tests for code that uses Hegel:

```racket
(require hegel)

;; Assert every generated value satisfies a predicate
(assert-all-examples (integers #:min-value 0 #:max-value 100)
                     (lambda (n) (and (>= n 0) (<= n 100))))

;; Assert no generated value satisfies a predicate
(assert-no-examples (integers #:min-value 0 #:max-value 10)
                    negative?)

;; Find any value satisfying a predicate (returns it, or raises if none found)
(define found (find-any (integers #:min-value -100 #:max-value 100)
                        (lambda (n) (> n 50))))

;; Find the minimal value satisfying a predicate (via shrinking)
(define v (minimal (integers #:min-value 0 #:max-value 1000)
                   (lambda (n) (> n 42))))
;; v => 43
```

Each function accepts an optional `#:test-cases` keyword (default 100).

## Development

```bash
just test        # run unit tests (fast, no coverage)
just coverage    # run tests + enforce 100% library coverage
just lint        # check all files compile cleanly
just format      # check all source files parse cleanly
just conformance # run conformance tests against hegel-core 0.4.0
just check       # coverage + lint + conformance (full gate)
```

## License

MIT — see [LICENSE](LICENSE).
