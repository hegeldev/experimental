#lang racket/base

;;; Wire protocol for communicating with the hegel server.
;;;
;;; Packet format:
;;;   20-byte header: magic(4) + CRC32(4) + stream_id(4) + message_id(4) + payload_length(4)
;;;   Variable-length CBOR payload
;;;   1-byte terminator (0x0A)

(require racket/contract
         cbor)

(provide
 (contract-out
  [struct packet ((stream exact-nonnegative-integer?)
                  (message-id exact-nonnegative-integer?)
                  (is-reply boolean?)
                  (payload bytes?))]
  [write-packet (-> packet? output-port? void?)]
  [read-packet  (-> input-port? packet?)]
  [cbor-encode-value (-> any/c bytes?)]
  [cbor-decode-value (-> bytes? any/c)])
 MAGIC
 HEADER-SIZE
 TERMINATOR
 REPLY-BIT
 CLOSE-STREAM-MESSAGE-ID
 CLOSE-STREAM-PAYLOAD
 HANDSHAKE-STRING)

;; ---------------------------------------------------------------------------
;; Constants
;; ---------------------------------------------------------------------------

(define MAGIC                  #x4845474C)  ; "HEGL"
(define HEADER-SIZE            20)
(define TERMINATOR             #x0A)
(define REPLY-BIT              #x80000000)
(define CLOSE-STREAM-MESSAGE-ID #x7FFFFFFF)
(define CLOSE-STREAM-PAYLOAD   (bytes #xFE))
(define HANDSHAKE-STRING       "hegel_handshake_start")

;; ---------------------------------------------------------------------------
;; CRC32
;; ---------------------------------------------------------------------------

(define crc32-table
  (let ([table (make-vector 256 0)])
    (for ([i (in-range 256)])
      (let loop ([c i] [j 0])
        (if (= j 8)
            (vector-set! table i c)
            (loop (if (odd? c)
                      (bitwise-xor (arithmetic-shift c -1) #xEDB88320)
                      (arithmetic-shift c -1))
                  (+ j 1)))))
    table))

(define (crc32-update crc bstr start end)
  (let loop ([i start] [crc crc])
    (if (= i end)
        crc
        (loop (+ i 1)
              (bitwise-xor
               (arithmetic-shift crc -8)
               (vector-ref crc32-table
                           (bitwise-and
                            (bitwise-xor crc (bytes-ref bstr i))
                            #xFF)))))))

(define (crc32-two-pieces bstr1 bstr2)
  ;; Compute CRC32 over bstr1 followed by bstr2 without concatenating
  (let* ([crc1 (crc32-update #xFFFFFFFF bstr1 0 (bytes-length bstr1))]
         [crc2 (crc32-update crc1 bstr2 0 (bytes-length bstr2))])
    (bitwise-and (bitwise-xor crc2 #xFFFFFFFF) #xFFFFFFFF)))

;; ---------------------------------------------------------------------------
;; Big-endian integer helpers
;; ---------------------------------------------------------------------------

(define (u32-be->bytes n)
  (bytes (bitwise-and (arithmetic-shift n -24) #xFF)
         (bitwise-and (arithmetic-shift n -16) #xFF)
         (bitwise-and (arithmetic-shift n -8)  #xFF)
         (bitwise-and n #xFF)))

(define (bytes->u32-be bstr off)
  (bitwise-ior
   (arithmetic-shift (bytes-ref bstr off) 24)
   (arithmetic-shift (bytes-ref bstr (+ off 1)) 16)
   (arithmetic-shift (bytes-ref bstr (+ off 2)) 8)
   (bytes-ref bstr (+ off 3))))

;; ---------------------------------------------------------------------------
;; Packet struct
;; ---------------------------------------------------------------------------

(struct packet
  (stream message-id is-reply payload)
  #:transparent)

;; ---------------------------------------------------------------------------
;; Write packet
;; ---------------------------------------------------------------------------

(define (write-packet pkt out)
  (define stream     (packet-stream pkt))
  (define message-id (packet-message-id pkt))
  (define is-reply   (packet-is-reply pkt))
  (define payload    (packet-payload pkt))

  (define raw-msg-id
    (if is-reply
        (bitwise-ior message-id REPLY-BIT)
        message-id))

  ;; Build header with checksum field zeroed
  (define header (make-bytes HEADER-SIZE 0))
  (bytes-copy! header 0 (u32-be->bytes MAGIC))
  ;; bytes 4..8 = checksum (filled below)
  (bytes-copy! header 8  (u32-be->bytes stream))
  (bytes-copy! header 12 (u32-be->bytes raw-msg-id))
  (bytes-copy! header 16 (u32-be->bytes (bytes-length payload)))

  ;; Compute CRC32 over header (checksum zeroed) + payload
  (define checksum (crc32-two-pieces header payload))
  (bytes-copy! header 4 (u32-be->bytes checksum))

  (write-bytes header out)
  (write-bytes payload out)
  (write-byte TERMINATOR out)
  (flush-output out))

;; ---------------------------------------------------------------------------
;; Read packet
;; ---------------------------------------------------------------------------

(define (read-exact-bytes in n)
  (define buf (read-bytes n in))
  (when (or (eof-object? buf) (< (bytes-length buf) n))
    (error 'read-packet "Connection closed: server process exited"))
  buf)

(define (read-packet in)
  (define header (read-exact-bytes in HEADER-SIZE))

  (define magic    (bytes->u32-be header 0))
  (define checksum (bytes->u32-be header 4))
  (define stream   (bytes->u32-be header 8))
  (define raw-msg  (bytes->u32-be header 12))
  (define length   (bytes->u32-be header 16))

  (unless (= magic MAGIC)
    (error 'read-packet "Invalid magic: expected 0x~a, got 0x~a"
           (number->string MAGIC 16) (number->string magic 16)))

  (define is-reply (not (= 0 (bitwise-and raw-msg REPLY-BIT))))
  (define message-id (bitwise-and raw-msg (bitwise-not REPLY-BIT)))

  (define payload (read-exact-bytes in length))
  (define term-byte (read-exact-bytes in 1))

  (unless (= (bytes-ref term-byte 0) TERMINATOR)
    (error 'read-packet "Invalid terminator: expected 0x~a, got 0x~a"
           (number->string TERMINATOR 16) (number->string (bytes-ref term-byte 0) 16)))

  ;; Verify CRC32: zero out checksum field, compute over header + payload
  (define header-for-check (bytes-copy header))
  (bytes-copy! header-for-check 4 (bytes 0 0 0 0))
  (define computed (crc32-two-pieces header-for-check payload))
  (unless (= computed checksum)
    (error 'read-packet "CRC32 mismatch: expected 0x~a, got 0x~a"
           (number->string checksum 16) (number->string computed 16)))

  (packet stream message-id is-reply payload))

;; ---------------------------------------------------------------------------
;; CBOR encode / decode
;; ---------------------------------------------------------------------------

;; Tag 91 = WTF-8 bytes → string (used by server for all strings)
(define HEGEL-STRING-TAG 91)

;; WTF-8 decode: try UTF-8, fall back to latin-1 replacement
(define (wtf8-decode bstr)
  (with-handlers
    ([exn:fail?
      (lambda (_e)
        ;; Fallback: decode as latin-1 replacing undecodable bytes
        (list->string
         (for/list ([b (in-bytes bstr)])
           (integer->char b))))])
    (bytes->string/utf-8 bstr)))

(define hegel-cbor-config
  ;; Start from cbor-default-config (handles bignums via tags 2/3, rationals via
  ;; tag 30) and layer on our WTF-8 string handler for Hegel's tag 91.
  (with-cbor-tag-deserializer
   cbor-default-config
   HEGEL-STRING-TAG
   (lambda (_tag-number content)
     (cond
       [(bytes? content) (wtf8-decode content)]
       [else (format "~a" content)]))))

(define (cbor-encode-value v)
  (define out (open-output-bytes))
  (cbor-write cbor-empty-config v out)
  (get-output-bytes out))

(define (cbor-decode-value bstr)
  (define in (open-input-bytes bstr))
  (cbor-read hegel-cbor-config in))
