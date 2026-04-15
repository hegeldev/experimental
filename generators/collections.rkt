#lang racket/base

;;; List, tuple, dict/hashmap generators.

(require racket/contract
         racket/list
         "../test-case.rkt"
         "core.rkt")

(provide
 (contract-out
  [lists  (->* (generator?)
               (#:min-size exact-nonnegative-integer?
                #:max-size (or/c exact-nonnegative-integer? #f)
                #:unique   boolean?)
               generator?)]
  [tuples (-> generator? ... generator?)]
  [dicts  (->* (generator? generator?)
               (#:min-size exact-nonnegative-integer?
                #:max-size (or/c exact-nonnegative-integer? #f))
               generator?)]
  [hashmaps (->* (generator? generator?)
                 (#:min-size exact-nonnegative-integer?
                  #:max-size (or/c exact-nonnegative-integer? #f))
                 generator?)]))

;; ---------------------------------------------------------------------------
;; Lists
;; ---------------------------------------------------------------------------

(define (lists elem-gen
               #:min-size [min-size 0]
               #:max-size [max-size #f]
               #:unique   [unique #f])
  (define bs (generator-as-basic elem-gen))
  (if (and bs (not unique))
      ;; Basic path: compose schemas
      (lists-basic elem-gen bs min-size max-size)
      ;; Non-basic path: collection protocol
      (lists-non-basic elem-gen min-size max-size unique)))

(define (lists-basic elem-gen bs min-size max-size)
  (define elem-schema (basic-schema-schema bs))
  (define elem-transform (basic-schema-transform bs))
  (define list-schema
    (let ([h (make-hash)])
      (hash-set! h "type" "list")
      (hash-set! h "elements" elem-schema)
      (hash-set! h "min_size" min-size)
      (when max-size (hash-set! h "max_size" max-size))
      h))
  (define (transform raw)
    ;; raw is a list of values from the server (CBOR arrays decode as Racket lists)
    (if elem-transform
        (map elem-transform raw)
        raw))
  (make-basic-generator list-schema transform))

(define (lists-non-basic elem-gen min-size max-size unique)
  (generator
   (lambda (tc)
     (tc-start-span tc LABEL-LIST)
     (define ds (test-case-ds tc))
     (define coll (make-collection ds min-size max-size))
     (define result
       (let loop ([acc '()])
         (if (not (collection-more coll))
             (reverse acc)
             (begin
               (tc-start-span tc LABEL-LIST-ELEMENT)
               (let ([v ((generator-draw-fn elem-gen) tc)])
                 (cond
                   [(and unique (member v acc))
                    (collection-reject coll "duplicate element")
                    (tc-stop-span tc #t)
                    (loop acc)]
                   [else
                    (tc-stop-span tc #f)
                    (loop (cons v acc))]))))))
     (tc-stop-span tc #f)
     result)
   (lambda () #f)))

;; ---------------------------------------------------------------------------
;; Tuples
;; ---------------------------------------------------------------------------

(define (tuples . elem-gens)
  (define basics (map generator-as-basic elem-gens))
  (if (andmap (lambda (x) x) basics)
      ;; All basic: compose schemas
      (tuples-basic elem-gens basics)
      ;; Non-basic: generate each element individually
      (tuples-non-basic elem-gens)))

(define (tuples-basic elem-gens basics)
  (define schemas (map basic-schema-schema basics))
  (define transforms (map basic-schema-transform basics))
  (define tuple-schema (hash "type" "tuple" "elements" schemas))
  (define (transform raw)
    ;; raw is a list of values from server (CBOR arrays decode as Racket lists)
    (map (lambda (v t) (if t (t v) v)) raw transforms))
  (make-basic-generator tuple-schema transform))

(define (tuples-non-basic elem-gens)
  (generator
   (lambda (tc)
     (tc-start-span tc LABEL-TUPLE)
     (define result
       (for/list ([gen (in-list elem-gens)])
         ((generator-draw-fn gen) tc)))
     (tc-stop-span tc #f)
     result)
   (lambda () #f)))

;; ---------------------------------------------------------------------------
;; Dicts / Hashmaps
;; ---------------------------------------------------------------------------

(define (dicts key-gen val-gen
               #:min-size [min-size 0]
               #:max-size [max-size #f])
  (hashmaps key-gen val-gen #:min-size min-size #:max-size max-size))

(define (hashmaps key-gen val-gen
                  #:min-size [min-size 0]
                  #:max-size [max-size #f])
  (define key-bs (generator-as-basic key-gen))
  (define val-bs (generator-as-basic val-gen))
  (if (and key-bs val-bs)
      (hashmaps-basic key-gen key-bs val-gen val-bs min-size max-size)
      (hashmaps-non-basic key-gen val-gen min-size max-size)))

(define (hashmaps-basic key-gen key-bs val-gen val-bs min-size max-size)
  (define key-schema (basic-schema-schema key-bs))
  (define val-schema (basic-schema-schema val-bs))
  (define key-transform (basic-schema-transform key-bs))
  (define val-transform (basic-schema-transform val-bs))
  (define dict-schema
    (let ([h (make-hash)])
      (hash-set! h "type" "dict")
      (hash-set! h "keys" key-schema)
      (hash-set! h "values" val-schema)
      (hash-set! h "min_size" min-size)
      (when max-size (hash-set! h "max_size" max-size))
      h))
  (define (transform raw)
    ;; raw is a list of [key, value] pairs (CBOR arrays decode as Racket lists)
    (define result (make-hash))
    (for ([pair (in-list raw)])
      (define k (if key-transform (key-transform (car pair)) (car pair)))
      (define v (if val-transform (val-transform (cadr pair)) (cadr pair)))
      (hash-set! result k v))
    result)
  (make-basic-generator dict-schema transform))

(define (hashmaps-non-basic key-gen val-gen min-size max-size)
  (generator
   (lambda (tc)
     (tc-start-span tc LABEL-MAP)
     (define ds (test-case-ds tc))
     (define coll (make-collection ds min-size max-size))
     (define result (make-hash))
     (let loop ()
       (when (collection-more coll)
         (tc-start-span tc LABEL-MAP-ENTRY)
         (define k ((generator-draw-fn key-gen) tc))
         (define v ((generator-draw-fn val-gen) tc))
         (cond
           [(hash-has-key? result k)
            (collection-reject coll "duplicate key")
            (tc-stop-span tc #t)]
           [else
            (hash-set! result k v)
            (tc-stop-span tc #f)])
         (loop)))
     (tc-stop-span tc #f)
     result)
   (lambda () #f)))
