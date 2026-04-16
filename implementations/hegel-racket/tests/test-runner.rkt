#lang racket/base

;;; Unit tests for the test runner and test case operations.

(require (except-in rackunit make-test-case run-test-case)
         rackunit/text-ui
         (except-in (file "../main.rkt") make-test-case)
         (only-in (file "../test-case.rkt") make-test-case raise-stop-test raise-assume-failed
          test-case-span-depth make-collection collection-more collection-reject
          data-source-generate data-source-start-span data-source-new-collection
          data-source-collection-more data-source-collection-reject)
         (only-in (file "../runner.rkt") run-test-case make-server-data-source origin-from-error)
         (only-in (file "../protocol.rkt") cbor-encode-value cbor-decode-value)
         (only-in (file "../connection.rkt")
                  make-connection connection-new-stream connection-connect-stream
                  stream-id stream-receive-request stream-send-reply))

;; ---------------------------------------------------------------------------
;; Mock DataSource
;; ---------------------------------------------------------------------------

;; Helper: create a mock client/server pair and a ServerDataSource
(define (make-mock-server-ds)
  (define-values (client-reads server-writes) (make-pipe))
  (define-values (server-reads client-writes) (make-pipe))
  (define client-conn (make-connection client-reads client-writes))
  (define server-conn (make-connection server-reads server-writes))
  (define client-stream (connection-new-stream client-conn))
  (define sid (stream-id client-stream))
  (define server-stream (connection-connect-stream server-conn sid))
  (values (make-server-data-source client-conn client-stream)
          server-stream))

