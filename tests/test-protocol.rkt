#lang racket/base

;;; Unit tests for the wire protocol: CRC32, packet encode/decode, CBOR.

(require rackunit
         rackunit/text-ui
         (file "../protocol.rkt"))

;; ---------------------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------------------

(define (packet-round-trip pkt)
  (define out (open-output-bytes))
  (write-packet pkt out)
  (define in (open-input-bytes (get-output-bytes out)))
  (read-packet in))

;; ---------------------------------------------------------------------------
;; Packet round-trips
;; ---------------------------------------------------------------------------

(define protocol-tests
  (test-suite
   "Protocol tests"

   (test-suite
    "Packet round-trips"

    (test-case "simple request"
      (define pkt (packet 0 1 #f #"hello"))
      (define result (packet-round-trip pkt))
      (check-equal? (packet-stream result)     0)
      (check-equal? (packet-message-id result) 1)
      (check-equal? (packet-is-reply result)   #f)
      (check-equal? (packet-payload result)    #"hello"))

    (test-case "reply packet"
      (define pkt (packet 3 7 #t #"world"))
      (define result (packet-round-trip pkt))
      (check-equal? (packet-stream result)     3)
      (check-equal? (packet-message-id result) 7)
      (check-equal? (packet-is-reply result)   #t)
      (check-equal? (packet-payload result)    #"world"))

    (test-case "empty payload"
      (define pkt (packet 0 0 #f #""))
      (define result (packet-round-trip pkt))
      (check-equal? (packet-payload result) #""))

    (test-case "large stream id"
      (define pkt (packet 999 42 #f #"data"))
      (define result (packet-round-trip pkt))
      (check-equal? (packet-stream result) 999))

    (test-case "binary payload"
      (define pkt (packet 1 1 #f #"\x00\xff\x80\x7f"))
      (define result (packet-round-trip pkt))
      (check-equal? (packet-payload result) #"\x00\xff\x80\x7f"))

    (test-case "large payload"
      (define payload (make-bytes 1000 #x42))
      (define pkt (packet 0 1 #f payload))
      (define result (packet-round-trip pkt))
      (check-equal? (packet-payload result) payload)))

   (test-suite
    "Packet read errors"

    (test-case "invalid magic"
      (define out (open-output-bytes))
      (write-packet (packet 0 1 #f #"x") out)
      (define raw (get-output-bytes out))
      ;; Corrupt the magic bytes
      (bytes-set! raw 0 #x00)
      (define in (open-input-bytes raw))
      (check-exn exn:fail? (lambda () (read-packet in))))

    (test-case "CRC mismatch"
      (define out (open-output-bytes))
      (write-packet (packet 0 1 #f #"x") out)
      (define raw (get-output-bytes out))
      ;; Corrupt a byte in the payload area
      (define last-idx (- (bytes-length raw) 2))
      (bytes-set! raw last-idx (bitwise-xor (bytes-ref raw last-idx) #xFF))
      (define in (open-input-bytes raw))
      (check-exn exn:fail? (lambda () (read-packet in))))

    (test-case "invalid terminator"
      (define out (open-output-bytes))
      (write-packet (packet 0 1 #f #"x") out)
      (define raw (get-output-bytes out))
      ;; Corrupt the terminator byte (last byte)
      (define last-idx (- (bytes-length raw) 1))
      ;; Change terminator but keep CRC valid by recomputing
      ;; Actually, just change the terminator - CRC covers header+payload, not terminator
      ;; So we need the packet to otherwise be valid but have a bad terminator.
      ;; The simplest way is to patch raw: the terminator is the very last byte.
      ;; But if we change it, the CRC is still valid (CRC doesn't cover terminator).
      ;; So the bad terminator error fires AFTER the CRC check.
      ;; We need a packet where CRC is valid but terminator is wrong.
      ;; Let's build one manually.
      (define bad-raw (bytes-append
                       (subbytes raw 0 (- (bytes-length raw) 1))
                       #"\xFF"))
      (define in (open-input-bytes bad-raw))
      (check-exn exn:fail? (lambda () (read-packet in))))

    (test-case "connection closed - header"
      (define in (open-input-bytes #""))
      (check-exn exn:fail? (lambda () (read-packet in))))

    (test-case "connection closed - payload"
      ;; Write just the header with no payload
      (define out (open-output-bytes))
      (write-packet (packet 0 1 #f #"hello") out)
      (define raw (get-output-bytes out))
      ;; Truncate at header (20 bytes)
      (define truncated (subbytes raw 0 20))
      ;; Re-compute: the header says payload length = 5. We give 0.
      ;; Actually the header length field matters. The truncated bytes won't match.
      ;; Let's just give a too-short byte string.
      (define in (open-input-bytes truncated))
      (check-exn exn:fail? (lambda () (read-packet in)))))

   ;; ---------------------------------------------------------------------------
   ;; CBOR round-trips
   ;; ---------------------------------------------------------------------------

   (test-suite
    "CBOR encode/decode"

    (test-case "integer"
      (check-equal? (cbor-decode-value (cbor-encode-value 42)) 42))

    (test-case "negative integer"
      (check-equal? (cbor-decode-value (cbor-encode-value -17)) -17))

    (test-case "boolean true"
      (check-equal? (cbor-decode-value (cbor-encode-value #t)) #t))

    (test-case "boolean false"
      (check-equal? (cbor-decode-value (cbor-encode-value #f)) #f))

    (test-case "null"
      (check-equal? (cbor-decode-value (cbor-encode-value 'null)) 'null))

    (test-case "string"
      (check-equal? (cbor-decode-value (cbor-encode-value "hello")) "hello"))

    (test-case "bytes"
      (check-equal? (cbor-decode-value (cbor-encode-value #"bytes")) #"bytes"))

    (test-case "hash with string keys"
      (define h (hash "a" 1 "b" 2))
      (define result (cbor-decode-value (cbor-encode-value h)))
      (check-equal? (hash-ref result "a") 1)
      (check-equal? (hash-ref result "b") 2))

    (test-case "list"
      (define lst (list 1 2 3))
      (define result (cbor-decode-value (cbor-encode-value lst)))
      ;; CBOR arrays may come back as list or vector depending on library
      (define result-list (if (list? result) result (vector->list result)))
      (check-equal? result-list (list 1 2 3)))

    (test-case "float"
      (define v 3.14)
      (define result (cbor-decode-value (cbor-encode-value v)))
      (check-true (< (abs (- result v)) 1e-10)))

    (test-case "nested hash"
      (define h (hash "cmd" "generate" "schema" (hash "type" "integer")))
      (define result (cbor-decode-value (cbor-encode-value h)))
      (check-equal? (hash-ref result "cmd") "generate")
      (define schema (hash-ref result "schema"))
      (check-equal? (hash-ref schema "type") "integer"))

    (test-case "CBOR tag 91 with invalid UTF-8 triggers wtf8-decode fallback"
      ;; Tag 91 (0xD8 0x5B) + bytes(0xFF) is invalid UTF-8 → fallback to latin-1
      ;; CBOR: 0xD8 0x5B = tag 91, 0x41 0xFF = bytes of length 1 containing 0xFF
      (define result (cbor-decode-value #"\xD8\x5B\x41\xFF"))
      ;; Should return the latin-1 char U+00FF, not crash
      (check-pred string? result))

    (test-case "CBOR tag 91 with non-bytes content falls back to format"
      ;; Tag 91 with integer content: format "~a" → string of integer
      ;; 0xD8 0x5B = tag 91, 0x18 0x2A = integer 42
      (define result (cbor-decode-value #"\xD8\x5B\x18\x2A"))
      (check-pred string? result)))

))

(run-tests protocol-tests)
