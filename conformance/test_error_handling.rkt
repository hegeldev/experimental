#!/usr/bin/env racket
#lang racket/base

;;; Error handling conformance binary.
;;;
;;; Used for all HEGEL_PROTOCOL_TEST_MODE error modes.
;;; Runs a simple test and exits 0 regardless of error.
;;; Params (JSON from argv[1]): {} (ignored)
;;; Metrics: none written
;;;
;;; For collection_more and new_collection modes, draws a list to
;;; trigger those protocol commands.

(require json
         (file "../main.rkt")
         (file "../conformance.rkt"))

(define test-cases (get-test-cases))
(define mode (getenv "HEGEL_PROTOCOL_TEST_MODE"))

;; A non-basic boolean generator: the filter always passes but forces the
;; non-basic (collection protocol) path for any list drawn with this element gen.
(define non-basic-bool (make-non-basic (booleans)))

(with-handlers ([exn:fail? void])
  (run-hegel
   (lambda (tc)
     ;; For collection error modes, draw a non-basic list to trigger
     ;; new_collection and collection_more protocol commands.
     ;; For other modes, drawing a boolean is sufficient.
     (cond
       [(or (equal? mode "stop_test_on_collection_more")
            (equal? mode "stop_test_on_new_collection"))
        (draw tc (lists non-basic-bool))]
       [else
        (draw tc (booleans))])
     (void))
   #:test-cases test-cases))