(define (make-mock-ds #:values    [vals '(42)]
                      #:more      [more '()]
                      #:aborted?  [aborted? #f])
  (define val-queue   (box vals))
  (define more-queue  (box more))
  (define status-box  (box #f))
  (define origin-box  (box #f))
  (define aborted-box (box aborted?))

  (define (dequeue! q-box default)
    (define q (unbox q-box))
    (if (null? q)
        default
        (begin (set-box! q-box (cdr q)) (car q))))

  (define ds
    (make-data-source
     (lambda (schema) (dequeue! val-queue 0))
     (lambda (label) (void))
     (lambda (discard) (void))
     (lambda (min-size max-size) 0)
     (lambda (coll-id) (dequeue! more-queue #f))
     (lambda (coll-id why) (void))
     (lambda (status origin)
       (set-box! status-box status)
       (set-box! origin-box origin)
       (void))
     (lambda () (unbox aborted-box))))

  (values ds status-box origin-box aborted-box))

;; ---------------------------------------------------------------------------
;; Tests
;; ---------------------------------------------------------------------------

(define runner-tests
  (test-suite
   "Runner tests"

   (test-suite
    "run-test-case outcomes"

    (test-case "valid: test passes"
      (define-values (ds status-box _ _2) (make-mock-ds #:values '(5)))
      (define result (run-test-case ds (lambda (tc) (void)) #f))
      (check-equal? result 'valid)
      (check-equal? (unbox status-box) "VALID"))

    (test-case "invalid: assume fails"
      (define-values (ds status-box _ _2) (make-mock-ds #:values '(5)))
      (define result (run-test-case ds
                                    (lambda (tc)
                                      (tc-assume tc #f))
                                    #f))
      (check-equal? result 'invalid)
      (check-equal? (unbox status-box) "INVALID"))

    (test-case "interesting: test raises error"
      (define-values (ds status-box origin-box _) (make-mock-ds #:values '(5)))
      (define result (run-test-case ds
                                    (lambda (tc)
                                      (error "test failed!"))
                                    #f))
      (check-pred pair? result)
      (check-equal? (car result) 'interesting)
      (check-equal? (unbox status-box) "INTERESTING")
      ;; origin should be a non-empty string
      (check-pred string? (unbox origin-box))
      (check-true (> (string-length (unbox origin-box)) 0)))

    (test-case "interesting on final run eprints error message"
      ;; Covers (when is-final? (eprintf ...)) in the exn:fail? handler
      (define-values (ds status-box origin-box _) (make-mock-ds #:values '(5)))
      (define result (run-test-case ds
                                    (lambda (tc)
                                      (error "final test failed!"))
                                    #t))  ; is-final? = #t
      (check-pred pair? result)
      (check-equal? (car result) 'interesting))

    (test-case "origin-from-error with no source location uses format error: msg"
      ;; Covers (format "error: ~a" msg) in origin-from-error when ctx is empty.
      ;; Pass an empty ctx override to simulate no source location.
      (define e (make-exn:fail "no-source error" (current-continuation-marks)))
      (check-equal? (origin-from-error e '()) "error: no-source error"))

    (test-case "aborted: no mark-complete sent"
      (define-values (ds status-box _ _2) (make-mock-ds #:aborted? #t))
      (define result (run-test-case ds (lambda (tc) (void)) #f))
      ;; When aborted, mark-complete is not called
      (check-false (unbox status-box)))

    (test-case "stop-test is treated as invalid"
      (define-values (ds status-box _ _2) (make-mock-ds #:values '(5)))
      (define result (run-test-case ds
                                    (lambda (tc)
                                      (raise-stop-test))
                                    #f))
      (check-equal? result 'invalid)
      (check-equal? (unbox status-box) "INVALID")))

   (test-suite
    "TestCase operations"

    (test-case "tc-assume passes when true"
      (define-values (ds _ _2 _3) (make-mock-ds))
      (define tc (make-test-case ds #f))
      (check-not-exn (lambda () (tc-assume tc #t))))

    (test-case "tc-assume fails when false"
      (define-values (ds _ _2 _3) (make-mock-ds))
      (define tc (make-test-case ds #f))
      (check-exn exn:fail:assume? (lambda () (tc-assume tc #f))))

    (test-case "tc-note on non-final run is silent"
      (define-values (ds _ _2 _3) (make-mock-ds))
      (define tc (make-test-case ds #f))
      ;; Should not raise
      (check-not-exn (lambda () (tc-note tc "some note"))))

    (test-case "tc-note on final run writes to stderr"
      (define-values (ds _ _2 _3) (make-mock-ds))
      (define tc (make-test-case ds #t))
      ;; Should not raise (writes to stderr)
      (check-not-exn (lambda () (tc-note tc "final run note"))))

    (test-case "tc-start-span increments depth"
      (define-values (ds _ _2 _3) (make-mock-ds))
      (define tc (make-test-case ds #f))
      (check-equal? (unbox (test-case-span-depth tc)) 0)
      (tc-start-span tc LABEL-LIST)
      (check-equal? (unbox (test-case-span-depth tc)) 1)
      (tc-stop-span tc #f)
      (check-equal? (unbox (test-case-span-depth tc)) 0))

    (test-case "tc-stop-span uses default discard=#f"
      ;; Calling tc-stop-span without discard arg triggers the default value #f
      (define-values (ds _ _2 _3) (make-mock-ds))
      (define tc (make-test-case ds #f))
      (tc-start-span tc LABEL-LIST)
      (tc-stop-span tc)  ; uses default discard=#f
      (check-equal? (unbox (test-case-span-depth tc)) 0))

    (test-case "tc-test-aborted? returns false when not aborted"
      (define-values (ds _ _2 _3) (make-mock-ds #:aborted? #f))
      (define tc (make-test-case ds #f))
      (check-false (tc-test-aborted? tc)))

    (test-case "draw on final run records and prints"
      (define-values (ds _ _2 _3) (make-mock-ds #:values '(99)))
      (define tc (make-test-case ds #t))
      ;; draw on final run writes to stderr via tc-record-draw!
      ;; Just check it doesn't crash and returns the value
      (define result (draw tc (integers)))
      (check-equal? result 99)))

   (test-suite
    "Collection protocol"

    (test-case "collection-more returns true when queue has #t"
      (define-values (ds _ _2 _3) (make-mock-ds #:more '(#t #f)))
      (define coll (make-collection ds 0 #f))
      (check-true (collection-more coll))
      (check-false (collection-more coll))
      ;; Once false, always false
      (check-false (collection-more coll)))

    (test-case "collection-reject does not crash"
      (define-values (ds _ _2 _3) (make-mock-ds #:more '(#t #f)))
      (define coll (make-collection ds 0 #f))
      (check-not-exn (lambda () (collection-reject coll "reason")))
      (check-not-exn (lambda () (collection-reject coll #f))))

    (test-case "collection-reject after done is no-op"
      (define-values (ds _ _2 _3) (make-mock-ds #:more '(#f)))
      (define coll (make-collection ds 0 #f))
      (collection-more coll)  ; exhausts the queue
      ;; Reject after done should not crash
      (check-not-exn (lambda () (collection-reject coll "should be no-op"))))

    (test-case "collection-more sets finished on stop-test"
      ;; DataSource that raises stop-test on collection-more
      (define ds
        (make-data-source
         (lambda (schema) 0)
         (lambda (label) (void))
         (lambda (discard) (void))
         (lambda (min-size max-size) 0)
         (lambda (coll-id) (raise-stop-test))  ; stop-test on collection-more
         (lambda (coll-id why) (void))
         (lambda (status origin) (void))
         (lambda () #f)))
      (define coll (make-collection ds 0 #f))
      ;; Should propagate the stop-test
      (check-exn exn:fail:stop-test? (lambda () (collection-more coll)))))

   (test-suite
    "Error types"

    (test-case "exn:fail:stop-test? predicate"
      (check-true
       (with-handlers ([exn:fail:stop-test? (lambda (_) #t)])
         (raise-stop-test)
         #f)))

    (test-case "exn:fail:assume? predicate"
      (check-true
       (with-handlers ([exn:fail:assume? (lambda (_) #t)])
         (raise-assume-failed)
         #f))))

   (test-suite
    "tc-start-span error handler"

    (test-case "tc-start-span decrements depth on error"
      ;; start-span fn that throws
      (define throwing-ds
        (make-data-source
         (lambda (schema) 0)
         (lambda (label) (error "start-span exploded!"))
         (lambda (discard) (void))
         (lambda (min-size max-size) 0)
         (lambda (coll-id) #f)
         (lambda (coll-id why) (void))
         (lambda (status origin) (void))
         (lambda () #f)))
      (define tc (make-test-case throwing-ds #f))
      (check-equal? (unbox (test-case-span-depth tc)) 0)
      (check-exn exn:fail? (lambda () (tc-start-span tc LABEL-LIST)))
      ;; Error handler must decrement depth back to 0
      (check-equal? (unbox (test-case-span-depth tc)) 0)))

   (test-suite
    "ServerDataSource error paths"

    (test-case "server error response raises hegel error"
      (define-values (ds server-stream) (make-mock-server-ds))
      ;; Server thread: respond with a generic error
      (define server-thread
        (thread
         (lambda ()
           (define-values (req-id _payload) (stream-receive-request server-stream))
           (define err-resp (cbor-encode-value
                             (hash "error" "SomeError" "type" "RuntimeError")))
           (stream-send-reply server-stream req-id err-resp))))
      ;; Client: generate call should raise hegel error
      (check-exn exn:fail?
        (lambda ()
          (data-source-generate ds (hash "type" "integer"))))
      (thread-wait server-thread))

    (test-case "StopTest error response raises stop-test"
      (define-values (ds server-stream) (make-mock-server-ds))
      (define server-thread
        (thread
         (lambda ()
           (define-values (req-id _payload) (stream-receive-request server-stream))
           (define err-resp (cbor-encode-value
                             (hash "error" "StopTest" "type" "StopTest")))
           (stream-send-reply server-stream req-id err-resp))))
      (check-exn exn:fail:stop-test?
        (lambda ()
          (data-source-generate ds (hash "type" "integer"))))
      (thread-wait server-thread))

    (test-case "FlakyReplay error response raises stop-test"
      (define-values (ds server-stream) (make-mock-server-ds))
      (define server-thread
        (thread
         (lambda ()
           (define-values (req-id _payload) (stream-receive-request server-stream))
           (define err-resp (cbor-encode-value
                             (hash "error" "FlakyReplay" "type" "FlakyReplay")))
           (stream-send-reply server-stream req-id err-resp))))
      (check-exn exn:fail:stop-test?
        (lambda ()
          (data-source-generate ds (hash "type" "integer"))))
      (thread-wait server-thread))

    (test-case "new-collection without max-size sends payload without max_size"
      (define-values (ds server-stream) (make-mock-server-ds))
      (define captured-payload (box #f))
      (define server-thread
        (thread
         (lambda ()
           (define-values (req-id payload) (stream-receive-request server-stream))
           (set-box! captured-payload (cbor-decode-value payload))
           (stream-send-reply server-stream req-id
                              (cbor-encode-value (hash "result" 0))))))
      ;; Call new-collection with max-size = #f
      (data-source-new-collection ds 0 #f)
      (thread-wait server-thread)
      (define pld (unbox captured-payload))
      (check-false (hash-has-key? pld "max_size"))
      (check-equal? (hash-ref pld "min_size") 0))

    (test-case "collection-reject with why sends why field"
      (define-values (ds server-stream) (make-mock-server-ds))
      (define server-thread
        (thread
         (lambda ()
           (define-values (req-id payload) (stream-receive-request server-stream))
           (define decoded (cbor-decode-value payload))
           (check-equal? (hash-ref decoded "why" #f) "duplicate")
           (stream-send-reply server-stream req-id
                              (cbor-encode-value (hash "result" 'null))))))
      (data-source-collection-reject ds 0 "duplicate")
      (thread-wait server-thread))

    (test-case "collection-reject without why omits why field"
      ;; Covers (hash "collection_id" coll-id) without "why" key path
      (define-values (ds server-stream) (make-mock-server-ds))
      (define captured-payload (box #f))
      (define server-thread
        (thread
         (lambda ()
           (define-values (req-id payload) (stream-receive-request server-stream))
           (set-box! captured-payload (cbor-decode-value payload))
           (stream-send-reply server-stream req-id
                              (cbor-encode-value (hash "result" 'null))))))
      (data-source-collection-reject ds 0 #f)  ; why=#f
      (thread-wait server-thread)
      (define pld (unbox captured-payload))
      (check-false (hash-has-key? pld "why")))

    (test-case "safe-start-span: StopTest sets aborted flag"
      ;; Covers (set-box! aborted #t) in safe-start-span wrapper
      (define-values (ds server-stream) (make-mock-server-ds))
      (define server-thread
        (thread
         (lambda ()
           (define-values (req-id _payload) (stream-receive-request server-stream))
           (stream-send-reply server-stream req-id
                              (cbor-encode-value (hash "error" "StopTest" "type" "StopTest"))))))
      (check-exn exn:fail:stop-test?
        (lambda ()
          (data-source-start-span ds LABEL-LIST)))
      (thread-wait server-thread))

    (test-case "safe-new-collection: StopTest sets aborted flag"
      ;; Covers (set-box! aborted #t) in safe-new-collection wrapper
      (define-values (ds server-stream) (make-mock-server-ds))
      (define server-thread
        (thread
         (lambda ()
           (define-values (req-id _payload) (stream-receive-request server-stream))
           (stream-send-reply server-stream req-id
                              (cbor-encode-value (hash "error" "StopTest" "type" "StopTest"))))))
      (check-exn exn:fail:stop-test?
        (lambda ()
          (data-source-new-collection ds 0 #f)))
      (thread-wait server-thread))

    (test-case "safe-collection-more: StopTest sets aborted flag"
      ;; Covers (set-box! aborted #t) in safe-collection-more wrapper
      (define-values (ds server-stream) (make-mock-server-ds))
      (define server-thread
        (thread
         (lambda ()
           (define-values (req-id _payload) (stream-receive-request server-stream))
           (stream-send-reply server-stream req-id
                              (cbor-encode-value (hash "error" "StopTest" "type" "StopTest"))))))
      (check-exn exn:fail:stop-test?
        (lambda ()
          (data-source-collection-more ds 0)))
      (thread-wait server-thread))

    (test-case "check-aborted raises stop-test when aborted is true"
      ;; After a StopTest, calling generate again triggers check-aborted
      (define-values (ds server-stream) (make-mock-server-ds))
      (define server-thread
        (thread
         (lambda ()
           ;; Only handle one request; aborted flag will prevent second
           (define-values (req-id _payload) (stream-receive-request server-stream))
           (stream-send-reply server-stream req-id
                              (cbor-encode-value (hash "error" "StopTest" "type" "StopTest"))))))
      ;; First call: server returns StopTest, aborted flag is set
      (check-exn exn:fail:stop-test?
        (lambda ()
          (data-source-generate ds (hash "type" "integer"))))
      (thread-wait server-thread)
      ;; Second call: check-aborted fires immediately (no server needed)
      (check-exn exn:fail:stop-test?
        (lambda ()
          (data-source-generate ds (hash "type" "integer")))))

    (test-case "server returns non-hash response"
      ;; Covers outer [else response] in server-request (when response is not a hash)
      (define-values (ds server-stream) (make-mock-server-ds))
      (define server-thread
        (thread
         (lambda ()
           (define-values (req-id _payload) (stream-receive-request server-stream))
           ;; Server returns a plain integer (not a hash)
           (stream-send-reply server-stream req-id
                              (cbor-encode-value 42)))))
      ;; Generate should return the raw value 42
      (define result (data-source-generate ds (hash "type" "integer")))
      (thread-wait server-thread)
      (check-equal? result 42))

    (test-case "server returns hash without result or error key"
      ;; Covers inner [else response] in server-request (hash with no error/result keys)
      (define-values (ds server-stream) (make-mock-server-ds))
      (define server-thread
        (thread
         (lambda ()
           (define-values (req-id _payload) (stream-receive-request server-stream))
           ;; Server returns a hash with unrecognized keys (no "error" or "result")
           (stream-send-reply server-stream req-id
                              (cbor-encode-value (hash "foo" "bar"))))))
      ;; Generate should return the raw hash
      (define result (data-source-generate ds (hash "type" "integer")))
      (thread-wait server-thread)
      (check-true (hash? result))
      (check-equal? (hash-ref result "foo") "bar")))))

(run-tests runner-tests)
