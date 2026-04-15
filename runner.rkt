#lang racket/base

;;; Test runner: Hegel builder and test lifecycle.

(require racket/contract
         racket/string
         racket/list
         "protocol.rkt"
         "connection.rkt"
         "session.rkt"
         "test-case.rkt")

(provide
 (contract-out
  [run-hegel (->* ((-> test-case? any))
                  (#:test-cases    exact-nonnegative-integer?
                   #:seed          (or/c exact-nonnegative-integer? #f)
                   #:derandomize   boolean?
                   #:database      (or/c 'unset 'disabled string?)
                   #:database-key  (or/c bytes? #f)
                   #:suppress-health-check (listof string?))
                  void?)]
  [make-server-data-source (-> connection? stream? data-source?)])
 run-test-case
 origin-from-error)

;; ---------------------------------------------------------------------------
;; ServerDataSource
;; ---------------------------------------------------------------------------

(define (server-request conn stream command payload-hash)
  ;; payload-hash is a Racket hash with string keys
  (define msg (hash-set payload-hash "command" command))
  (define encoded (cbor-encode-value msg))
  (define id (stream-send-request stream encoded))
  (define response-bytes (stream-receive-reply stream id))
  (define response (cbor-decode-value response-bytes))

  ;; Handle response envelope
  (cond
    [(hash? response)
     (cond
       [(hash-has-key? response "error")
        (define err-msg (format "~a" (hash-ref response "error" "")))
        (define err-type (format "~a" (hash-ref response "type" "")))
        (cond
          [(or (string-contains? err-msg "overflow")
               (string-contains? err-msg "StopTest")
               (string-contains? err-type "overflow")
               (string-contains? err-type "StopTest"))
           (stream-mark-closed! stream)
           (raise-stop-test)]
          [(or (string-contains? err-msg "FlakyStrategyDefinition")
               (string-contains? err-msg "FlakyReplay"))
           (stream-mark-closed! stream)
           (raise-stop-test)]
          [else
           (error 'hegel "Server error (~a): ~a" err-type err-msg)])]
       [(hash-has-key? response "result")
        (hash-ref response "result")]
       [else response])]
    [else response]))

(define (make-server-data-source conn stream)
  (define aborted (box #f))

  (define (check-aborted)
    (when (unbox aborted)
      (raise-stop-test)))

  (define (do-generate schema)
    (check-aborted)
    (server-request conn stream "generate" (hash "schema" schema)))

  (define (do-start-span label)
    (check-aborted)
    (server-request conn stream "start_span" (hash "label" label))
    (void))

  (define (do-stop-span discard)
    (when (not (unbox aborted))
      (with-handlers ([exn:fail? void])
        (server-request conn stream "stop_span" (hash "discard" discard))))
    (void))

  (define (do-new-collection min-size max-size)
    (check-aborted)
    (define payload (if max-size
                        (hash "min_size" min-size "max_size" max-size)
                        (hash "min_size" min-size)))
    (define result (server-request conn stream "new_collection" payload))
    (inexact->exact result))

  (define (do-collection-more coll-id)
    (check-aborted)
    (server-request conn stream "collection_more" (hash "collection_id" coll-id)))

  (define (do-collection-reject coll-id why)
    (when (not (unbox aborted))
      (define payload (if why
                          (hash "collection_id" coll-id "why" why)
                          (hash "collection_id" coll-id)))
      (server-request conn stream "collection_reject" payload))
    (void))

  (define (do-mark-complete status origin)
    (with-handlers ([exn:fail? void])
      (define msg (hash "command" "mark_complete"
                        "status" status
                        "origin" (or origin 'null)))
      (define encoded (cbor-encode-value msg))
      (define id (stream-send-request stream encoded))
      (stream-receive-reply stream id))
    (stream-close stream)
    (void))

  (define (do-test-aborted?)
    (unbox aborted))

  ;; Wrap generate/start-span to detect stop-test and set aborted flag
  (define (safe-generate schema)
    (with-handlers ([exn:fail:stop-test?
                     (lambda (e)
                       (set-box! aborted #t)
                       (raise e))])
      (do-generate schema)))

  (define (safe-start-span label)
    (with-handlers ([exn:fail:stop-test?
                     (lambda (e)
                       (set-box! aborted #t)
                       (raise e))])
      (do-start-span label)))

  (define (safe-new-collection min-size max-size)
    (with-handlers ([exn:fail:stop-test?
                     (lambda (e)
                       (set-box! aborted #t)
                       (raise e))])
      (do-new-collection min-size max-size)))

  (define (safe-collection-more coll-id)
    (with-handlers ([exn:fail:stop-test?
                     (lambda (e)
                       (set-box! aborted #t)
                       (raise e))])
      (do-collection-more coll-id)))

  (make-data-source
   safe-generate
   safe-start-span
   do-stop-span
   safe-new-collection
   safe-collection-more
   do-collection-reject
   do-mark-complete
   do-test-aborted?))

;; ---------------------------------------------------------------------------
;; Run a single test case
;; ---------------------------------------------------------------------------

;; ---------------------------------------------------------------------------
;; Error origin extraction
;; ---------------------------------------------------------------------------

(define (origin-from-error err [override-ctx #f])
  ;; Hypothesis requires interesting_origin to be non-None.
  ;; Extract a meaningful string from the exception.
  (define msg (exn-message err))
  (define ctx
    (or override-ctx
        (continuation-mark-set->context (exn-continuation-marks err))))
  (define loc-str
    (for/or ([frame (in-list ctx)])
      (define loc (cdr frame))
      (and (srcloc? loc)
           (let ([src (srcloc-source loc)]
                 [line (srcloc-line loc)])
             (and src line
                  (format "~a:~a" src line))))))
  (if loc-str
      (format "error at ~a: ~a" loc-str msg)
      (format "error: ~a" msg)))

;; ---------------------------------------------------------------------------
;; Run a single test case
;; ---------------------------------------------------------------------------

(define (run-test-case ds test-fn is-final?)
  (define tc (make-test-case ds is-final?))
  (define result
    (with-handlers
      ([exn:fail:assume?
        (lambda (_e) 'invalid)]
       [exn:fail:stop-test?
        (lambda (_e) 'invalid)]
       [exn:fail?
        (lambda (e)
          (when is-final?
            (define msg (exn-message e))
            (eprintf "\n~a\n" msg))
          (cons 'interesting e))])
      (test-fn tc)
      'valid))

  (unless (data-source-test-aborted? ds)
    (define status
      (cond
        [(eq? result 'valid)    "VALID"]
        [(eq? result 'invalid)  "INVALID"]
        [else                   "INTERESTING"]))
    (define origin
      (if (pair? result)
          (origin-from-error (cdr result))
          #f))
    (data-source-mark-complete ds status origin))

  result)

;; ---------------------------------------------------------------------------
;; run-hegel
;; ---------------------------------------------------------------------------

(define (run-hegel test-fn
                   #:test-cases    [test-cases 100]
                   #:seed          [seed #f]
                   #:derandomize   [derandomize (in-ci?)]
                   #:database      [database (if (in-ci?) 'disabled 'unset)]
                   #:database-key  [database-key #f]
                   #:suppress-health-check [suppress-health-check '()])
  (define sess (get-session))
  (define conn (session-connection sess))
  (define ctrl (session-control-stream sess))
  (define test-stream (connection-new-stream conn))

  ;; Build run_test message
  (define run-test-msg
    (let ([h (make-hash)])
      (hash-set! h "command" "run_test")
      (hash-set! h "test_cases" test-cases)
      (hash-set! h "seed" (or seed 'null))
      (hash-set! h "stream_id" (stream-id test-stream))
      (hash-set! h "database_key" (or database-key 'null))
      (hash-set! h "derandomize" derandomize)
      (cond
        [(eq? database 'disabled) (hash-set! h "database" 'null)]
        [(string? database)       (hash-set! h "database" database)])
      (when (not (null? suppress-health-check))
        (hash-set! h "suppress_health_check" suppress-health-check))
      h))

  ;; Send run_test on control stream
  (define ctrl-payload (cbor-encode-value run-test-msg))
  (define ctrl-req-id (stream-send-request ctrl ctrl-payload))
  (stream-receive-reply ctrl ctrl-req-id)

  ;; Event loop
  (define ack-null (cbor-encode-value (hash "result" 'null)))
  (define result-data (hash))

  (let loop ()
    (define-values (event-id event-payload) (stream-receive-request test-stream))
    (define event (cbor-decode-value event-payload))
    (define event-type (hash-ref event "event" #f))

    (cond
      [(equal? event-type "test_case")
       (define stream-id-val (hash-ref event "stream_id"))
       (define test-case-stream (connection-connect-stream conn (inexact->exact stream-id-val)))

       ;; Ack BEFORE running the test
       (stream-send-reply test-stream event-id ack-null)

       (define ds (make-server-data-source conn test-case-stream))
       (run-test-case ds test-fn #f)
       (loop)]

      [(equal? event-type "test_done")
       (define ack-true (cbor-encode-value (hash "result" #t)))
       (stream-send-reply test-stream event-id ack-true)
       (set! result-data (hash-ref event "results" (hash)))]

      [else
       ;; Unknown event - skip
       (stream-send-reply test-stream event-id ack-null)
       (loop)]))

  ;; Check for server-side failures
  (when (hash-ref result-data "health_check_failure" #f)
    (error 'hegel "Health check failure:\n~a"
           (hash-ref result-data "health_check_failure")))
  (when (hash-ref result-data "flaky" #f)
    (error 'hegel "Flaky test detected: ~a"
           (hash-ref result-data "flaky")))

  ;; Final replays for interesting test cases
  (define n-interesting
    (inexact->exact (hash-ref result-data "interesting_test_cases" 0)))

  (define final-result #f)

  (for ([_ (in-range n-interesting)])
    (define-values (event-id event-payload) (stream-receive-request test-stream))
    (define event (cbor-decode-value event-payload))
    (define stream-id-val (hash-ref event "stream_id"))
    (define test-case-stream (connection-connect-stream conn (inexact->exact stream-id-val)))

    (stream-send-reply test-stream event-id ack-null)

    (define ds (make-server-data-source conn test-case-stream))
    (define result (run-test-case ds test-fn #t))
    (when (pair? result)
      (set! final-result result)))

  (stream-close test-stream)

  ;; Check if test passed
  (define passed (hash-ref result-data "passed" #t))

  (unless passed
    (define msg
      (if (and final-result (pair? final-result))
          (exn-message (cdr final-result))
          "unknown"))
    (error 'hegel "Property test failed: ~a" msg)))

;; ---------------------------------------------------------------------------
;; CI detection
;; ---------------------------------------------------------------------------

(define (in-ci?)
  (define ci-vars
    '("CI" "BITBUCKET_COMMIT" "BUILDKITE" "CIRCLECI" "CIRRUS_CI"
      "CODEBUILD_BUILD_ID" "GITHUB_ACTIONS" "GITLAB_CI" "HEROKU_TEST_RUN_ID"
      "TEAMCITY_VERSION" "TF_BUILD"))
  (ormap (lambda (v) (getenv v)) ci-vars))
