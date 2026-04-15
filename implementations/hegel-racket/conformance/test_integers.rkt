#!/usr/bin/env racket
#lang racket/base

;;; Conformance binary for integer generation.
;;;
;;; Params (JSON from argv[1]): { min_value?: number|null, max_value?: number|null }
;;; Metrics: { value: number }

(require json
         (file "../main.rkt")
         (file "../conformance.rkt"))

(define params
  (let ([args (current-command-line-arguments)])
    (if (> (vector-length args) 0)
        (string->jsexpr (vector-ref args 0))
        (hash))))

(define min-val (hash-ref params 'min_value #f))
(define max-val (hash-ref params 'max_value #f))

(define test-cases (get-test-cases))
(define gen
  (integers #:min-value (and min-val (inexact->exact min-val))
            #:max-value (and max-val (inexact->exact max-val))))

(run-hegel
 (lambda (tc)
   (define value (draw tc gen))
   (write-metrics (hash 'value value)))
 #:test-cases test-cases)
