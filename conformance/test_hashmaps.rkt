#!/usr/bin/env racket
#lang racket/base

;;; Conformance binary for dict/hashmap generation.
;;;
;;; Params (JSON from argv[1]): { min_size: number, max_size: number,
;;;                               key_type: "string"|"integer",
;;;                               min_key: number, max_key: number,
;;;                               min_value: number, max_value: number,
;;;                               mode?: "basic"|"non_basic" }
;;; Metrics: { size: number, min_key?: number, max_key?: number,
;;;            min_value?: number, max_value?: number }

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

(define min-size  (inexact->exact (hash-ref params 'min_size 0)))
(define max-size  (let ([v (json-val->opt (hash-ref params 'max_size 'null))])
                    (and v (inexact->exact v))))
(define key-type  (hash-ref params 'key_type "integer"))
(define min-key   (let ([v (json-val->opt (hash-ref params 'min_key 'null))])
                    (and v (inexact->exact v))))
(define max-key   (let ([v (json-val->opt (hash-ref params 'max_key 'null))])
                    (and v (inexact->exact v))))
(define min-val   (let ([v (json-val->opt (hash-ref params 'min_value 'null))])
                    (and v (inexact->exact v))))
(define max-val   (let ([v (json-val->opt (hash-ref params 'max_value 'null))])
                    (and v (inexact->exact v))))
(define mode      (hash-ref params 'mode "basic"))

(define test-cases (get-test-cases))

(define key-gen
  (if (equal? key-type "string")
      (text)
      (integers #:min-value min-key
                #:max-value max-key)))

(define val-gen
  (integers #:min-value min-val
            #:max-value max-val))

(define key-gen-used
  (if (equal? mode "non_basic")
      (make-non-basic key-gen)
      key-gen))
(define val-gen-used
  (if (equal? mode "non_basic")
      (make-non-basic val-gen)
      val-gen))

(define gen
  (hashmaps key-gen-used val-gen-used
            #:min-size min-size
            #:max-size max-size))

(run-hegel
 (lambda (tc)
   (define hmap (draw tc gen))
   (define size (hash-count hmap))
   (define metrics
     (if (= size 0)
         (hash 'size size)
         (let ([vals (hash-values hmap)]
               [keys (hash-keys hmap)])
           (define m (hash 'size size
                           'min_value (apply min vals)
                           'max_value (apply max vals)))
           (if (equal? key-type "integer")
               (hash-set (hash-set m 'min_key (apply min keys))
                         'max_key (apply max keys))
               m))))
   (write-metrics metrics))
 #:test-cases test-cases)
