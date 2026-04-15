#lang racket/base

;;; Unit tests for connection and stream multiplexing.

(require rackunit
         rackunit/text-ui
         (file "../protocol.rkt")
         (file "../connection.rkt"))

;; ---------------------------------------------------------------------------
;; Test infrastructure: in-memory bidirectional pipe pair
;; ---------------------------------------------------------------------------

;; Creates a pair of connections for "client" and "server" that communicate
;; via in-memory pipes.
(define (make-test-pair)
  ;; pipe: (make-pipe) → (values read-port write-port)
  (define-values (client-reads server-writes) (make-pipe))
  (define-values (server-reads client-writes) (make-pipe))
  (values (make-connection client-reads client-writes)
          (make-connection server-reads server-writes)))

;; ---------------------------------------------------------------------------
;; Tests
;; ---------------------------------------------------------------------------

(define connection-tests
  (test-suite
   "Connection tests"

   (test-suite
    "Stream creation"

    (test-case "new stream has odd ID"
      (define-values (client _server) (make-test-pair))
      (define s (connection-new-stream client))
      (check-true (odd? (stream-id s))))

    (test-case "successive streams have increasing IDs"
      (define-values (client _server) (make-test-pair))
      (define s1 (connection-new-stream client))
      (define s2 (connection-new-stream client))
      (check-true (< (stream-id s1) (stream-id s2))))

    (test-case "control stream has ID 0"
      (define-values (client _server) (make-test-pair))
      (define ctrl (connection-control-stream client))
      (check-equal? (stream-id ctrl) 0))

    (test-case "connect stream uses given ID"
      (define-values (client _server) (make-test-pair))
      (define s (connection-connect-stream client 42))
      (check-equal? (stream-id s) 42)))

   (test-suite
    "Request/reply"

    (test-case "send request and receive reply"
      (define-values (client server) (make-test-pair))
      (define client-stream (connection-new-stream client))
      (define sid (stream-id client-stream))

      ;; Thread simulates server: read request, send reply
      (define server-thread
        (thread
         (lambda ()
           (define server-stream (connection-connect-stream server sid))
           (define-values (req-id req-payload)
             (stream-receive-request server-stream))
           (stream-send-reply server-stream req-id #"reply-data"))))

      (define req-id (stream-send-request client-stream #"request-data"))
      (define response (stream-receive-reply client-stream req-id))
      (thread-wait server-thread)
      (check-equal? response #"reply-data"))

    (test-case "server sends request, client replies"
      (define-values (client server) (make-test-pair))
      (define sid 2)  ;; server-initiated stream (even)
      (define server-stream (connection-connect-stream server sid))
      (define client-stream (connection-connect-stream client sid))

      ;; Thread simulates client: read request, send reply
      (define client-thread
        (thread
         (lambda ()
           (define-values (req-id req-payload)
             (stream-receive-request client-stream))
           (stream-send-reply client-stream req-id #"client-reply"))))

      (define req-id (stream-send-request server-stream #"server-request"))
      (define response (stream-receive-reply server-stream req-id))
      (thread-wait client-thread)
      (check-equal? response #"client-reply"))

    (test-case "multiple requests on same stream"
      (define-values (client server) (make-test-pair))
      (define client-stream (connection-new-stream client))
      (define sid (stream-id client-stream))

      (define server-thread
        (thread
         (lambda ()
           (define server-stream (connection-connect-stream server sid))
           ;; Handle 3 requests
           (for ([i (in-range 3)])
             (define-values (req-id payload) (stream-receive-request server-stream))
             (stream-send-reply server-stream req-id
                                (string->bytes/utf-8 (format "reply-~a" i)))))))

      (define id1 (stream-send-request client-stream #"req1"))
      (define id2 (stream-send-request client-stream #"req2"))
      (define id3 (stream-send-request client-stream #"req3"))

      (define r1 (stream-receive-reply client-stream id1))
      (define r2 (stream-receive-reply client-stream id2))
      (define r3 (stream-receive-reply client-stream id3))

      (thread-wait server-thread)
      (check-equal? r1 #"reply-0")
      (check-equal? r2 #"reply-1")
      (check-equal? r3 #"reply-2")))

   (test-suite
    "Buffering across streams"

    (test-case "packets for other streams are buffered"
      (define-values (client server) (make-test-pair))
      (define s1 (connection-new-stream client))
      (define s2 (connection-new-stream client))
      (define sid1 (stream-id s1))
      (define sid2 (stream-id s2))

      ;; Server sends a reply for s2 before s1 has sent anything
      (define server-thread
        (thread
         (lambda ()
           ;; Wait for s1's request first
           (define ss1 (connection-connect-stream server sid1))
           (define ss2 (connection-connect-stream server sid2))
           ;; Reply to s1
           (define-values (req-id1 _payload1) (stream-receive-request ss1))
           ;; Reply to s2
           (define-values (req-id2 _payload2) (stream-receive-request ss2))
           (stream-send-reply ss2 req-id2 #"s2-reply")
           (stream-send-reply ss1 req-id1 #"s1-reply"))))

      ;; Client sends on both streams
      (define id1 (stream-send-request s1 #"s1-req"))
      (define id2 (stream-send-request s2 #"s2-req"))

      ;; Receive on s1 - might buffer s2 reply
      (define r1 (stream-receive-reply s1 id1))
      ;; Receive on s2 - should get buffered reply
      (define r2 (stream-receive-reply s2 id2))

      (thread-wait server-thread)
      (check-equal? r1 #"s1-reply")
      (check-equal? r2 #"s2-reply")))

   (test-suite
    "Stream close"

    (test-case "stream-close sends close packet"
      (define-values (client server) (make-test-pair))
      (define s (connection-new-stream client))
      (define sid (stream-id s))
      ;; Close the stream - should not raise
      (check-not-exn (lambda () (stream-close s))))

    (test-case "stream-close twice is a no-op"
      (define-values (client server) (make-test-pair))
      (define s (connection-new-stream client))
      (stream-close s)
      ;; Second close should not raise
      (check-not-exn (lambda () (stream-close s))))

    (test-case "send on closed stream raises"
      (define-values (client server) (make-test-pair))
      (define s (connection-new-stream client))
      (stream-close s)
      (check-exn exn:fail? (lambda () (stream-send-request s #"data"))))

    (test-case "stream-mark-closed! prevents send"
      (define-values (client server) (make-test-pair))
      (define s (connection-new-stream client))
      (stream-mark-closed! s)
      (check-exn exn:fail? (lambda () (stream-send-request s #"data"))))

    (test-case "receive on closed stream raises"
      (define-values (client server) (make-test-pair))
      (define s (connection-new-stream client))
      (stream-mark-closed! s)
      (check-exn exn:fail? (lambda () (stream-receive-reply s 1)))))

   (test-suite
    "Buffering"

    (test-case "stream-receive-reply handles out-of-order replies"
      ;; Server replies to request 2 before request 1
      ;; While waiting for reply 1, reply 2 is buffered per-stream
      ;; When we ask for reply 2, it's served from stream buffer
      (define-values (client server) (make-test-pair))
      (define cs (connection-new-stream client))
      (define sid (stream-id cs))
      (define ss (connection-connect-stream server sid))

      (define id1 (stream-send-request cs #"req1"))
      (define id2 (stream-send-request cs #"req2"))

      (define server-thread
        (thread
         (lambda ()
           ;; Read both requests, reply to 2 first then 1
           (define-values (rid1 _p1) (stream-receive-request ss))
           (define-values (rid2 _p2) (stream-receive-request ss))
           (stream-send-reply ss rid2 #"reply-2")
           (stream-send-reply ss rid1 #"reply-1"))))

      ;; Wait for reply 1 — reply 2 arrives first and is buffered
      (define r1 (stream-receive-reply cs id1))
      ;; Reply 2 should be in the per-stream buffer
      (define r2 (stream-receive-reply cs id2))
      (thread-wait server-thread)
      (check-equal? r1 #"reply-1")
      (check-equal? r2 #"reply-2"))

    (test-case "stream-receive-reply buffers incoming requests"
      ;; While waiting for a reply, the server sends a request
      ;; The request is buffered; stream-receive-request returns it
      (define-values (client server) (make-test-pair))
      (define cs (connection-new-stream client))
      (define sid (stream-id cs))
      (define ss (connection-connect-stream server sid))

      (define id1 (stream-send-request cs #"my-req"))

      (define server-thread
        (thread
         (lambda ()
           ;; Read client's request
           (define-values (rid _p) (stream-receive-request ss))
           ;; Send a server-initiated request first (before replying)
           (stream-send-request ss #"server-req")
           ;; Then send the reply
           (stream-send-reply ss rid #"my-reply"))))

      ;; Client waits for reply — server's request arrives first, gets buffered
      (define r (stream-receive-reply cs id1))
      ;; The server's request should now be in stream-requests buffer
      (define-values (srv-id srv-payload) (stream-receive-request cs))
      (thread-wait server-thread)
      (check-equal? r #"my-reply")
      (check-equal? srv-payload #"server-req"))

    (test-case "stream-receive-request serves from buffer"
      ;; Requests buffered during stream-receive-reply are dequeued by stream-receive-request
      ;; This is a combination test that verifies the buffer is consumed in FIFO order
      (define-values (client server) (make-test-pair))
      (define cs (connection-new-stream client))
      (define sid (stream-id cs))
      (define ss (connection-connect-stream server sid))

      (define id1 (stream-send-request cs #"client-req"))

      ;; Server sends 2 requests to client, then replies to client's request
      (define server-thread
        (thread
         (lambda ()
           (define-values (rid _p) (stream-receive-request ss))
           (stream-send-request ss #"srv-req-a")
           (stream-send-request ss #"srv-req-b")
           (stream-send-reply ss rid #"client-reply"))))

      ;; Client reads reply — buffers both srv requests
      (define r (stream-receive-reply cs id1))
      ;; Both buffered requests should come out in order
      (define-values (id-a payload-a) (stream-receive-request cs))
      (define-values (id-b payload-b) (stream-receive-request cs))
      (thread-wait server-thread)
      (check-equal? r #"client-reply")
      (check-equal? payload-a #"srv-req-a")
      (check-equal? payload-b #"srv-req-b"))

    (test-case "stream-receive-request buffers incoming replies"
      ;; While waiting for a request, a reply arrives and is buffered per-stream
      ;; Then stream-receive-reply returns the buffered reply
      (define-values (client server) (make-test-pair))
      (define cs (connection-new-stream client))
      (define sid (stream-id cs))
      (define ss (connection-connect-stream server sid))

      ;; Server: send a reply (msg-id=1 as if responding to something),
      ;;         then send a request
      (define server-thread
        (thread
         (lambda ()
           ;; Send an unsolicited reply (as if client had sent req id=99)
           (stream-send-reply ss 99 #"early-reply")
           ;; Then send a real request
           (stream-send-request ss #"real-request"))))

      ;; Client: wait for a request — sees the reply first, buffers it
      (define-values (req-id req-payload) (stream-receive-request cs))
      ;; The buffered reply for msg-id=99 should be retrievable
      (define buffered-reply (stream-receive-reply cs 99))
      (thread-wait server-thread)
      (check-equal? req-payload #"real-request")
      (check-equal? buffered-reply #"early-reply")))

   (test-suite
    "Server exit handling"

    (test-case "connection-server-exited! sets flag"
      (define-values (client _server) (make-test-pair))
      (check-false (connection-server-exited? client))
      (connection-server-exited! client)
      (check-true (connection-server-exited? client)))

    (test-case "read error sets server-exited flag"
      (define-values (client-reads-end server-writes-end) (make-pipe))
      (define-values (server-reads-end client-writes-end) (make-pipe))
      (define conn (make-connection client-reads-end client-writes-end))

      ;; Close the server's write end — this causes EOF on client's read end
      (close-output-port server-writes-end)

      (define s (connection-new-stream conn))
      (define id (stream-send-request s #"request"))

      ;; Reading should fail with connection closed error
      (check-exn exn:fail? (lambda () (stream-receive-reply s id)))
      (check-true (connection-server-exited? conn))))))

(run-tests connection-tests)
