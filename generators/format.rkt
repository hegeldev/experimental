#lang racket/base

;;; Format generators: emails, urls, domains, IP addresses, dates, times, datetimes, regex.

(require racket/contract
         "core.rkt"
         "misc.rkt")

(provide
 (contract-out
  [emails      (->* () () generator?)]
  [urls        (->* () () generator?)]
  [domains     (->* () () generator?)]
  [ipv4-addresses (->* () () generator?)]
  [ipv6-addresses (->* () () generator?)]
  [ip-addresses   (->* () () generator?)]
  [dates       (->* () () generator?)]
  [times       (->* () () generator?)]
  [datetimes   (->* () () generator?)]
  [from-regex  (->* (string?) () generator?)]))

;; ---------------------------------------------------------------------------
;; Format generators
;; ---------------------------------------------------------------------------

(define (emails)
  (make-basic-generator (hash "type" "email")))

(define (urls)
  (make-basic-generator (hash "type" "url")))

(define (domains)
  (make-basic-generator (hash "type" "domain")))

(define (ipv4-addresses)
  (make-basic-generator (hash "type" "ipv4")))

(define (ipv6-addresses)
  (make-basic-generator (hash "type" "ipv6")))

(define (ip-addresses)
  ;; hegel-core has no "ip_address" schema type; use one-of ipv4/ipv6
  (one-of (ipv4-addresses) (ipv6-addresses)))

(define (dates)
  (make-basic-generator (hash "type" "date")))

(define (times)
  (make-basic-generator (hash "type" "time")))

(define (datetimes)
  (make-basic-generator (hash "type" "datetime")))

(define (from-regex pattern)
  (make-basic-generator (hash "type" "regex" "pattern" pattern "fullmatch" #t)))
