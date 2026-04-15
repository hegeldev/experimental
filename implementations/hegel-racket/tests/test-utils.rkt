#lang racket/base

;;; Tests for test-utils.rkt: assert-all-examples, assert-no-examples, find-any, minimal.

(require (except-in rackunit make-test-case run-test-case)
         rackunit/text-ui
         (except-in (file "../main.rkt") make-test-case)
         (only-in (file "../test-case.rkt") make-test-case))

(define utils-tests
  (test-suite
   "Test utilities"

   (test-suite
    "assert-all-examples"

    (test-case "passes when all examples satisfy predicate"
      (check-not-exn
       (lambda ()
         (assert-all-examples
          (integers #:min-value 0 #:max-value 100)
          (lambda (n) (and (>= n 0) (<= n 100)))
          #:test-cases 20))))

    (test-case "raises when a generated value fails the predicate"
      (check-exn
       exn:fail?
       (lambda ()
         (assert-all-examples
          (integers #:min-value 1 #:max-value 100)
          (lambda (n) (= n 0))  ; always fails — integers are 1-100
          #:test-cases 20))))

    (test-case "works with boolean generator"
      (check-not-exn
       (lambda ()
         (assert-all-examples
          (booleans)
          boolean?
          #:test-cases 10))))

    (test-case "works with text generator"
      (check-not-exn
       (lambda ()
         (assert-all-examples
          (text #:min-size 0 #:max-size 10)
          string?
          #:test-cases 10))))

    (test-case "uses default test-cases when not specified"
      (check-not-exn
       (lambda ()
         ;; Call without #:test-cases to exercise the default value 100
         (assert-all-examples
          (booleans)
          boolean?)))))

   (test-suite
    "assert-no-examples"

    (test-case "passes when no examples satisfy predicate"
      (check-not-exn
       (lambda ()
         (assert-no-examples
          (integers #:min-value 0 #:max-value 10)
          negative?
          #:test-cases 20))))

    (test-case "raises when a generated value satisfies the predicate"
      (check-exn
       exn:fail?
       (lambda ()
         (assert-no-examples
          (integers #:min-value 1 #:max-value 100)
          positive?  ; integers(1-100) are always positive
          #:test-cases 20))))

    (test-case "works with booleans: no booleans are strings"
      (check-not-exn
       (lambda ()
         (assert-no-examples
          (booleans)
          string?
          #:test-cases 10))))

    (test-case "uses default test-cases when not specified"
      (check-not-exn
       (lambda ()
         ;; Call without #:test-cases to exercise the default value 100
         (assert-no-examples
          (integers #:min-value 0 #:max-value 10)
          negative?)))))

   (test-suite
    "find-any"

    (test-case "finds a value satisfying predicate"
      (define v (find-any (integers #:min-value 0 #:max-value 100)
                          (lambda (n) (> n 50))
                          #:test-cases 200))
      (check-pred integer? v)
      (check-true (> v 50)))

    (test-case "raises when no value satisfies predicate"
      ;; Use a predicate that can never be satisfied for integers in [0,10]
      (check-exn
       exn:fail?
       (lambda ()
         (find-any (integers #:min-value 0 #:max-value 10)
                   (lambda (n) (> n 100))
                   #:test-cases 50))))

    (test-case "returns a shrunk minimal value"
      ;; Integers > 42 — minimal should be 43
      (define v (find-any (integers #:min-value 0 #:max-value 1000)
                          (lambda (n) (> n 42))
                          #:test-cases 500))
      (check-equal? v 43))

    (test-case "works with lists"
      (define v (find-any (lists (integers #:min-value 0 #:max-value 10))
                          (lambda (lst) (> (length lst) 2))
                          #:test-cases 200))
      (check-pred list? v)
      (check-true (> (length v) 2)))

    (test-case "uses default test-cases when not specified"
      ;; Call without #:test-cases to exercise the default value 100
      (define v (find-any (booleans) (lambda (b) (not b))))
      (check-equal? v #f)))

   (test-suite
    "minimal"

    (test-case "finds minimal integer > 42"
      (define v (minimal (integers #:min-value 0 #:max-value 1000)
                         (lambda (n) (> n 42))
                         #:test-cases 500))
      (check-equal? v 43))

    (test-case "finds minimal non-empty list"
      (define v (minimal (lists (integers #:min-value 0 #:max-value 10) #:min-size 0)
                         (lambda (lst) (not (null? lst)))
                         #:test-cases 200))
      (check-pred list? v)
      (check-false (null? v)))

    (test-case "raises when no value satisfies predicate"
      (check-exn
       exn:fail?
       (lambda ()
         (minimal (integers #:min-value 0 #:max-value 5)
                  (lambda (n) (> n 100))
                  #:test-cases 50))))

    (test-case "uses default test-cases when not specified"
      ;; Call without #:test-cases to exercise the default value 100
      (define v (minimal (booleans) (lambda (b) (not b))))
      (check-equal? v #f)))))

(run-tests utils-tests)
