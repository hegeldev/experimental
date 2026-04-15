#lang racket/base

;;; Test utilities for asserting properties of generators.
;;;
;;; These helpers are useful when writing tests for code that uses Hegel.
;;; They let you make assertions about what generators can and cannot produce,
;;; and find minimal examples satisfying a predicate.

(require racket/contract
         "runner.rkt"
         "generators/core.rkt")

(provide
 (contract-out
  [assert-all-examples
   (->* (generator? (-> any/c any/c))
        (#:test-cases exact-positive-integer?)
        void?)]
  [assert-no-examples
   (->* (generator? (-> any/c any/c))
        (#:test-cases exact-positive-integer?)
        void?)]
  [find-any
   (->* (generator? (-> any/c any/c))
        (#:test-cases exact-positive-integer?)
        any/c)]
  [minimal
   (->* (generator? (-> any/c any/c))
        (#:test-cases exact-positive-integer?)
        any/c)]))

;; ---------------------------------------------------------------------------
;; assert-all-examples
;; ---------------------------------------------------------------------------

;;; Run test-cases draws from gen. Raises if any drawn value fails pred.
;;; Use this to assert that a generator only produces values satisfying a predicate.
(define (assert-all-examples gen pred #:test-cases [test-cases 100])
  ;; Use a fixed error message so Hypothesis treats all failures as the same
  ;; interesting class. The failing value appears in the draw_N debug output.
  (run-hegel
   (lambda (tc)
     (define v (draw tc gen))
     (unless (pred v)
       (error "assert-all-examples: generated value did not satisfy predicate")))
   #:test-cases test-cases))

;; ---------------------------------------------------------------------------
;; assert-no-examples
;; ---------------------------------------------------------------------------

;;; Run test-cases draws from gen. Raises if any drawn value satisfies pred.
;;; Use this to assert that a generator never produces values satisfying a predicate.
(define (assert-no-examples gen pred #:test-cases [test-cases 100])
  ;; Use a fixed error message so Hypothesis treats all failures as the same
  ;; interesting class. The failing value appears in the draw_N debug output.
  (run-hegel
   (lambda (tc)
     (define v (draw tc gen))
     (when (pred v)
       (error "assert-no-examples: generated value should not satisfy predicate")))
   #:test-cases test-cases))

;; ---------------------------------------------------------------------------
;; find-any
;; ---------------------------------------------------------------------------

;;; Find any value from gen that satisfies pred.
;;; Returns the found value (which has been shrunk to a minimal form).
;;; Raises if no satisfying value is found within test-cases draws.
(define (find-any gen pred #:test-cases [test-cases 100])
  (define result (box #f))
  (define found? (box #f))
  (with-handlers
    ([exn:fail?
      (lambda (e)
        (unless (unbox found?)
          ;; Hegel ran out of interesting cases without finding one
          (raise (make-exn:fail
                  "find-any: no example satisfying predicate found"
                  (current-continuation-marks))))
        (unbox result))])
    (run-hegel
     (lambda (tc)
       (define v (draw tc gen))
       (when (pred v)
         ;; Always set result - the last replay (shrunk minimal) wins.
         ;; Use a fixed error message so all failures share one origin,
         ;; so Hypothesis keeps only the minimal interesting case.
         (set-box! result v)
         (set-box! found? #t)
         (error "find-any: predicate satisfied")))
     #:test-cases test-cases)
    ;; If run-hegel succeeded without raising, no example was found
    (error 'find-any "no example satisfying predicate found")))

;; ---------------------------------------------------------------------------
;; minimal
;; ---------------------------------------------------------------------------

;;; Find the minimal value from gen that satisfies pred (via Hegel's shrinking).
;;; Returns the shrunk minimal value.
;;; Raises if no satisfying value is found within test-cases draws.
(define (minimal gen pred #:test-cases [test-cases 100])
  (find-any gen pred #:test-cases test-cases))
