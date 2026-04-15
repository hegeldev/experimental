#lang racket/base

;;; Hegel property-based testing library for Racket.
;;;
;;; This is the main entry point. Import this module to get access
;;; to all public APIs.
;;;
;;; Example:
;;;
;;;   #lang racket
;;;   (require hegel rackunit)
;;;
;;;   (test-case "addition is commutative"
;;;     (run-hegel (lambda (tc)
;;;       (define x (draw tc (integers #:min-value 0 #:max-value 100)))
;;;       (define y (draw tc (integers #:min-value 0 #:max-value 100)))
;;;       (check-equal? (+ x y) (+ y x)))))

(require "test-case.rkt"
         "runner.rkt"
         "generators/main.rkt"
         "session.rkt")

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
 make-test-case)
