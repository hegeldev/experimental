#lang racket/base

;;; Unit tests for conformance.rkt helper functions.

(require (except-in rackunit make-test-case)
         rackunit/text-ui
         racket/file
         racket/string
         (except-in (file "../main.rkt") make-test-case)
         (only-in (file "../test-case.rkt") make-test-case make-data-source)
         (only-in (file "../generators/core.rkt") generator-as-basic)
         (file "../conformance.rkt"))

(define conformance-helper-tests
  (test-suite
   "Conformance helper tests"

   (test-suite
    "get-test-cases"

    (test-case "returns 50 when env var not set"
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    #"CONFORMANCE_TEST_CASES" #f)
        (check-equal? (get-test-cases) 50)))

    (test-case "returns env var value when set to valid integer"
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    #"CONFORMANCE_TEST_CASES" #"25")
        (check-equal? (get-test-cases) 25)))

    (test-case "returns 50 when env var is not a valid positive integer"
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    #"CONFORMANCE_TEST_CASES" #"not-a-number")
        (check-equal? (get-test-cases) 50)))

    (test-case "returns 50 when env var is zero"
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    #"CONFORMANCE_TEST_CASES" #"0")
        (check-equal? (get-test-cases) 50))))

   (test-suite
    "write-metrics"

    (test-case "write-metrics appends JSON to file"
      (define tmp-file (make-temporary-file))
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    #"CONFORMANCE_METRICS_FILE"
                                    (string->bytes/utf-8 (path->string tmp-file)))
        (check-not-exn (lambda () (write-metrics (hash 'value 42))))
        (define content (file->string tmp-file))
        (check-true (string-contains? content "42")))
      (delete-file tmp-file))

    (test-case "write-metrics escapes U+0085 NEL"
      (define tmp-file (make-temporary-file))
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    #"CONFORMANCE_METRICS_FILE"
                                    (string->bytes/utf-8 (path->string tmp-file)))
        (define metrics (hash 'value (string (integer->char #x0085))))
        (check-not-exn (lambda () (write-metrics metrics)))
        (define content (file->string tmp-file))
        (check-true (string-contains? content "\\u0085"))
        (check-false (string-contains? content (string (integer->char #x0085)))))
      (delete-file tmp-file))

    (test-case "write-metrics escapes U+2028 line separator"
      (define tmp-file (make-temporary-file))
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    #"CONFORMANCE_METRICS_FILE"
                                    (string->bytes/utf-8 (path->string tmp-file)))
        (define metrics (hash 'value (string (integer->char #x2028))))
        (check-not-exn (lambda () (write-metrics metrics)))
        (define content (file->string tmp-file))
        (check-true (string-contains? content "\\u2028")))
      (delete-file tmp-file))

    (test-case "write-metrics escapes U+2029 paragraph separator"
      (define tmp-file (make-temporary-file))
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    #"CONFORMANCE_METRICS_FILE"
                                    (string->bytes/utf-8 (path->string tmp-file)))
        (define metrics (hash 'value (string (integer->char #x2029))))
        (check-not-exn (lambda () (write-metrics metrics)))
        (define content (file->string tmp-file))
        (check-true (string-contains? content "\\u2029")))
      (delete-file tmp-file))

    (test-case "write-metrics raises when env var not set"
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    #"CONFORMANCE_METRICS_FILE" #f)
        (check-exn exn:fail?
          (lambda () (write-metrics (hash 'x 1)))))))

   (test-suite
    "make-non-basic"

    (test-case "wraps a basic generator to be non-basic"
      (check-not-false (generator-as-basic (integers)))
      (check-false (generator-as-basic (make-non-basic (integers)))))

    (test-case "drawing from non-basic generator calls always-true predicate"
      ;; Drawing from a make-non-basic generator exercises always-true
      (define non-basic-gen (make-non-basic (integers)))
      ;; Use a mock tc so we can draw without a real server
      (define tc (make-test-case
                  (make-data-source
                   (lambda (schema) 42)
                   (lambda (label) (void))
                   (lambda (discard) (void))
                   (lambda (min-size max-size) 0)
                   (lambda (coll-id) #f)
                   (lambda (coll-id why) (void))
                   (lambda (status origin) (void))
                   (lambda () #f))
                  #f))
      (check-equal? (draw tc non-basic-gen) 42)))))

(run-tests conformance-helper-tests)
