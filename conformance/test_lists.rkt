#!/usr/bin/env racket
#lang racket/base

;;; Conformance binary for list generation.
;;;
;;; Params (JSON from argv[1]): { min_size?: number, max_size?: number|null,
;;;                               min_value?: number|null, max_value?: number|null,
;;;                               unique?: boolean,
;;;                               mode?: "basic"|"non_basic" }
;;; Metrics: { size: number, min_element?: number, max_element?: number }

(require json
         (file "../main.rkt")
         (file "../conformance.rkt"))

(define params
  (let ([args (current-command-line-arguments)])
    (if (> (vector-length args) 0)
        (string->jsexpr (vector-ref args 0))
        (hash))))

(define (json-val->opt v)
  (if (eq? v 'null) #f v))

(define min-size (inexact->exact (hash-ref params 'min_size 0)))
(define max-size (let ([v (json-val->opt (hash-ref params 'max_size 'null))])
                   (and v (inexact->exact v))))
(define min-val  (let ([v (json-val->opt (hash-ref params 'min_value 'null))])
                   (and v (inexact->exact v))))
(define max-val  (let ([v (json-val->opt (hash-ref params 'max_value 'null))])
                   (and v (inexact->exact v))))
(define unique   (hash-ref params 'unique #f))
(define mode     (hash-ref params 'mode "basic"))

(define test-cases (get-test-cases))
(define elem-gen
  (integers #:min-value min-val
            #:max-value max-val))

(define elem-gen-used
  (if (equal? mode "non_basic")
      (make-non-basic elem-gen)
      elem-gen))

(define gen
  (lists elem-gen-used
         #:min-size min-size
         #:max-size max-size
         #:unique (if (boolean? unique) unique #f)))

(run-hegel
 (lambda (tc)
   (define value (draw tc gen))
   (define size (length value))
   (define metrics
     (if (> size 0)
         (hash 'size size
               'min_element (apply min value)
               'max_element (apply max value))
         (hash 'size size)))
   (write-metrics metrics))
 #:test-cases test-cases)
