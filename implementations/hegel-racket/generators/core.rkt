#lang racket/base

;;; Generator base struct and core combinators.
;;;
;;; A generator is a struct with:
;;;   - draw-fn: (-> test-case? any/c)  - produces a value
;;;   - as-basic-fn: (-> (or/c basic-schema? #f))  - returns schema info if basic
;;;
;;; A basic-schema has:
;;;   - schema: hash?  - the CBOR schema to send to the server
;;;   - transform: (or/c #f (-> any/c any/c))  - optional transform applied to raw value

(require racket/contract
         "../test-case.rkt")

(provide
 (contract-out
  [struct generator
    ((draw-fn     (-> test-case? any/c))
     (as-basic-fn (-> (or/c basic-schema? #f))))]
  [struct basic-schema
    ((schema    hash?)
     (transform (or/c #f (-> any/c any/c))))])
 make-basic-generator
 generator-as-basic
 generator-map
 generator-flat-map
 generator-filter
 draw
 draw-silent)

;; ---------------------------------------------------------------------------
;; Structs
;; ---------------------------------------------------------------------------

(struct generator (draw-fn as-basic-fn) #:transparent)

(struct basic-schema (schema transform) #:transparent)

;; ---------------------------------------------------------------------------
;; Constructors
;; ---------------------------------------------------------------------------

(define (make-basic-generator schema [transform #f])
  (define bs (basic-schema schema transform))
  (generator
   ;; draw-fn
   (lambda (tc)
     (define raw (generate-raw tc schema))
     (if transform (transform raw) raw))
   ;; as-basic-fn
   (lambda () bs)))

(define (generator-as-basic gen)
  ((generator-as-basic-fn gen)))

;; ---------------------------------------------------------------------------
;; draw / draw-silent
;; ---------------------------------------------------------------------------

(define (draw tc gen)
  (define value ((generator-draw-fn gen) tc))
  (tc-record-draw! tc value)
  value)

(define (draw-silent tc gen)
  ((generator-draw-fn gen) tc))

;; ---------------------------------------------------------------------------
;; map
;; ---------------------------------------------------------------------------

(define (generator-map gen f)
  (define bs (generator-as-basic gen))
  (if bs
      ;; Basic: compose the transform
      (let* ([old-transform (basic-schema-transform bs)]
             [new-transform (if old-transform
                                (lambda (raw) (f (old-transform raw)))
                                f)]
             [new-bs (basic-schema (basic-schema-schema bs) new-transform)])
        (generator
         (lambda (tc)
           (define raw (generate-raw tc (basic-schema-schema new-bs)))
           (f (if old-transform (old-transform raw) raw)))
         (lambda () new-bs)))
      ;; Non-basic: use a MAPPED span
      (generator
       (lambda (tc)
         (tc-start-span tc LABEL-MAPPED)
         (define result (f ((generator-draw-fn gen) tc)))
         (tc-stop-span tc #f)
         result)
       (lambda () #f))))

;; ---------------------------------------------------------------------------
;; flat-map
;; ---------------------------------------------------------------------------

(define (generator-flat-map gen f)
  (generator
   (lambda (tc)
     (tc-start-span tc LABEL-FLAT-MAP)
     (define intermediate ((generator-draw-fn gen) tc))
     (define next-gen (f intermediate))
     (define result ((generator-draw-fn next-gen) tc))
     (tc-stop-span tc #f)
     result)
   (lambda () #f)))

;; ---------------------------------------------------------------------------
;; filter
;; ---------------------------------------------------------------------------

(define (generator-filter gen pred)
  (generator
   (lambda (tc)
     (let loop ([i 0])
       (when (= i 3)
         (tc-assume tc #f))
       (tc-start-span tc LABEL-FILTER)
       (define value ((generator-draw-fn gen) tc))
       (if (pred value)
           (begin (tc-stop-span tc #f) value)
           (begin (tc-stop-span tc #t) (loop (+ i 1))))))
   (lambda () #f)))
