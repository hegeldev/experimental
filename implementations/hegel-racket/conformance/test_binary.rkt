#!/usr/bin/env racket
#lang racket/base

;;; Conformance binary for binary (bytes) generation.
;;;
;;; Params (JSON from argv[1]): { min_size?: number, max_size?: number|null }
;;; Metrics: { length: number }

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

(define test-cases (get-test-cases))
(define gen
  (binary #:min-size min-size
          #:max-size max-size))

(run-hegel
 (lambda (tc)
   (define value (draw tc gen))
   (write-metrics (hash 'length (bytes-length value))))
 #:test-cases test-cases)
