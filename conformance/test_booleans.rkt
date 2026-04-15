#!/usr/bin/env racket
#lang racket/base

;;; Conformance binary for boolean generation.
;;;
;;; Params (JSON from argv[1]): { p?: number }
;;; Metrics: { value: boolean }

(require json
         (file "../main.rkt")
         (file "../conformance.rkt"))

(define params
  (let ([args (current-command-line-arguments)])
    (if (> (vector-length args) 0)
        (string->jsexpr (vector-ref args 0))
        (hash))))

(define p-val (hash-ref params 'p #f))

(define test-cases (get-test-cases))
(define gen
  (if p-val
      (booleans #:p p-val)
      (booleans)))

(run-hegel
 (lambda (tc)
   (define value (draw tc gen))
   (write-metrics (hash 'value value)))
 #:test-cases test-cases)
