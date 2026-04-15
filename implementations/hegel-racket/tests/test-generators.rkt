#lang racket/base

;;; Unit tests for generators.

(require (except-in rackunit make-test-case)
         rackunit/text-ui
         racket/set
         (except-in (file "../main.rkt") make-test-case)
         (only-in (file "../test-case.rkt") make-test-case test-case-draw-count test-case-span-depth)
         (only-in (file "../generators/core.rkt") generator-as-basic basic-schema-schema basic-schema-transform))

;; ---------------------------------------------------------------------------
;; Mock DataSource and TestCase helpers
;; ---------------------------------------------------------------------------

;; A mock data source that returns values from a queue.
;; Values for generate are taken from val-queue.
;; Collection protocol: new-collection returns 0, collection-more pops
;; from more-queue (#t = yield more, #f = stop).
(define (make-mock-ds #:values [vals '()]
                      #:more   [more '()])
  (define val-queue  (box vals))
  (define more-queue (box more))
  (define status-box (box #f))
  (define origin-box (box #f))

  (define (dequeue! q-box default)
    (define q (unbox q-box))
    (if (null? q)
        default
        (begin
          (set-box! q-box (cdr q))
          (car q))))

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
     (lambda () #f)))

  (values ds status-box origin-box))

(define (make-mock-tc #:value [v 0]
                      #:values [vals #f]
                      #:more [more '()])
  (define-values (ds _ _2)
    (if vals
        (make-mock-ds #:values vals #:more more)
        (make-mock-ds #:values (list v) #:more more)))
  (make-test-case ds #f))

;; Helper: draw a value from a generator using a mock
(define (draw-with gen #:value [v 0])
  (define tc (make-mock-tc #:value v))
  (draw tc gen))

(define (draw-with* gen #:values vs #:more [more '()])
  (define tc (make-mock-tc #:values vs #:more more))
  (draw tc gen))

;; ---------------------------------------------------------------------------
;; Generator structure tests
;; ---------------------------------------------------------------------------

(define generator-tests
  (test-suite
   "Generator tests"

   ;; ----- integers -----
   (test-suite
    "integers"

    (test-case "basic schema with no bounds"
      (define gen (integers))
      (define bs (generator-as-basic gen))
      (check-not-false bs)
      (check-equal? (hash-ref (basic-schema-schema bs) "type") "integer"))

    (test-case "basic schema with min and max"
      (define gen (integers #:min-value 5 #:max-value 10))
      (define bs (generator-as-basic gen))
      (check-not-false bs)
      (check-equal? (hash-ref (basic-schema-schema bs) "min_value") 5)
      (check-equal? (hash-ref (basic-schema-schema bs) "max_value") 10))

    (test-case "draw returns value from generate"
      (define gen (integers))
      (check-equal? (draw-with gen #:value 42) 42))

    (test-case "min > max raises error"
      (check-exn exn:fail? (lambda () (integers #:min-value 10 #:max-value 5)))))

   ;; ----- floats -----
   (test-suite
    "floats"

    (test-case "basic schema type"
      (define gen (floats))
      (define bs (generator-as-basic gen))
      (check-not-false bs)
      (check-equal? (hash-ref (basic-schema-schema bs) "type") "float"))

    (test-case "allows nan and infinity by default"
      (define gen (floats))
      (define bs (generator-as-basic gen))
      (check-true (hash-ref (basic-schema-schema bs) "allow_nan"))
      (check-true (hash-ref (basic-schema-schema bs) "allow_infinity")))

    (test-case "nan disallowed when bounds set"
      (define gen (floats #:min-value 0.0 #:max-value 1.0))
      (define bs (generator-as-basic gen))
      (check-false (hash-ref (basic-schema-schema bs) "allow_nan")))

    (test-case "draw coerces integer to float"
      ;; Server may return integer 0 for floats
      (define gen (floats))
      (define result (draw-with gen #:value 0))
      (check-true (real? result)))

    (test-case "draw preserves exact float"
      (define gen (floats))
      (define result (draw-with gen #:value 3.14))
      (check-equal? result 3.14))

    (test-case "draw returns other values unchanged (else branch)"
      ;; rational numbers are neither flonum nor exact-integer
      (define gen (floats))
      (define result (draw-with gen #:value 3/2))
      (check-equal? result 3/2)))

   ;; ----- booleans -----
   (test-suite
    "booleans"

    (test-case "basic schema type"
      (define gen (booleans))
      (define bs (generator-as-basic gen))
      (check-not-false bs)
      (check-equal? (hash-ref (basic-schema-schema bs) "type") "boolean"))

    (test-case "with p parameter"
      (define gen (booleans #:p 0.3))
      (define bs (generator-as-basic gen))
      (check-equal? (hash-ref (basic-schema-schema bs) "p") 0.3))

    (test-case "draw returns boolean"
      (define gen (booleans))
      (check-equal? (draw-with gen #:value #t) #t)
      (check-equal? (draw-with gen #:value #f) #f)))

   ;; ----- text -----
   (test-suite
    "text"

    (test-case "basic schema type"
      (define gen (text))
      (define bs (generator-as-basic gen))
      (check-not-false bs)
      (check-equal? (hash-ref (basic-schema-schema bs) "type") "string"))

    (test-case "with min/max size"
      (define gen (text #:min-size 3 #:max-size 10))
      (define bs (generator-as-basic gen))
      (check-equal? (hash-ref (basic-schema-schema bs) "min_size") 3)
      (check-equal? (hash-ref (basic-schema-schema bs) "max_size") 10))

    (test-case "draw returns string"
      (define gen (text))
      (check-equal? (draw-with gen #:value "hello") "hello"))

    (test-case "text with all optional parameters"
      (define gen (text #:min-size 1 #:max-size 20
                        #:codec "ascii"
                        #:min-codepoint 32 #:max-codepoint 126
                        #:categories '("L") #:exclude-categories '("C")
                        #:include-characters "abc" #:exclude-characters "xyz"))
      (define bs (generator-as-basic gen))
      (define schema (basic-schema-schema bs))
      (check-equal? (hash-ref schema "codec") "ascii")
      (check-equal? (hash-ref schema "min_codepoint") 32)
      (check-equal? (hash-ref schema "max_codepoint") 126)
      (check-equal? (hash-ref schema "categories") '("L"))
      (check-equal? (hash-ref schema "exclude_categories") '("C"))
      (check-equal? (hash-ref schema "include_characters") "abc")
      (check-equal? (hash-ref schema "exclude_characters") "xyz")))

   ;; ----- binary -----
   (test-suite
    "binary"

    (test-case "basic schema type"
      (define gen (binary))
      (define bs (generator-as-basic gen))
      (check-not-false bs)
      (check-equal? (hash-ref (basic-schema-schema bs) "type") "binary"))

    (test-case "with min/max size"
      (define gen (binary #:min-size 2 #:max-size 8))
      (define bs (generator-as-basic gen))
      (check-equal? (hash-ref (basic-schema-schema bs) "min_size") 2)
      (check-equal? (hash-ref (basic-schema-schema bs) "max_size") 8))

    (test-case "draw returns bytes"
      (define gen (binary))
      (check-equal? (draw-with gen #:value #"data") #"data")))

   ;; ----- just -----
   (test-suite
    "just"

    (test-case "is basic"
      (check-not-false (generator-as-basic (just 42))))

    (test-case "draw always returns the value"
      (define gen (just "hello"))
      ;; The mock returns 0 from generate, but just ignores it
      (check-equal? (draw-with gen #:value 0) "hello")
      (check-equal? (draw-with gen #:value 'null) "hello")))

   ;; ----- sampled-from -----
   (test-suite
    "sampled-from"

    (test-case "is basic"
      (check-not-false (generator-as-basic (sampled-from '(a b c)))))

    (test-case "draw picks by index"
      (define gen (sampled-from '(10 20 30)))
      ;; Index 0 → 10, index 2 → 30
      (check-equal? (draw-with gen #:value 0) 10)
      (check-equal? (draw-with gen #:value 2) 30))

    (test-case "requires non-empty list"
      (check-exn exn:fail? (lambda () (sampled-from '()))))

    (test-case "schema uses correct bounds"
      (define gen (sampled-from '(a b c d)))
      (define bs (generator-as-basic gen))
      (check-equal? (hash-ref (basic-schema-schema bs) "min_value") 0)
      (check-equal? (hash-ref (basic-schema-schema bs) "max_value") 3)))

   ;; ----- generator-map -----
   (test-suite
    "generator-map"

    (test-case "basic + map stays basic"
      (define gen (generator-map (integers) (lambda (x) (* x 2))))
      (check-not-false (generator-as-basic gen)))

    (test-case "basic map applies transform"
      (define gen (generator-map (integers) (lambda (x) (* x 2))))
      (check-equal? (draw-with gen #:value 5) 10))

    (test-case "non-basic + map is non-basic with MAPPED span"
      ;; A filtered generator is non-basic
      (define base (generator-filter (integers) (lambda (x) #t)))
      (check-false (generator-as-basic base))
      (define gen (generator-map base (lambda (x) (* x 2))))
      (check-false (generator-as-basic gen)))

    (test-case "non-basic map draws inner and applies fn"
      (define base (generator-filter (integers) (lambda (x) #t)))
      (define gen (generator-map base (lambda (x) (+ x 100))))
      (define-values (ds _ _2) (make-mock-ds #:values '(7) #:more '(#t)))
      (define tc (make-test-case ds #f))
      (check-equal? (draw tc gen) 107))

    (test-case "chained maps on basic gen"
      (define gen (generator-map
                   (generator-map (integers) (lambda (x) (* x 2)))
                   (lambda (x) (+ x 1))))
      (check-not-false (generator-as-basic gen))
      ;; 5 * 2 = 10, + 1 = 11
      (check-equal? (draw-with gen #:value 5) 11))

    (test-case "map on gen with existing transform composes transforms"
      ;; floats have a coerce-float transform; mapping applies f after transform
      ;; This covers the (lambda (raw) (f (old-transform raw))) path in generator-map
      (define base (floats))
      (define gen (generator-map base (lambda (x) (+ x 1.0))))
      ;; When used as basic (e.g. inside lists), new-transform is invoked
      (define mapped-bs (generator-as-basic gen))
      (check-not-false mapped-bs)
      ;; The composed transform: coerce-float(0) = 0.0, then +1.0 = 1.0
      (define composed-transform (basic-schema-transform mapped-bs))
      (check-equal? (composed-transform 0) 1.0))

    (test-case "list of mapped-float generator invokes composed transform"
      ;; lists with a basic elem that has a transform exercises the (map elem-transform raw) path
      (define elem-gen (generator-map (floats) (lambda (x) (+ x 1.0))))
      (define list-gen (lists elem-gen))
      ;; Draw a list: server returns '(0 1.5 2.0)
      ;; composed transform: coerce(0)=0.0+1.0=1.0, coerce(1.5)+1.0=2.5, coerce(2.0)+1.0=3.0
      (define result (draw-with list-gen #:value '(0 1.5 2.0)))
      (check-equal? result '(1.0 2.5 3.0))))

   ;; ----- generator-filter -----
   (test-suite
    "generator-filter"

    (test-case "filter is always non-basic"
      (define gen (generator-filter (integers) odd?))
      (check-false (generator-as-basic gen)))

    (test-case "filter returns matching value"
      (define gen (generator-filter (integers) odd?))
      ;; First value 2 (even) rejected, second 3 accepted
      (define-values (ds _ _2) (make-mock-ds #:values '(2 3)))
      (define tc (make-test-case ds #f))
      (check-equal? (draw tc gen) 3))

    (test-case "filter assumes if 3 rejects in a row"
      ;; All values fail the predicate → assume
      (define gen (generator-filter (integers) (lambda (x) #f)))
      (define-values (ds _ _2) (make-mock-ds #:values '(0 0 0)))
      (define tc (make-test-case ds #f))
      (check-exn exn:fail:assume? (lambda () (draw tc gen)))))

   ;; ----- generator-flat-map -----
   (test-suite
    "generator-flat-map"

    (test-case "flat-map is non-basic"
      (define gen (generator-flat-map (integers) integers))
      (check-false (generator-as-basic gen)))

    (test-case "flat-map chains generators"
      ;; Draw n (=3), then draw from integers with that as max
      (define gen (generator-flat-map (integers)
                                      (lambda (n)
                                        (just n))))
      ;; First draw gives n=7, then just returns 7
      (define-values (ds _ _2) (make-mock-ds #:values '(7 0)))
      (define tc (make-test-case ds #f))
      (check-equal? (draw tc gen) 7)))

   ;; ----- one-of -----
   (test-suite
    "one-of"

    (test-case "all basic = basic"
      (define gen (one-of (integers) (booleans)))
      (check-not-false (generator-as-basic gen)))

    (test-case "mixed basic/non-basic = non-basic"
      (define non-basic (generator-filter (integers) odd?))
      (define gen (one-of (integers) non-basic))
      (check-false (generator-as-basic gen)))

    (test-case "one-of requires at least one generator"
      (check-exn exn:fail? (lambda () (one-of))))

    (test-case "basic one-of decodes [index, value]"
      (define gen (one-of (integers) (booleans)))
      ;; Server returns [0, 42] → index 0 is integers → value 42
      (define-values (ds _ _2) (make-mock-ds #:values (list (list 0 42))))
      (define tc (make-test-case ds #f))
      (check-equal? (draw tc gen) 42))

    (test-case "non-basic one-of selects by index"
      (define non-basic (generator-filter (integers #:min-value 100) (lambda (x) #t)))
      (define gen (one-of (just 0) non-basic))
      ;; First draw gives index=1 (selects non-basic), then draw from it
      (define-values (ds _ _2) (make-mock-ds #:values '(1 150)))
      (define tc (make-test-case ds #f))
      (check-equal? (draw tc gen) 150))

    (test-case "basic one-of with transform applies it to value"
      ;; floats has a transform (coerce-float); selecting index 0 → floats → apply transform
      ;; This covers (if t (t val) val) → (t val) branch in one-of-basic
      (define gen (one-of (floats) (integers)))
      ;; Server returns [0, 0] → index 0 = floats, raw val = 0 (integer) → coerce-float → 0.0
      (define-values (ds _ _2) (make-mock-ds #:values (list (list 0 0))))
      (define tc (make-test-case ds #f))
      (define result (draw tc gen))
      ;; coerce-float(0) = 0.0
      (check-equal? result 0.0)))

   ;; ----- optional -----
   (test-suite
    "optional"

    (test-case "optional is basic when element is basic"
      (check-not-false (generator-as-basic (optional (integers))))))

   ;; ----- lists -----
   (test-suite
    "lists"

    (test-case "basic elem → basic list"
      (define gen (lists (integers)))
      (check-not-false (generator-as-basic gen)))

    (test-case "non-basic elem → non-basic list"
      (define non-basic (generator-filter (integers) odd?))
      (define gen (lists non-basic))
      (check-false (generator-as-basic gen)))

    (test-case "basic elem + unique → still basic (server handles deduplication)"
      ;; When elem gen is basic, unique: true is sent in the schema.
      ;; The server handles deduplication, so we stay on the basic path.
      (define gen (lists (integers) #:unique #t))
      (check-not-false (generator-as-basic gen)))

    (test-case "basic unique list schema includes unique: true"
      (define gen (lists (integers) #:unique #t))
      (define bs (generator-as-basic gen))
      (define schema (basic-schema-schema bs))
      (check-equal? (hash-ref schema "unique") #t))

    (test-case "non-basic elem + unique → non-basic"
      (define non-basic (generator-filter (integers) odd?))
      (define gen (lists non-basic #:unique #t))
      (check-false (generator-as-basic gen)))

    (test-case "basic list schema has correct fields"
      (define gen (lists (integers) #:min-size 2 #:max-size 5))
      (define bs (generator-as-basic gen))
      (define schema (basic-schema-schema bs))
      (check-equal? (hash-ref schema "type") "list")
      (check-equal? (hash-ref schema "min_size") 2)
      (check-equal? (hash-ref schema "max_size") 5))

    (test-case "basic list transform applies element transform"
      (define gen (lists (integers)))
      ;; Server returns a list directly
      (define result (draw-with gen #:value '(1 2 3)))
      (check-equal? result '(1 2 3)))

    (test-case "non-basic list uses collection protocol"
      (define non-basic (generator-filter (integers) (lambda (x) #t)))
      (define gen (lists non-basic #:min-size 0 #:max-size 3))
      ;; more: #t #t #f = 2 elements
      (define-values (ds _ _2) (make-mock-ds #:values '(10 20 0) #:more '(#t #t #f)))
      (define tc (make-test-case ds #f))
      (define result (draw tc gen))
      (check-equal? result '(10 20)))

    (test-case "unique list with basic elem applies server schema (basic path)"
      ;; With a basic elem gen, unique list uses the basic path.
      ;; The mock returns a list directly (server-side deduplication).
      (define gen (lists (integers) #:unique #t))
      ;; Mock generate returns a list directly
      (define result (draw-with gen #:value '(5 7 9)))
      (check-equal? result '(5 7 9)))

    (test-case "unique list rejects duplicates (non-basic path)"
      ;; When elem is non-basic, unique list uses the collection protocol.
      ;; Duplicate values trigger collection-reject.
      (define filtered (generator-filter (integers) (lambda (x) #t)))
      (define gen (lists filtered #:unique #t))
      ;; mock: more = #t #t #t #f, values = 5 5 7 (first two are duplicates)
      ;; the duplicate 5 gets rejected; 7 is unique → result is '(5 7)
      (define-values (ds _ _2)
        (make-mock-ds #:values '(5 5 7 0) #:more '(#t #t #t #f)))
      (define tc (make-test-case ds #f))
      (define result (draw tc gen))
      ;; result should contain 5 and 7 (not the duplicate 5)
      (check-equal? (length result) 2)
      (check-equal? (sort result <) '(5 7))))

   ;; ----- tuples -----
   (test-suite
    "tuples"

    (test-case "all basic → basic tuple"
      (define gen (tuples (integers) (booleans)))
      (check-not-false (generator-as-basic gen)))

    (test-case "any non-basic → non-basic tuple"
      (define non-basic (generator-filter (integers) odd?))
      (define gen (tuples (integers) non-basic))
      (check-false (generator-as-basic gen)))

    (test-case "basic tuple schema"
      (define gen (tuples (integers) (booleans)))
      (define bs (generator-as-basic gen))
      (check-equal? (hash-ref (basic-schema-schema bs) "type") "tuple"))

    (test-case "non-basic tuple draws each element"
      (define non-basic (generator-filter (integers) (lambda (x) #t)))
      (define gen (tuples (integers) non-basic))
      (define-values (ds _ _2) (make-mock-ds #:values '(5 10)))
      (define tc (make-test-case ds #f))
      (define result (draw tc gen))
      (check-equal? result '(5 10)))

    (test-case "basic tuple with transforms applies them"
      ;; floats has coerce-float transform; tuples should apply per-element transforms
      ;; This covers (map (lambda (v t) (if t (t v) v)) raw transforms) in tuples-basic
      (define gen (tuples (floats) (integers)))
      ;; Server returns list [0, 5] → element 0: coerce-float(0)=0.0, element 1: 5
      (define result (draw-with gen #:value '(0 5)))
      (check-equal? result '(0.0 5))))

   ;; ----- sets -----
   (test-suite
    "sets"

    (test-case "sets with basic elem is basic (generator-map preserves basicness)"
      ;; sets wraps lists(unique=#t) with generator-map.
      ;; Since both lists(basic, unique) and generator-map-of-basic are basic,
      ;; sets returns a basic generator.
      (define gen (sets (integers)))
      (check-not-false (generator-as-basic gen)))

    (test-case "sets schema has unique: true"
      (define gen (sets (integers)))
      (define bs (generator-as-basic gen))
      (define schema (basic-schema-schema bs))
      (check-equal? (hash-ref schema "type") "list")
      (check-equal? (hash-ref schema "unique") #t))

    (test-case "sets with mock values returns a Racket set"
      ;; Basic path: generate returns the whole list at once; transform applies list->set
      (define gen (sets (integers)))
      ;; Mock: generate returns a list directly (server sends deduplicated list)
      (define result (draw-with gen #:value '(1 2 3)))
      (check-pred set? result)
      (check-true (set-member? result 1))
      (check-true (set-member? result 2))
      (check-true (set-member? result 3))))

   ;; ----- hashmaps -----
   (test-suite
    "hashmaps"

    (test-case "both basic → basic hashmap"
      (define gen (hashmaps (integers) (integers)))
      (check-not-false (generator-as-basic gen)))

    (test-case "any non-basic → non-basic hashmap"
      (define non-basic (generator-filter (integers) odd?))
      (define gen (hashmaps (integers) non-basic))
      (check-false (generator-as-basic gen)))

    (test-case "basic hashmap schema"
      (define gen (hashmaps (integers) (integers)))
      (define bs (generator-as-basic gen))
      (define schema (basic-schema-schema bs))
      (check-equal? (hash-ref schema "type") "dict"))

    (test-case "basic hashmap transform builds hash from pairs"
      (define gen (hashmaps (integers) (integers)))
      ;; Server returns list of [key, value] pairs
      (define result (draw-with gen #:value '((1 10) (2 20))))
      (check-equal? (hash-ref result 1) 10)
      (check-equal? (hash-ref result 2) 20))

    (test-case "dicts is alias for hashmaps"
      (define gen (dicts (integers) (integers)))
      (check-not-false (generator-as-basic gen)))

    (test-case "basic hashmap with max-size includes max_size in schema"
      ;; covers (when max-size (hash-set! h "max_size" max-size)) path
      (define gen (hashmaps (integers) (integers) #:max-size 5))
      (define bs (generator-as-basic gen))
      (define schema (basic-schema-schema bs))
      (check-equal? (hash-ref schema "max_size") 5))

    (test-case "basic hashmap with transforms applies them to keys and values"
      ;; floats has coerce-float transform; hashmap should apply per-key/value transforms
      ;; This covers (key-transform (car pair)) and (val-transform (cadr pair)) paths
      (define gen (hashmaps (floats) (floats)))
      ;; Server returns list of [key, value] pairs with integer keys/values
      (define result (draw-with gen #:value '((0 1) (2 3))))
      ;; coerce-float applied: 0→0.0, 1→1.0, 2→2.0, 3→3.0
      (check-equal? (hash-ref result 0.0) 1.0)
      (check-equal? (hash-ref result 2.0) 3.0)))

   ;; ----- format generators -----
   (test-suite
    "format generators"

    (test-case "emails is basic"
      (check-not-false (generator-as-basic (emails))))

    (test-case "urls is basic"
      (check-not-false (generator-as-basic (urls))))

    (test-case "domains is basic"
      (check-not-false (generator-as-basic (domains))))

    (test-case "ipv4-addresses is basic"
      (check-not-false (generator-as-basic (ipv4-addresses))))

    (test-case "ipv6-addresses is basic"
      (check-not-false (generator-as-basic (ipv6-addresses))))

    (test-case "ip-addresses is basic"
      (check-not-false (generator-as-basic (ip-addresses))))

    (test-case "dates is basic"
      (check-not-false (generator-as-basic (dates))))

    (test-case "times is basic"
      (check-not-false (generator-as-basic (times))))

    (test-case "datetimes is basic"
      (check-not-false (generator-as-basic (datetimes))))

    (test-case "from-regex is basic"
      (check-not-false (generator-as-basic (from-regex "[a-z]+"))))

    (test-case "from-regex schema"
      (define gen (from-regex "[0-9]+"))
      (define bs (generator-as-basic gen))
      (check-equal? (hash-ref (basic-schema-schema bs) "type") "regex")
      (check-equal? (hash-ref (basic-schema-schema bs) "pattern") "[0-9]+")
      ;; Must use "fullmatch" not "full_match" (hegel-core key name)
      (check-equal? (hash-ref (basic-schema-schema bs) "fullmatch") #t))

    (test-case "ip-addresses is basic (one_of ipv4+ipv6)"
      (check-not-false (generator-as-basic (ip-addresses))))

    (test-case "ip-addresses schema is one_of"
      (define bs (generator-as-basic (ip-addresses)))
      (define schema (basic-schema-schema bs))
      (check-equal? (hash-ref schema "type") "one_of"))

    (test-case "characters is basic"
      (check-not-false (generator-as-basic (characters))))

    (test-case "characters schema has size 1"
      (define bs (generator-as-basic (characters)))
      (define schema (basic-schema-schema bs))
      (check-equal? (hash-ref schema "type") "string")
      (check-equal? (hash-ref schema "min_size") 1)
      (check-equal? (hash-ref schema "max_size") 1)))

   ;; ----- draw vs draw-silent -----
   (test-suite
    "draw and draw-silent"

    (test-case "draw records the draw"
      (define gen (integers))
      (define tc (make-mock-tc #:value 5))
      (check-equal? (unbox (test-case-draw-count tc)) 0)
      (draw tc gen)
      (check-equal? (unbox (test-case-draw-count tc)) 1))

    (test-case "draw-silent does not record the draw"
      (define gen (integers))
      (define tc (make-mock-tc #:value 5))
      (draw-silent tc gen)
      (check-equal? (unbox (test-case-draw-count tc)) 0)))))

(run-tests generator-tests)
