#!/usr/bin/env racket
#lang racket/base

;;; Conformance binary for sampled-from generation.
;;;
;;; Params (JSON from argv[1]): { options: any[] }
;;; Metrics: { value: any }

(require json
         (file "../main.rkt")
         (file "../conformance.rkt"))

(define params
  (let ([args (current-command-line-arguments)])
    (if (> (vector-length args) 0)
        (string->jsexpr (vector-ref args 0))
        (hash))))

;; Params use "options" key; JSON arrays are Racket lists
(define options (hash-ref params 'options '(1 2 3)))

(define test-cases (get-test-cases))
(define gen (sampled-from options))

(run-hegel
 (lambda (tc)
   (define value (draw tc gen))
   (write-metrics (hash 'value value)))
 #:test-cases test-cases)
