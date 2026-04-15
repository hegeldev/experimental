#lang racket/base

;;; Integration tests: run actual property tests against the hegel server.
;;;
;;; These tests start the real hegel-core server subprocess and exercise
;;; the full protocol stack (session, connection, runner, generators).

(require (except-in rackunit make-test-case run-test-case)
         rackunit/text-ui
         racket/path
         racket/runtime-path
         racket/string
         (except-in (file "../main.rkt") make-test-case)
         (only-in (file "../test-case.rkt") make-test-case)
         (only-in (file "../runner.rkt") run-test-case)
         (file "../session.rkt")
         (file "../connection.rkt"))

;; Path to mock server script (relative to this file)
(define-runtime-path mock-server-path "mock-server.py")

;; ---------------------------------------------------------------------------
;; Basic integration tests
;; ---------------------------------------------------------------------------

(define integration-tests
  (test-suite
   "Integration tests (real server)"

   (test-suite
    "Session"

    (test-case "get-session returns a valid session"
      (define sess (get-session))
      (check-pred hegel-session? sess))

    (test-case "get-session is idempotent (singleton)"
      (define sess1 (get-session))
      (define sess2 (get-session))
      (check-eq? sess1 sess2))

    (test-case "session has connection and control stream"
      (define sess (get-session))
      (check-pred connection? (session-connection sess))
      (check-pred stream? (session-control-stream sess))))

   (test-suite
    "Basic property tests"

    (test-case "integer property test passes"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define x (draw tc (integers #:min-value 0 #:max-value 100)))
            (check-true (>= x 0))
            (check-true (<= x 100)))
          #:test-cases 20))))

    (test-case "boolean property test passes"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define b (draw tc (booleans)))
            (check-pred boolean? b))
          #:test-cases 10))))

    (test-case "text property test passes"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define s (draw tc (text #:min-size 0 #:max-size 20)))
            (check-pred string? s))
          #:test-cases 10))))

    (test-case "float property test passes"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define f (draw tc (floats #:min-value 0.0 #:max-value 1.0)))
            (check-true (>= f 0.0))
            (check-true (<= f 1.0)))
          #:test-cases 10))))

    (test-case "binary property test passes"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define b (draw tc (binary #:min-size 0 #:max-size 10)))
            (check-pred bytes? b))
          #:test-cases 10))))

    (test-case "list property test passes"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define lst (draw tc (lists (integers #:min-value 0))))
            (check-pred list? lst))
          #:test-cases 10))))

    (test-case "non-basic list property test"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define filtered-gen (generator-filter (integers #:min-value 0 #:max-value 100) even?))
            (define lst (draw tc (lists filtered-gen #:min-size 0 #:max-size 5)))
            (for ([x lst]) (check-true (even? x))))
          #:test-cases 10))))

    (test-case "hashmap property test"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define hmap (draw tc (hashmaps (integers #:min-value 0) (integers #:min-value 0))))
            (check-true (hash? hmap)))
          #:test-cases 10))))

    (test-case "sampled-from property test"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define v (draw tc (sampled-from '(1 2 3 4 5))))
            (unless (member v '(1 2 3 4 5))
              (error (format "sampled-from returned ~a, not in list" v))))
          #:test-cases 10))))

    (test-case "one-of property test"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define v (draw tc (one-of (integers #:min-value 0 #:max-value 10)
                                       (booleans))))
            (unless (or (and (integer? v) (<= 0 v 10)) (boolean? v))
              (error (format "one-of returned unexpected value: ~a" v))))
          #:test-cases 10))))

    (test-case "failing test is detected and raises"
      (check-exn
       exn:fail?
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define x (draw tc (integers #:min-value 1 #:max-value 100)))
            (check-equal? x 1))
          #:test-cases 50))))

    (test-case "assume filters test cases"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define x (draw tc (integers #:min-value 0 #:max-value 10)))
            (tc-assume tc (even? x))
            (check-true (even? x)))
          #:test-cases 20))))

    (test-case "derandomize flag works"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define x (draw tc (integers)))
            (check-pred integer? x))
          #:test-cases 10
          #:derandomize #t))))

    (test-case "seed parameter works"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define x (draw tc (integers)))
            (check-pred integer? x))
          #:test-cases 5
          #:seed 12345))))

    (test-case "multiple draws in one test case"
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define x (draw tc (integers #:min-value 0 #:max-value 100)))
            (define y (draw tc (integers #:min-value 0 #:max-value 100)))
            (define z (draw tc (booleans)))
            (check-true (or z (not z))))  ; always true
          #:test-cases 10))))

    (test-case "tc-note output on final run"
      ;; Test that a failing test with tc-note doesn't crash
      (define noted (box #f))
      (check-exn
       exn:fail?
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define x (draw tc (integers #:min-value 1 #:max-value 3)))
            (tc-note tc (format "x = ~a" x))
            (set-box! noted #t)
            ;; Always fail
            (check-true #f))
          #:test-cases 20)))
      (check-true (unbox noted)))

    (test-case "default test-cases uses 100"
      ;; Covers the default [test-cases 100] expression in run-hegel
      ;; Uses seed + disabled database to make it deterministic and fast
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define x (draw tc (integers #:min-value 0 #:max-value 100)))
            (check-pred integer? x))
          ;; No #:test-cases -- uses default 100
          #:seed 42
          #:database 'disabled))))

    (test-case "database disabled in CI environment"
      ;; Covers the 'disabled literal in default (if (in-ci?) 'disabled 'unset)
      (check-not-exn
       (lambda ()
         (parameterize ([current-environment-variables
                         (environment-variables-copy (current-environment-variables))])
           (environment-variables-set! (current-environment-variables) #"CI" #"true")
           (run-hegel
            (lambda (tc)
              (define x (draw tc (integers #:min-value 0 #:max-value 100)))
              (check-pred integer? x))
            #:test-cases 5)))))

    (test-case "database disabled option works"
      ;; Covers (eq? database 'disabled) path in run-hegel
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define x (draw tc (integers #:min-value 0 #:max-value 100)))
            (check-pred integer? x))
          #:test-cases 5
          #:database 'disabled))))

    (test-case "database string option works"
      ;; Covers (string? database) path in run-hegel
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define x (draw tc (integers #:min-value 0 #:max-value 100)))
            (check-pred integer? x))
          #:test-cases 5
          #:database "/tmp/hegel-test-db"))))

    (test-case "suppress-health-check option works"
      ;; Covers (not (null? suppress-health-check)) path in run-hegel
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define x (draw tc (integers #:min-value 0 #:max-value 10)))
            (check-pred integer? x))
          #:test-cases 5
          #:suppress-health-check '("filter_too_much")))))

    (test-case "non-basic hashmap property test"
      ;; Covers hashmaps-non-basic function body in generators/collections.rkt
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            (define filtered-key (generator-filter (integers #:min-value 1 #:max-value 20) odd?))
            (define hmap (draw tc (hashmaps filtered-key (integers #:min-value 0))))
            (check-true (hash? hmap))
            (for ([k (hash-keys hmap)])
              (check-true (odd? k))))
          #:test-cases 10))))

    (test-case "non-basic hashmap duplicate key rejection"
      ;; Covers the (hash-has-key? result k) duplicate-key branch in hashmaps-non-basic.
      ;; Uses a filtered key gen with only 2 possible values and min-size 3,
      ;; guaranteeing that duplicates must occur (pigeonhole principle).
      (check-not-exn
       (lambda ()
         (run-hegel
          (lambda (tc)
            ;; Only 2 possible odd values (1, 3), min-size 3 -> must generate a duplicate key
            (define key-gen (generator-filter (integers #:min-value 1 #:max-value 3) odd?))
            (define hmap (draw tc (hashmaps key-gen (integers #:min-value 0)
                                            #:min-size 3 #:max-size 5)))
            (check-true (hash? hmap))
            ;; All keys must be odd
            (for ([k (hash-keys hmap)])
              (check-true (odd? k))))
          #:test-cases 10
          #:suppress-health-check '("filter_too_much")))))

    (test-case "mock server: health_check_failure raises error"
      ;; Covers (when (hash-ref result-data "health_check_failure" #f) ...) in run-hegel
      (reset-session-for-testing!)
      (dynamic-wind
        void
        (lambda ()
          (parameterize ([current-environment-variables
                          (environment-variables-copy (current-environment-variables))])
            (environment-variables-set! (current-environment-variables)
                                        #"HEGEL_SERVER_COMMAND"
                                        (string->bytes/utf-8 (path->string mock-server-path)))
            (environment-variables-set! (current-environment-variables)
                                        #"MOCK_SERVER_MODE" #"health_check_failure")
            (reset-session-for-testing!)
            (check-exn
             (lambda (e) (and (exn:fail? e)
                              (string-contains? (exn-message e) "Health check failure")))
             (lambda ()
               (run-hegel
                (lambda (tc)
                  (define x (draw tc (integers #:min-value 0 #:max-value 10)))
                  (check-pred integer? x))
                #:test-cases 5)))))
        (lambda ()
          (reset-session-for-testing!))))

    (test-case "mock server: flaky raises error"
      ;; Covers (when (hash-ref result-data "flaky" #f) ...) in run-hegel
      (reset-session-for-testing!)
      (dynamic-wind
        void
        (lambda ()
          (parameterize ([current-environment-variables
                          (environment-variables-copy (current-environment-variables))])
            (environment-variables-set! (current-environment-variables)
                                        #"HEGEL_SERVER_COMMAND"
                                        (string->bytes/utf-8 (path->string mock-server-path)))
            (environment-variables-set! (current-environment-variables)
                                        #"MOCK_SERVER_MODE" #"flaky")
            (reset-session-for-testing!)
            (check-exn
             (lambda (e) (and (exn:fail? e)
                              (string-contains? (exn-message e) "Flaky test")))
             (lambda ()
               (run-hegel
                (lambda (tc)
                  (define x (draw tc (integers #:min-value 0 #:max-value 10)))
                  (check-pred integer? x))
                #:test-cases 5)))))
        (lambda ()
          (reset-session-for-testing!))))

    (test-case "mock server: else_loop skips unknown event and succeeds"
      ;; Covers the else branch in run-hegel event loop (unknown event type)
      (reset-session-for-testing!)
      (dynamic-wind
        void
        (lambda ()
          (parameterize ([current-environment-variables
                          (environment-variables-copy (current-environment-variables))])
            (environment-variables-set! (current-environment-variables)
                                        #"HEGEL_SERVER_COMMAND"
                                        (string->bytes/utf-8 (path->string mock-server-path)))
            (environment-variables-set! (current-environment-variables)
                                        #"MOCK_SERVER_MODE" #"else_loop")
            (reset-session-for-testing!)
            (check-not-exn
             (lambda ()
               (run-hegel
                (lambda (tc)
                  (define x (draw tc (integers #:min-value 0 #:max-value 10)))
                  (check-pred integer? x))
                #:test-cases 5)))))
        (lambda ()
          (reset-session-for-testing!))))

    (test-case "mock server: missing_keys uses default values"
      ;; Covers default 0 and #t in (hash-ref result-data "interesting_test_cases" 0) etc.
      (reset-session-for-testing!)
      (dynamic-wind
        void
        (lambda ()
          (parameterize ([current-environment-variables
                          (environment-variables-copy (current-environment-variables))])
            (environment-variables-set! (current-environment-variables)
                                        #"HEGEL_SERVER_COMMAND"
                                        (string->bytes/utf-8 (path->string mock-server-path)))
            (environment-variables-set! (current-environment-variables)
                                        #"MOCK_SERVER_MODE" #"missing_keys")
            (reset-session-for-testing!)
            (check-not-exn
             (lambda ()
               (run-hegel
                (lambda (tc)
                  (define x (draw tc (integers #:min-value 0 #:max-value 10)))
                  (check-pred integer? x))
                #:test-cases 5)))))
        (lambda ()
          (reset-session-for-testing!))))

    (test-case "mock server: passed_false_no_replay raises with 'unknown' message"
      ;; Covers the \"unknown\" fallback in run-hegel when passed=false but no replay happened
      (reset-session-for-testing!)
      (dynamic-wind
        void
        (lambda ()
          (parameterize ([current-environment-variables
                          (environment-variables-copy (current-environment-variables))])
            (environment-variables-set! (current-environment-variables)
                                        #"HEGEL_SERVER_COMMAND"
                                        (string->bytes/utf-8 (path->string mock-server-path)))
            (environment-variables-set! (current-environment-variables)
                                        #"MOCK_SERVER_MODE" #"passed_false_no_replay")
            (reset-session-for-testing!)
            (check-exn
             (lambda (e) (and (exn:fail? e)
                              (string-contains? (exn-message e) "unknown")))
             (lambda ()
               (run-hegel
                (lambda (tc)
                  (define x (draw tc (integers #:min-value 0 #:max-value 10)))
                  (check-pred integer? x))
                #:test-cases 5)))))
        (lambda ()
          (reset-session-for-testing!)))))))

(run-tests integration-tests)
