#lang racket/base

;;; Text and binary generators.

(require racket/contract
         "core.rkt")

(provide
 (contract-out
  [text   (->* ()
               (#:min-size exact-nonnegative-integer?
                #:max-size (or/c exact-nonnegative-integer? #f)
                #:codec    (or/c string? #f)
                #:min-codepoint (or/c exact-nonnegative-integer? #f)
                #:max-codepoint (or/c exact-nonnegative-integer? #f)
                #:categories (or/c (listof string?) #f)
                #:exclude-categories (or/c (listof string?) #f)
                #:include-characters (or/c string? #f)
                #:exclude-characters (or/c string? #f))
               generator?)]
  [binary (->* ()
               (#:min-size exact-nonnegative-integer?
                #:max-size (or/c exact-nonnegative-integer? #f))
               generator?)]))

;; ---------------------------------------------------------------------------
;; Text
;; ---------------------------------------------------------------------------

(define (text #:min-size [min-size 0]
              #:max-size [max-size #f]
              #:codec [codec #f]
              #:min-codepoint [min-codepoint #f]
              #:max-codepoint [max-codepoint #f]
              #:categories [categories #f]
              #:exclude-categories [exclude-categories #f]
              #:include-characters [include-characters #f]
              #:exclude-characters [exclude-characters #f])
  (define schema
    (let ([h (make-hash)])
      (hash-set! h "type" "string")
      (hash-set! h "min_size" min-size)
      (when max-size (hash-set! h "max_size" max-size))
      (when codec    (hash-set! h "codec" codec))
      (when min-codepoint (hash-set! h "min_codepoint" min-codepoint))
      (when max-codepoint (hash-set! h "max_codepoint" max-codepoint))
      (when categories (hash-set! h "categories" categories))
      (when exclude-categories (hash-set! h "exclude_categories" exclude-categories))
      (when include-characters (hash-set! h "include_characters" include-characters))
      (when exclude-characters (hash-set! h "exclude_characters" exclude-characters))
      h))
  ;; The server sends strings wrapped in CBOR tag 91 (WTF-8)
  ;; Our CBOR decoder in protocol.rkt handles tag 91 → string
  (make-basic-generator schema))

;; ---------------------------------------------------------------------------
;; Binary
;; ---------------------------------------------------------------------------

(define (binary #:min-size [min-size 0]
                #:max-size [max-size #f])
  (define schema
    (let ([h (make-hash)])
      (hash-set! h "type" "binary")
      (hash-set! h "min_size" min-size)
      (when max-size (hash-set! h "max_size" max-size))
      h))
  (make-basic-generator schema))
