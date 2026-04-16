#lang racket/base

;;; Unit tests for session helper functions.

(require rackunit
         rackunit/text-ui
         racket/file
         (only-in (file "../session.rkt")
                  parse-version version<=? version-in-range? find-uv
                  hegel-command init-session HEGEL-SERVER-COMMAND-ENV))

(define session-tests
  (test-suite
   "Session helper tests"

   (test-suite
    "parse-version"

    (test-case "parses valid version string"
      (define v (parse-version "0.10"))
      (check-equal? (car v) 0)
      (check-equal? (cdr v) 10))

    (test-case "parses major.minor"
      (define v (parse-version "2.5"))
      (check-equal? (car v) 2)
      (check-equal? (cdr v) 5))

    (test-case "raises on non-major.minor format"
      ;; String without exactly one dot raises an error
      (check-exn exn:fail?
        (lambda () (parse-version "1.2.3")))
      (check-exn exn:fail?
        (lambda () (parse-version "1"))))

    (test-case "raises on non-numeric parts"
      (check-exn exn:fail?
        (lambda () (parse-version "a.b")))
      (check-exn exn:fail?
        (lambda () (parse-version "1.x")))))

   (test-suite
    "version<=?"

    (test-case "lower major is <=?"
      (check-true (version<=? '(0 . 9) '(1 . 0))))

    (test-case "equal versions are <=?"
      (check-true (version<=? '(1 . 5) '(1 . 5))))

    (test-case "lower minor same major is <=?"
      (check-true (version<=? '(1 . 4) '(1 . 5))))

    (test-case "higher version is not <=?"
      (check-false (version<=? '(1 . 6) '(1 . 5))))

    (test-case "higher major is not <=?"
      (check-false (version<=? '(2 . 0) '(1 . 9)))))

   (test-suite
    "version-in-range?"

    (test-case "version in range returns #t"
      (check-true (version-in-range? "0.10" "0.10" "0.10")))

    (test-case "version below range returns #f"
      (check-false (version-in-range? "0.9" "0.10" "0.11")))

    (test-case "version above range returns #f"
      (check-false (version-in-range? "0.12" "0.10" "0.11")))

    (test-case "version at min boundary returns #t"
      (check-true (version-in-range? "0.10" "0.10" "0.11")))

    (test-case "version at max boundary returns #t"
      (check-true (version-in-range? "0.11" "0.10" "0.11"))))

   (test-suite
    "find-uv"

    (test-case "returns a string"
      ;; find-uv should always return a string (either a path or 'uv' fallback)
      (define result (find-uv))
      (check-pred string? result))

    (test-case "finds uv via common-locations when not on PATH"
      ;; Covers the (for/or ... common-locations) fallback path in find-uv.
      ;; Creates a temporary file to serve as a fake uv at a known location,
      ;; so the test doesn't depend on where uv is actually installed.
      (define fake-uv (make-temporary-file "uv~a"))
      (dynamic-wind
        void
        (lambda ()
          (parameterize ([current-environment-variables
                          (environment-variables-copy (current-environment-variables))])
            ;; Set PATH to empty so find-executable-path cannot find uv
            (environment-variables-set! (current-environment-variables) #"PATH" #"")
            ;; Pass our fake location to exercise the (for/or) fallback branch
            (define result (find-uv (list (path->string fake-uv))))
            (check-pred string? result)
            ;; It should be the absolute path, not just "uv"
            (check-true (> (string-length result) 2))))
        (lambda ()
          (when (file-exists? fake-uv) (delete-file fake-uv)))))

    (test-case "falls back to \"uv\" string when PATH is empty and no common locations exist"
      ;; Covers the \"uv\" fallback string in find-uv when all locations fail
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables) #"PATH" #"")
        ;; Pass empty locations list so no common location exists
        (define result (find-uv '()))
        (check-equal? result "uv"))))

   (test-suite
    "hegel-command"

    (test-case "returns override list when HEGEL_SERVER_COMMAND is set"
      ;; Covers (list override) branch in hegel-command
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    (string->bytes/utf-8 HEGEL-SERVER-COMMAND-ENV)
                                    #"/usr/bin/fake-server")
        (define cmd (hegel-command))
        (check-equal? cmd '("/usr/bin/fake-server"))))

    (test-case "returns uv-based command when HEGEL_SERVER_COMMAND not set"
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    (string->bytes/utf-8 HEGEL-SERVER-COMMAND-ENV)
                                    #f)
        (define cmd (hegel-command))
        (check-true (list? cmd))
        (check-true (> (length cmd) 1)))))

   (test-suite
    "init-session error paths"

    (test-case "init-session raises on bad handshake response"
      ;; Covers bad-handshake subprocess-kill + error path in init-session
      ;; Use a mock server that sends "INVALID_RESPONSE" as the handshake reply
      (define mock-server-script (make-temporary-file "mock-server-~a.py"))
      (display-to-file
       (string-append
        "#!/usr/bin/env -S uv run\n"
        "# /// script\n"
        "# requires-python = \">=3.9\"\n"
        "# dependencies = [\"hegel-core==0.4.0\"]\n"
        "# ///\n"
        "import sys\n"
        "from hegel.protocol.connection import Connection\n"
        "class StdioTransport:\n"
        "    def recv(self, n):\n"
        "        data = sys.stdin.buffer.read(n)\n"
        "        return data if data else b''\n"
        "    def sendall(self, data):\n"
        "        sys.stdout.buffer.write(data)\n"
        "        sys.stdout.buffer.flush()\n"
        "    def settimeout(self, t): pass\n"
        "    def shutdown(self, h): pass\n"
        "    def close(self): pass\n"
        "conn = Connection(StdioTransport())\n"
        "req = conn.control_stream.read_request()\n"
        "conn.control_stream.write_reply_bytes(req.message_id, b'INVALID_RESPONSE')\n"
        "import time; time.sleep(30)\n")
       mock-server-script #:exists 'replace)
      (file-or-directory-permissions mock-server-script #o755)
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    (string->bytes/utf-8 HEGEL-SERVER-COMMAND-ENV)
                                    (string->bytes/utf-8 (path->string mock-server-script)))
        (check-exn exn:fail?
          (lambda () (init-session))))
      (delete-file mock-server-script))

    (test-case "init-session raises on unsupported server version"
      ;; Covers version-mismatch subprocess-kill + error path in init-session
      (define mock-server-script (make-temporary-file "mock-server-~a.py"))
      (display-to-file
       (string-append
        "#!/usr/bin/env -S uv run\n"
        "# /// script\n"
        "# requires-python = \">=3.9\"\n"
        "# dependencies = [\"hegel-core==0.4.0\"]\n"
        "# ///\n"
        "import sys\n"
        "from hegel.protocol.connection import Connection\n"
        "class StdioTransport:\n"
        "    def recv(self, n):\n"
        "        data = sys.stdin.buffer.read(n)\n"
        "        return data if data else b''\n"
        "    def sendall(self, data):\n"
        "        sys.stdout.buffer.write(data)\n"
        "        sys.stdout.buffer.flush()\n"
        "    def settimeout(self, t): pass\n"
        "    def shutdown(self, h): pass\n"
        "    def close(self): pass\n"
        "conn = Connection(StdioTransport())\n"
        "req = conn.control_stream.read_request()\n"
        "conn.control_stream.write_reply_bytes(req.message_id, b'Hegel/99.99')\n"
        "import time; time.sleep(30)\n")
       mock-server-script #:exists 'replace)
      (file-or-directory-permissions mock-server-script #o755)
      (parameterize ([current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    (string->bytes/utf-8 HEGEL-SERVER-COMMAND-ENV)
                                    (string->bytes/utf-8 (path->string mock-server-script)))
        (check-exn exn:fail?
          (lambda () (init-session))))
      (delete-file mock-server-script))

    (test-case "plumber cleanup kills server subprocess on flush"
      ;; Covers (subprocess-kill proc #t) in the plumber-add-flush! callback
      ;; Uses a mock server that completes the handshake and then sleeps
      (define mock-server-script (make-temporary-file "mock-server-~a.py"))
      (display-to-file
       (string-append
        "#!/usr/bin/env -S uv run\n"
        "# /// script\n"
        "# requires-python = \">=3.9\"\n"
        "# dependencies = [\"hegel-core==0.4.0\"]\n"
        "# ///\n"
        "import sys, time\n"
        "from hegel.protocol.connection import Connection\n"
        "class StdioTransport:\n"
        "    def recv(self, n):\n"
        "        data = sys.stdin.buffer.read(n)\n"
        "        return data if data else b''\n"
        "    def sendall(self, data):\n"
        "        sys.stdout.buffer.write(data)\n"
        "        sys.stdout.buffer.flush()\n"
        "    def settimeout(self, t): pass\n"
        "    def shutdown(self, h): pass\n"
        "    def close(self): pass\n"
        "conn = Connection(StdioTransport())\n"
        "conn.receive_handshake()\n"  ; completes handshake (sends Hegel/0.10)
        "time.sleep(30)\n")           ; wait to be killed by plumber flush
       mock-server-script #:exists 'replace)
      (file-or-directory-permissions mock-server-script #o755)
      ;; Use a fresh plumber so we don't interfere with the real session's plumber
      (define test-plumber (make-plumber))
      (parameterize ([current-plumber test-plumber]
                     [current-environment-variables
                      (environment-variables-copy (current-environment-variables))])
        (environment-variables-set! (current-environment-variables)
                                    (string->bytes/utf-8 HEGEL-SERVER-COMMAND-ENV)
                                    (string->bytes/utf-8 (path->string mock-server-script)))
        ;; init-session spawns the mock server, completes handshake, registers cleanup
        (define sess (init-session))
        (check-not-false sess)
        ;; Flushing the plumber invokes (subprocess-kill proc #t) -- covers the cleanup callback
        (plumber-flush-all test-plumber))
      (delete-file mock-server-script)))))

(run-tests session-tests)
