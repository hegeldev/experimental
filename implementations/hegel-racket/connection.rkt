#lang racket/base

;;; Synchronous connection and stream multiplexing over stdio pipes.

(require racket/contract
         "protocol.rkt")

(provide
 (contract-out
  [make-connection   (-> input-port? output-port? connection?)]
  [connection?       (-> any/c boolean?)]
  [connection-new-stream     (-> connection? stream?)]
  [connection-connect-stream (-> connection? exact-nonnegative-integer? stream?)]
  [connection-control-stream (-> connection? stream?)]
  [connection-server-exited! (-> connection? void?)]
  [connection-server-exited? (-> connection? boolean?)]
  [stream?           (-> any/c boolean?)]
  [stream-id         (-> stream? exact-nonnegative-integer?)]
  [stream-send-request  (-> stream? bytes? exact-nonnegative-integer?)]
  [stream-send-reply    (-> stream? exact-nonnegative-integer? bytes? void?)]
  [stream-receive-reply (-> stream? exact-nonnegative-integer? bytes?)]
  [stream-receive-request (-> stream? (values exact-nonnegative-integer? bytes?))]
  [stream-close         (-> stream? void?)]
  [stream-mark-closed!  (-> stream? void?)]))

;; ---------------------------------------------------------------------------
;; Connection
;; ---------------------------------------------------------------------------

(struct connection
  (in-port
   out-port
   ;; stream-id -> (listof packet) : buffered incoming packets
   stream-inboxes      ; mutable hash
   next-stream-counter ; mutable box
   server-exited       ; mutable box
   )
  #:mutable)

(define (make-connection in-port out-port)
  (connection in-port out-port
              (make-hash)
              (box 0)
              (box #f)))

(define (connection-server-exited! conn)
  (set-box! (connection-server-exited conn) #t))

(define (connection-server-exited? conn)
  (unbox (connection-server-exited conn)))

(define (connection-read-packet-for-stream conn target-stream-id)
  ;; Check inbox first
  (define inbox (hash-ref (connection-stream-inboxes conn) target-stream-id #f))
  (cond
    [(and inbox (not (null? inbox)))
     (define pkt (car inbox))
     (hash-set! (connection-stream-inboxes conn) target-stream-id (cdr inbox))
     pkt]
    [else
     ;; Read from port until we get a packet for this stream
     (let loop ()
       (define pkt
         (with-handlers
           ([exn:fail?
             (lambda (e)
               (connection-server-exited! conn)
               (raise e))])
           (read-packet (connection-in-port conn))))

       (if (= (packet-stream pkt) target-stream-id)
           pkt
           (let* ([sid (packet-stream pkt)]
                  [current (hash-ref (connection-stream-inboxes conn) sid '())])
             (hash-set! (connection-stream-inboxes conn) sid (append current (list pkt)))
             (loop))))]))

(define (connection-unregister-stream conn stream-id)
  (hash-remove! (connection-stream-inboxes conn) stream-id))

(define (connection-new-stream conn)
  (define counter (unbox (connection-next-stream-counter conn)))
  (set-box! (connection-next-stream-counter conn) (+ counter 1))
  ;; Client-initiated streams: odd IDs
  (define sid (bitwise-ior (arithmetic-shift counter 1) 1))
  (make-stream sid conn))

(define (connection-connect-stream conn stream-id)
  (make-stream stream-id conn))

(define (connection-control-stream conn)
  (make-stream 0 conn))

;; ---------------------------------------------------------------------------
;; Stream
;; ---------------------------------------------------------------------------

(struct stream
  (id
   conn
   next-message-id  ; mutable box
   responses        ; mutable hash: msg-id -> payload
   requests         ; mutable list of (cons msg-id payload)
   closed           ; mutable box
   )
  #:mutable)

(define (make-stream sid conn)
  (stream sid conn (box 1) (make-hash) (box '()) (box #f)))

(define (stream-check-closed! s)
  (when (unbox (stream-closed s))
    (error 'stream "Stream is closed")))

(define (stream-mark-closed! s)
  (set-box! (stream-closed s) #t))

(define (stream-send-request s payload)
  (stream-check-closed! s)
  (define msg-id (unbox (stream-next-message-id s)))
  (set-box! (stream-next-message-id s) (+ msg-id 1))
  (write-packet
   (packet (stream-id s) msg-id #f payload)
   (connection-out-port (stream-conn s)))
  msg-id)

(define (stream-send-reply s msg-id payload)
  (write-packet
   (packet (stream-id s) msg-id #t payload)
   (connection-out-port (stream-conn s))))

(define (stream-receive-reply s msg-id)
  ;; Check buffered responses first
  (define buffered (hash-ref (stream-responses s) msg-id #f))
  (if buffered
      (begin
        (hash-remove! (stream-responses s) msg-id)
        buffered)
      (let loop ()
        (stream-check-closed! s)
        (define pkt (connection-read-packet-for-stream (stream-conn s) (stream-id s)))
        (cond
          [(and (packet-is-reply pkt) (= (packet-message-id pkt) msg-id))
           (packet-payload pkt)]
          [(packet-is-reply pkt)
           (hash-set! (stream-responses s) (packet-message-id pkt) (packet-payload pkt))
           (loop)]
          [else
           (define reqs (unbox (stream-requests s)))
           (set-box! (stream-requests s)
                     (append reqs (list (cons (packet-message-id pkt) (packet-payload pkt)))))
           (loop)]))))

(define (stream-receive-request s)
  (define reqs (unbox (stream-requests s)))
  (if (not (null? reqs))
      (let ([req (car reqs)])
        (set-box! (stream-requests s) (cdr reqs))
        (values (car req) (cdr req)))
      (let loop ()
        (stream-check-closed! s)
        (define pkt (connection-read-packet-for-stream (stream-conn s) (stream-id s)))
        (if (not (packet-is-reply pkt))
            (values (packet-message-id pkt) (packet-payload pkt))
            (begin
              (hash-set! (stream-responses s) (packet-message-id pkt) (packet-payload pkt))
              (loop))))))

(define (stream-close s)
  (unless (unbox (stream-closed s))
    (set-box! (stream-closed s) #t)
    (connection-unregister-stream (stream-conn s) (stream-id s))
    (write-packet
     (packet (stream-id s) CLOSE-STREAM-MESSAGE-ID #f CLOSE-STREAM-PAYLOAD)
     (connection-out-port (stream-conn s)))))
