#lang racket/base

;;; Conformance testing helpers.
;;;
;;; Used by conformance binary scripts to read test configuration from
;;; environment variables and write per-test-case metrics to the
;;; conformance metrics file.

(require racket/contract
         racket/port
         racket/string
         json
         "generators/core.rkt"
         "test-case.rkt")

(provide
 (contract-out
  [get-test-cases  (-> exact-nonnegative-integer?)]
  [write-metrics   (-> jsexpr? void?)]
  [make-non-basic  (-> generator? generator?)]))

;; ---------------------------------------------------------------------------
;; get-test-cases
;; ---------------------------------------------------------------------------

(define (get-test-cases)
  (define val (getenv "CONFORMANCE_TEST_CASES"))
  (if (not val)
      50
      (let ([n (string->number val)])
        (if (and n (exact-positive-integer? n))
            n
            50))))

;; ---------------------------------------------------------------------------
;; write-metrics
;; ---------------------------------------------------------------------------

(define (escape-unicode-linebreaks s)
  ;; Python's splitlines() splits on U+0085, U+2028, U+2029
  ;; Escape these to avoid breaking JSONL parsing
  (string-replace
   (string-replace
    (string-replace s "\u0085" "\\u0085")
    "\u2028" "\\u2028")
   "\u2029" "\\u2029"))

(define (write-metrics metrics)
  (define path (getenv "CONFORMANCE_METRICS_FILE"))
  (unless path
    (error 'write-metrics "hegel: CONFORMANCE_METRICS_FILE env var not set"))
  (define json-str (with-output-to-string (lambda () (write-json metrics))))
  (define escaped (escape-unicode-linebreaks json-str))
  (call-with-output-file path
    (lambda (out)
      (display escaped out)
      (newline out))
    #:exists 'append))

;; ---------------------------------------------------------------------------
;; make-non-basic
;; ---------------------------------------------------------------------------

(define (always-true _) #t)

(define (make-non-basic gen)
  ;; Wrap with a filter that always returns true, making it non-basic
  (generator-filter gen always-true))
