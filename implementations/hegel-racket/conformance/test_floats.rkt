#!/usr/bin/env racket
#lang racket/base

;;; Conformance binary for float generation.
;;;
;;; Params (JSON from argv[1]): { min_value?: number|null, max_value?: number|null,
;;;                               exclude_min?: boolean, exclude_max?: boolean,
;;;                               allow_nan?: boolean|null, allow_infinity?: boolean|null }
;;; Metrics: { value: number } | { is_nan: true } | { is_infinite: true }

(require json
         racket/math
         (file "../main.rkt")
         (file "../conformance.rkt"))

(define params
  (let ([args (current-command-line-arguments)])
    (if (> (vector-length args) 0)
        (string->jsexpr (vector-ref args 0))
        (hash))))

;; json-val->opt: JSON null → #f (no bound), any other value → that value
(define (json-val->opt v)
  (if (eq? v 'null) #f v))

;; json-bool->opt: JSON null → 'unset, JSON true → #t, JSON false → #f
;; Needed to distinguish "user passed false" from "user passed null (use default)"
(define (json-bool->opt v)
  (if (eq? v 'null) 'unset v))

(define min-val    (json-val->opt (hash-ref params 'min_value 'null)))
(define max-val    (json-val->opt (hash-ref params 'max_value 'null)))
(define excl-min   (hash-ref params 'exclude_min #f))
(define excl-max   (hash-ref params 'exclude_max #f))
(define allow-nan-raw (json-bool->opt (hash-ref params 'allow_nan 'null)))
(define allow-inf-raw (json-bool->opt (hash-ref params 'allow_infinity 'null)))

;; When null (unset), use the same defaults as Hypothesis / the floats generator:
;;   allow_nan = not has_min and not has_max
;;   allow_infinity = not has_min or not has_max
(define allow-nan (if (boolean? allow-nan-raw)
                      allow-nan-raw
                      (and (not min-val) (not max-val))))
(define allow-inf (if (boolean? allow-inf-raw)
                      allow-inf-raw
                      (or (not min-val) (not max-val))))

(define test-cases (get-test-cases))
(define gen
  (floats #:min-value min-val
          #:max-value max-val
          #:exclude-min excl-min
          #:exclude-max excl-max
          #:allow-nan allow-nan
          #:allow-infinity allow-inf))

(run-hegel
 (lambda (tc)
   (define value (draw tc gen))
   (define metrics
     (cond
       [(nan? value)      (hash 'is_nan #t)]
       [(infinite? value) (hash 'is_infinite #t)]
       [else              (hash 'value value)]))
   (write-metrics metrics))
 #:test-cases test-cases)
