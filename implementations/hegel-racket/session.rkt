#lang racket/base

;;; Global lazy session that manages the hegel server subprocess.
;;;
;;; The session is created on first use and persists for the lifetime of
;;; the process. It spawns hegel with --stdio and communicates over
;;; synchronous pipe I/O.

(require racket/contract
         racket/port
         racket/system
         racket/file
         racket/string
         racket/os
         "protocol.rkt"
         "connection.rkt")

(provide
 (contract-out
  [get-session        (-> hegel-session?)]
  [hegel-session?     (-> any/c boolean?)]
  [session-connection     (-> hegel-session? connection?)]
  [session-control-stream (-> hegel-session? stream?)])
 HEGEL-SERVER-VERSION
 HEGEL-SERVER-COMMAND-ENV
 ;; Internal helpers exposed for testing
 parse-version
 version<=?
 version-in-range?
 find-uv
 hegel-command
 init-session
 reset-session-for-testing!)

;; Forward declarations - actual definitions below after struct
(define (session-connection sess) (hegel-session-connection sess))

;; ---------------------------------------------------------------------------
;; Constants
;; ---------------------------------------------------------------------------

(define HEGEL-SERVER-VERSION     "0.4.0")
(define SUPPORTED-PROTOCOL-MIN  "0.10")
(define SUPPORTED-PROTOCOL-MAX  "0.10")
(define HEGEL-SERVER-COMMAND-ENV "HEGEL_SERVER_COMMAND")
(define HEGEL-SERVER-DIR         ".hegel")

;; ---------------------------------------------------------------------------
;; Version parsing
;; ---------------------------------------------------------------------------

(define (parse-version s)
  (define parts (string-split s "."))
  (unless (= (length parts) 2)
    (error 'hegel "Invalid version string '~a': expected 'major.minor' format" s))
  (define major (string->number (car parts)))
  (define minor (string->number (cadr parts)))
  (unless (and major minor)
    (error 'hegel "Invalid version string '~a'" s))
  (cons major minor))

(define (version<=? a b)
  (or (< (car a) (car b))
      (and (= (car a) (car b))
           (<= (cdr a) (cdr b)))))

(define (version-in-range? version-str min-str max-str)
  (define v   (parse-version version-str))
  (define lo  (parse-version min-str))
  (define hi  (parse-version max-str))
  (and (version<=? lo v) (version<=? v hi)))

;; ---------------------------------------------------------------------------
;; Server log file
;; ---------------------------------------------------------------------------

(define log-file-counter (box 0))

(define (server-log-file)
  (make-directory* HEGEL-SERVER-DIR)
  (define pid (getpid))
  (define ix  (unbox log-file-counter))
  (set-box! log-file-counter (+ ix 1))
  (define path (string-append HEGEL-SERVER-DIR "/server." (number->string pid)
                              "-" (number->string ix) ".log"))
  (open-output-file path #:exists 'append))

;; ---------------------------------------------------------------------------
;; Hegel command discovery
;; ---------------------------------------------------------------------------

(define uv-common-locations
  (list "/home/dev/.local/bin/uv"
        "/usr/local/bin/uv"
        "/usr/bin/uv"))

(define (find-uv [locations uv-common-locations])
  ;; Search for uv in common locations + PATH; always returns a string
  (define on-path (find-executable-path "uv"))
  (define result
    (or on-path
        (for/or ([loc (in-list locations)])
          (and (file-exists? loc) loc))
        "uv"))  ; fallback, may fail
  (if (path? result) (path->string result) result))

(define (hegel-command)
  (define override (getenv HEGEL-SERVER-COMMAND-ENV))
  (if override
      (list override)
      (list (find-uv) "tool" "run" "--from"
            (string-append "hegel-core==" HEGEL-SERVER-VERSION)
            "hegel")))

;; ---------------------------------------------------------------------------
;; HegelSession
;; ---------------------------------------------------------------------------

(struct hegel-session
  (connection control-stream)
  #:transparent)

(define session-box (box #f))

(define (session-control-stream sess)
  (hegel-session-control-stream sess))

(define (get-session)
  (unless (unbox session-box)
    (set-box! session-box (init-session)))
  (unbox session-box))

(define (reset-session-for-testing!)
  ;; Reset the global session, forcing a fresh init on next get-session.
  ;; FOR TESTING ONLY: do not call from production code.
  (set-box! session-box #f))

(define (init-session)
  (define cmd-parts (hegel-command))
  (define log-port (server-log-file))

  ;; Spawn the server process
  ;; subprocess args: (subprocess stdout-dest stdin-src stderr-dest exe args...)
  ;;   stdout-dest: #f = create pipe (return value is input-port to read server's stdout)
  ;;   stdin-src:   #f = create pipe (return value is output-port to write to server's stdin)
  ;;   stderr-dest: log-port = redirect stderr to log file (return value is #f)
  ;; Returns: (values proc server-stdout-port server-stdin-port server-stderr-or-#f)
  (define-values (proc server-stdout server-stdin _stderr)
    (apply subprocess
           #f          ; stdout: create pipe, we'll read from server-stdout
           #f          ; stdin: create pipe, we'll write to server-stdin
           log-port    ; stderr: redirect to log file
           (car cmd-parts)
           (append (cdr cmd-parts) (list "--stdio" "--verbosity" "normal"))))

  ;; Close the log port (child has inherited it)
  (close-output-port log-port)

  ;; server-stdout is an input-port (read responses from server)
  ;; server-stdin is an output-port (send commands to server)
  (define conn (make-connection server-stdout server-stdin))
  (define ctrl (connection-control-stream conn))

  ;; Handshake: send raw bytes, receive version string
  (define handshake-payload (string->bytes/utf-8 HANDSHAKE-STRING))
  (define req-id (stream-send-request ctrl handshake-payload))
  (define response-bytes (stream-receive-reply ctrl req-id))
  (define response-str (bytes->string/utf-8 response-bytes))

  (unless (string-prefix? response-str "Hegel/")
    (subprocess-kill proc #t)
    (error 'hegel "Bad handshake response: ~s" response-str))

  (define server-version (substring response-str (string-length "Hegel/")))
  (unless (version-in-range? server-version SUPPORTED-PROTOCOL-MIN SUPPORTED-PROTOCOL-MAX)
    (subprocess-kill proc #t)
    (error 'hegel
           "hegel-racket supports protocol versions ~a through ~a, but server is using ~a"
           SUPPORTED-PROTOCOL-MIN SUPPORTED-PROTOCOL-MAX server-version))

  ;; Register cleanup on process exit
  (plumber-add-flush!
   (current-plumber)
   (lambda (_handle)
     (subprocess-kill proc #t)))

  (hegel-session conn ctrl))
