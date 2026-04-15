#lang racket/base

;;; TestCase: per-test-case state passed explicitly to test functions.
;;;
;;; Provides assume, note, span management, and the Collection
;;; struct for server-managed collection sizing.
;;;
;;; Note: the draw function is defined in generators/core.rkt to avoid
;;; a circular dependency between test-case and generators.

(require racket/contract
         racket/format)

(provide
 ;; Error types
 exn:fail:stop-test?
 exn:fail:assume?
 raise-stop-test
 raise-assume-failed

 ;; Span labels
 LABEL-LIST
 LABEL-LIST-ELEMENT
 LABEL-SET
 LABEL-SET-ELEMENT
 LABEL-MAP
 LABEL-MAP-ENTRY
 LABEL-TUPLE
 LABEL-ONE-OF
 LABEL-OPTIONAL
 LABEL-FIXED-DICT
 LABEL-FLAT-MAP
 LABEL-FILTER
 LABEL-MAPPED
 LABEL-SAMPLED-FROM
 LABEL-ENUM-VARIANT

 ;; DataSource interface
 (contract-out
  [make-data-source
   (-> (-> hash? any/c)                                                   ; generate
       (-> exact-nonnegative-integer? void?)                              ; start-span
       (-> boolean? void?)                                                ; stop-span
       (-> exact-nonnegative-integer? (or/c exact-nonnegative-integer? #f) exact-nonnegative-integer?) ; new-collection
       (-> exact-nonnegative-integer? boolean?)                           ; collection-more
       (-> exact-nonnegative-integer? (or/c string? #f) void?)            ; collection-reject
       (-> string? (or/c string? #f) void?)                              ; mark-complete
       (-> boolean?)                                                      ; test-aborted?
       data-source?)]
  [data-source? (-> any/c boolean?)]
  [data-source-generate  (-> data-source? hash? any/c)]
  [data-source-start-span (-> data-source? exact-nonnegative-integer? void?)]
  [data-source-stop-span  (-> data-source? boolean? void?)]
  [data-source-new-collection  (-> data-source? exact-nonnegative-integer? (or/c exact-nonnegative-integer? #f) exact-nonnegative-integer?)]
  [data-source-collection-more (-> data-source? exact-nonnegative-integer? boolean?)]
  [data-source-collection-reject (-> data-source? exact-nonnegative-integer? (or/c string? #f) void?)]
  [data-source-mark-complete (-> data-source? string? (or/c string? #f) void?)]
  [data-source-test-aborted? (-> data-source? boolean?)])

 ;; TestCase
 (contract-out
  [make-test-case (-> data-source? boolean? test-case?)]
  [test-case?     (-> any/c boolean?)]
  [test-case-ds         (-> test-case? data-source?)]
  [test-case-last-run?  (-> test-case? boolean?)]
  [test-case-draw-count (-> test-case? (box/c exact-nonnegative-integer?))]
  [test-case-span-depth (-> test-case? (box/c exact-nonnegative-integer?))])

 tc-assume
 tc-note
 tc-start-span
 tc-stop-span
 tc-test-aborted?
 tc-record-draw!
 generate-raw

 ;; Collection
 (contract-out
  [make-collection (-> data-source? exact-nonnegative-integer? (or/c exact-nonnegative-integer? #f) collection?)]
  [collection?     (-> any/c boolean?)]
  [collection-more   (-> collection? boolean?)]
  [collection-reject (-> collection? (or/c string? #f) void?)]))

;; ---------------------------------------------------------------------------
;; Error types
;; ---------------------------------------------------------------------------

(struct exn:fail:stop-test exn:fail ()
  #:transparent
  #:extra-constructor-name make-stop-test)

(struct exn:fail:assume exn:fail ()
  #:transparent
  #:extra-constructor-name make-assume)

(define (raise-stop-test)
  (raise (make-stop-test "Server ran out of data (StopTest)"
                         (current-continuation-marks))))

(define (raise-assume-failed)
  (raise (make-assume "Assumption rejected"
                      (current-continuation-marks))))

;; ---------------------------------------------------------------------------
;; Span labels
;; ---------------------------------------------------------------------------

(define LABEL-LIST         1)
(define LABEL-LIST-ELEMENT 2)
(define LABEL-SET          3)
(define LABEL-SET-ELEMENT  4)
(define LABEL-MAP          5)
(define LABEL-MAP-ENTRY    6)
(define LABEL-TUPLE        7)
(define LABEL-ONE-OF       8)
(define LABEL-OPTIONAL     9)
(define LABEL-FIXED-DICT   10)
(define LABEL-FLAT-MAP     11)
(define LABEL-FILTER       12)
(define LABEL-MAPPED       13)
(define LABEL-SAMPLED-FROM 14)
(define LABEL-ENUM-VARIANT 15)

;; ---------------------------------------------------------------------------
;; DataSource
;; ---------------------------------------------------------------------------

(struct data-source
  (generate-fn
   start-span-fn
   stop-span-fn
   new-collection-fn
   collection-more-fn
   collection-reject-fn
   mark-complete-fn
   test-aborted?-fn)
  #:transparent)

(define (make-data-source gen-fn start-fn stop-fn new-coll-fn more-fn reject-fn complete-fn aborted?-fn)
  (data-source gen-fn start-fn stop-fn new-coll-fn more-fn reject-fn complete-fn aborted?-fn))

(define (data-source-generate ds schema)
  ((data-source-generate-fn ds) schema))

(define (data-source-start-span ds label)
  ((data-source-start-span-fn ds) label))

(define (data-source-stop-span ds discard)
  ((data-source-stop-span-fn ds) discard))

(define (data-source-new-collection ds min-size max-size)
  ((data-source-new-collection-fn ds) min-size max-size))

(define (data-source-collection-more ds coll-id)
  ((data-source-collection-more-fn ds) coll-id))

(define (data-source-collection-reject ds coll-id why)
  ((data-source-collection-reject-fn ds) coll-id why))

(define (data-source-mark-complete ds status origin)
  ((data-source-mark-complete-fn ds) status origin))

(define (data-source-test-aborted? ds)
  ((data-source-test-aborted?-fn ds)))

;; ---------------------------------------------------------------------------
;; TestCase
;; ---------------------------------------------------------------------------

(struct test-case
  (ds last-run? draw-count span-depth)
  #:transparent)

(define (make-test-case ds last-run?)
  (test-case ds last-run? (box 0) (box 0)))

(define (tc-test-aborted? tc)
  (data-source-test-aborted? (test-case-ds tc)))

;; Called by draw in generators/core.rkt to record the draw and print if final run
(define (tc-record-draw! tc value)
  (unless (> (unbox (test-case-span-depth tc)) 0)
    (set-box! (test-case-draw-count tc) (+ (unbox (test-case-draw-count tc)) 1))
    (when (test-case-last-run? tc)
      (define n (unbox (test-case-draw-count tc)))
      (eprintf "var draw_~a = ~a;\n" n (~v value)))))

(define (tc-assume tc condition)
  (unless condition
    (raise-assume-failed)))

(define (tc-note tc message)
  (when (test-case-last-run? tc)
    (eprintf "~a\n" message)))

(define (tc-start-span tc label)
  (set-box! (test-case-span-depth tc) (+ (unbox (test-case-span-depth tc)) 1))
  (with-handlers ([exn:fail? (lambda (e)
                               (set-box! (test-case-span-depth tc)
                                         (- (unbox (test-case-span-depth tc)) 1))
                               (raise e))])
    (data-source-start-span (test-case-ds tc) label)))

(define (tc-stop-span tc [discard #f])
  (set-box! (test-case-span-depth tc) (- (unbox (test-case-span-depth tc)) 1))
  (with-handlers ([exn:fail? void])
    (data-source-stop-span (test-case-ds tc) discard)))

(define (generate-raw tc schema)
  (data-source-generate (test-case-ds tc) schema))

;; ---------------------------------------------------------------------------
;; Collection
;; ---------------------------------------------------------------------------

(struct collection
  (ds min-size max-size coll-id finished)
  #:transparent)

(define (make-collection ds min-size max-size)
  (collection ds min-size max-size (box #f) (box #f)))

(define (collection-ensure-initialized! coll)
  (unless (unbox (collection-coll-id coll))
    (set-box! (collection-coll-id coll)
              (data-source-new-collection
               (collection-ds coll)
               (collection-min-size coll)
               (collection-max-size coll))))
  (unbox (collection-coll-id coll)))

(define (collection-more coll)
  (if (unbox (collection-finished coll))
      #f
      (let ([cid (collection-ensure-initialized! coll)])
        (define result
          (with-handlers ([exn:fail? (lambda (e)
                                       (set-box! (collection-finished coll) #t)
                                       (raise e))])
            (data-source-collection-more (collection-ds coll) cid)))
        (unless result
          (set-box! (collection-finished coll) #t))
        result)))

(define (collection-reject coll why)
  (unless (unbox (collection-finished coll))
    (define cid (collection-ensure-initialized! coll))
    (data-source-collection-reject (collection-ds coll) cid why)))
