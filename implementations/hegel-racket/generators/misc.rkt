#lang racket/base

;;; just, sampled-from, one-of, optional generators.

(require racket/contract
         racket/list
         "../test-case.rkt"
         "core.rkt")

(provide
 (contract-out
  [just         (-> any/c generator?)]
  [sampled-from (-> (and/c list? (not/c null?)) generator?)]
  [one-of       (->* () #:rest (listof generator?) generator?)]
  [optional     (-> generator? generator?)]))

;; ---------------------------------------------------------------------------
;; just
;; ---------------------------------------------------------------------------

(define (just value)
  ;; The server returns the null value from the schema; we ignore it and return value
  (define schema (hash "type" "constant" "value" 'null))
  (make-basic-generator schema (lambda (_raw) value)))

;; ---------------------------------------------------------------------------
;; sampled-from
;; ---------------------------------------------------------------------------

(define (sampled-from values)
  (define len (length values))
  (define schema (hash "type" "integer" "min_value" 0 "max_value" (- len 1)))
  (define vec (list->vector values))
  (make-basic-generator schema (lambda (idx)
    (vector-ref vec (inexact->exact idx)))))

;; ---------------------------------------------------------------------------
;; one-of
;; ---------------------------------------------------------------------------

(define (one-of . gens)
  (when (null? gens)
    (error 'one-of "must provide at least one generator"))
  ;; Check if all generators are basic
  (define basics (map generator-as-basic gens))
  (if (andmap (lambda (x) x) basics)
      ;; All basic: compose schemas
      (one-of-basic gens basics)
      ;; Not all basic: compositional generation
      (one-of-non-basic gens)))

(define (one-of-basic gens basics)
  ;; Wrap each schema in a tuple {type: "tuple", elements: [{type: "constant", value: i}, schema]}
  ;; so the server returns [index, raw-value] pairs for disambiguation.
  (define tagged-schemas
    (for/list ([bs basics] [i (in-naturals)])
      (hash "type" "tuple"
            "elements" (list (hash "type" "constant" "value" i)
                             (basic-schema-schema bs)))))
  (define combined-schema (hash "type" "one_of" "generators" tagged-schemas))
  ;; The server returns a list [index, raw-value] (CBOR arrays decode as Racket lists)
  (define (transform raw)
    (define idx (inexact->exact (car raw)))
    (define val (cadr raw))
    (define t (basic-schema-transform (list-ref basics idx)))
    (if t (t val) val))
  (make-basic-generator combined-schema transform))

(define (one-of-non-basic gens)
  (define n (length gens))
  (define idx-schema (hash "type" "integer" "min_value" 0 "max_value" (- n 1)))
  (define idx-gen (make-basic-generator idx-schema))
  (define vec (list->vector gens))
  (generator
   (lambda (tc)
     (tc-start-span tc LABEL-ONE-OF)
     (define idx (inexact->exact (draw-silent tc idx-gen)))
     (define result ((generator-draw-fn (vector-ref vec idx)) tc))
     (tc-stop-span tc #f)
     result)
   (lambda () #f)))

;; ---------------------------------------------------------------------------
;; optional
;; ---------------------------------------------------------------------------

(define (optional elem-gen)
  (apply one-of (list (just #f) elem-gen)))
