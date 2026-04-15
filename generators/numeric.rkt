#lang racket/base

;;; Numeric and boolean generators.

(require racket/contract
         "core.rkt")

(provide
 (contract-out
  [integers (->* ()
                 (#:min-value (or/c exact-integer? #f)
                  #:max-value (or/c exact-integer? #f))
                 generator?)]
  [floats   (->* ()
                 (#:min-value (or/c real? #f)
                  #:max-value (or/c real? #f)
                  #:exclude-min boolean?
                  #:exclude-max boolean?
                  #:allow-nan boolean?
                  #:allow-infinity boolean?)
                 generator?)]
  [booleans (->* () (#:p (real-in 0.0 1.0)) generator?)]))

;; ---------------------------------------------------------------------------
;; Integers
;; ---------------------------------------------------------------------------

(define (integers #:min-value [min-value #f]
                  #:max-value [max-value #f])
  (when (and min-value max-value (> min-value max-value))
    (error 'integers "min-value must be <= max-value"))
  (define schema
    (let ([h (make-hash '(("type" . "integer")))])
      (when min-value (hash-set! h "min_value" min-value))
      (when max-value (hash-set! h "max_value" max-value))
      h))
  (make-basic-generator schema))

;; ---------------------------------------------------------------------------
;; Floats
;; ---------------------------------------------------------------------------

(define (floats #:min-value    [min-value #f]
                #:max-value    [max-value #f]
                #:exclude-min  [exclude-min #f]
                #:exclude-max  [exclude-max #f]
                #:allow-nan    [allow-nan (and (not min-value) (not max-value))]
                #:allow-infinity [allow-infinity (or (not min-value) (not max-value))])
  (define schema
    (let ([h (make-hash)])
      (hash-set! h "type" "float")
      (hash-set! h "width" 64)
      (hash-set! h "allow_nan" allow-nan)
      (hash-set! h "allow_infinity" allow-infinity)
      (when min-value
        (hash-set! h "min_value" (exact->inexact min-value))
        (hash-set! h "exclude_min" exclude-min))
      (when max-value
        (hash-set! h "max_value" (exact->inexact max-value))
        (hash-set! h "exclude_max" exclude-max))
      h))
  (define (coerce-float raw)
    (cond
      [(flonum? raw) raw]
      [(exact-integer? raw) (exact->inexact raw)]
      [else raw]))
  (make-basic-generator schema coerce-float))

;; ---------------------------------------------------------------------------
;; Booleans
;; ---------------------------------------------------------------------------

(define (booleans #:p [p #f])
  (define schema
    (if p
        (hash "type" "boolean" "p" p)
        (hash "type" "boolean")))
  (make-basic-generator schema))
