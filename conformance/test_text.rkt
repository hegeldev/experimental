#!/usr/bin/env racket
#lang racket/base

;;; Conformance binary for text (string) generation.
;;;
;;; Params (JSON from argv[1]): { min_size?: number, max_size?: number|null,
;;;                               codec?: string, min_codepoint?: number,
;;;                               max_codepoint?: number, categories?: string[],
;;;                               exclude_categories?: string[],
;;;                               include_characters?: string,
;;;                               exclude_characters?: string }
;;; Metrics: { codepoints: number[] }

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

(define min-size         (inexact->exact (hash-ref params 'min_size 0)))
(define max-size         (let ([v (json-val->opt (hash-ref params 'max_size 'null))])
                           (and v (inexact->exact v))))
(define codec            (json-val->opt (hash-ref params 'codec 'null)))
(define min-codepoint    (let ([v (json-val->opt (hash-ref params 'min_codepoint 'null))])
                           (and v (inexact->exact v))))
(define max-codepoint    (let ([v (json-val->opt (hash-ref params 'max_codepoint 'null))])
                           (and v (inexact->exact v))))
(define categories       (json-val->opt (hash-ref params 'categories 'null)))
(define excl-categories  (json-val->opt (hash-ref params 'exclude_categories 'null)))
(define incl-chars       (json-val->opt (hash-ref params 'include_characters 'null)))
(define excl-chars       (json-val->opt (hash-ref params 'exclude_characters 'null)))

(define test-cases (get-test-cases))
(define gen
  (text #:min-size min-size
        #:max-size max-size
        #:codec codec
        #:min-codepoint min-codepoint
        #:max-codepoint max-codepoint
        #:categories categories
        #:exclude-categories excl-categories
        #:include-characters incl-chars
        #:exclude-characters excl-chars))

(run-hegel
 (lambda (tc)
   (define value (draw tc gen))
   (define codepoints (map char->integer (string->list value)))
   (write-metrics (hash 'codepoints codepoints)))
 #:test-cases test-cases)
