#lang racket/base

;;; Hegel property-based testing library for Racket.
;;;
;;; This is the main entry point. Import this module to get access
;;; to all public APIs.
;;;
;;; # Getting Started
;;;
;;; Hegel is a property-based testing library powered by Hypothesis. Instead
;;; of writing individual test cases by hand, you describe the shape of your
;;; inputs with generators and let Hegel find inputs that break your
;;; properties. When it finds a failure, it automatically shrinks the failing
;;; input to the simplest possible example.
;;;
;;; ## Your first property test
;;;
;;;   #lang racket
;;;   (require hegel rackunit)
;;;
;;;   (test-case "sort preserves length"
;;;     (run-hegel
;;;      (lambda (tc)
;;;        (define xs (draw tc (lists (integers #:min-value -10 #:max-value 10))))
;;;        (define sorted (sort (list-copy xs) <))
;;;        (check-equal? (length sorted) (length xs)))))
;;;
;;; `run-hegel` runs the lambda 100 times (by default) with different inputs.
;;; If the lambda raises an exception for any input, Hegel shrinks that input
;;; and re-raises with the minimal failing case.
;;;
;;; ## Drawing values
;;;
;;; Inside the lambda, `draw` produces a value from a generator:
;;;
;;;   (define n  (draw tc (integers #:min-value 0 #:max-value 100)))
;;;   (define f  (draw tc (floats #:min-value 0.0 #:max-value 1.0)))
;;;   (define b  (draw tc (booleans)))
;;;   (define s  (draw tc (text #:min-size 3 #:max-size 20)))
;;;   (define bs (draw tc (binary #:max-size 256)))
;;;   (define xs (draw tc (lists (integers) #:min-size 1)))
;;;   (define hm (draw tc (hashmaps (text) (integers))))
;;;   (define v  (draw tc (sampled-from '(a b c))))
;;;   (define x  (draw tc (one-of (integers) (booleans))))
;;;
;;; ## Dependent generation
;;;
;;; Because drawing is imperative, earlier draws can influence later ones:
;;;
;;;   (define n   (draw tc (integers #:min-value 1 #:max-value 10)))
;;;   (define lst (draw tc (lists (integers) #:min-size n #:max-size n)))
;;;   (define idx (draw tc (integers #:min-value 0 #:max-value (- n 1))))
;;;   ;; lst always has n elements so idx is always in bounds
;;;
;;; ## Combinators
;;;
;;;   (generator-map    gen proc)    ; transform drawn values
;;;   (generator-filter gen pred?)  ; discard values not matching predicate
;;;   (generator-flat-map gen proc) ; draw from a generator that depends on a value
;;;
;;; ## Control
;;;
;;;   (tc-assume tc pred)            ; skip test case if pred is #f
;;;   (tc-note   tc message-string)  ; print on final shrunk replay only
;;;
;;; ## Settings
;;;
;;;   (run-hegel proc
;;;              #:test-cases 500         ; default 100
;;;              #:seed 42                ; deterministic seed
;;;              #:derandomize #t         ; replay known examples only
;;;              #:database "/tmp/mydb"   ; persistent example database path
;;;              #:database 'disabled)    ; or disable the database

(require "test-case.rkt"
         "runner.rkt"
         "generators/main.rkt"
         "session.rkt"
         "test-utils.rkt")

(provide
 ;; Test runner
 run-hegel

 ;; TestCase operations
 draw
 draw-silent
 tc-assume
 tc-note
 tc-start-span
 tc-stop-span
 tc-test-aborted?

 ;; Error types
 exn:fail:stop-test?
 exn:fail:assume?

 ;; Span labels
 LABEL-LIST
 LABEL-LIST-ELEMENT
 LABEL-SET
 LABEL-SET-ELEMENT
 LABEL-MAP
 LABEL-MAP-ENTRY
 LABEL-TUPLE
 LABEL-ONE-OF
 LABEL-OPTIONAL
 LABEL-FIXED-DICT
 LABEL-FLAT-MAP
 LABEL-FILTER
 LABEL-MAPPED
 LABEL-SAMPLED-FROM
 LABEL-ENUM-VARIANT

 ;; Generators
 generator?
 generator-map
 generator-flat-map
 generator-filter
 integers
 floats
 booleans
 text
 binary
 just
 sampled-from
 one-of
 optional
 lists
 tuples
 dicts
 hashmaps
 emails
 urls
 domains
 ipv4-addresses
 ipv6-addresses
 ip-addresses
 dates
 times
 datetimes
 from-regex

 ;; Session
 get-session
 HEGEL-SERVER-VERSION

 ;; DataSource (for testing)
 make-data-source
 data-source?
 make-test-case

 ;; Test utilities
 assert-all-examples
 assert-no-examples
 find-any
 minimal)
