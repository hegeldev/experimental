#lang racket/base

;;; Re-exports all generators.

(require "core.rkt"
         "numeric.rkt"
         "strings.rkt"
         "misc.rkt"
         "collections.rkt"
         "format.rkt")

(provide
 ;; Core
 generator?
 generator-map
 generator-flat-map
 generator-filter
 draw
 draw-silent

 ;; Numeric
 integers
 floats
 booleans

 ;; Strings
 text
 binary

 ;; Misc
 just
 sampled-from
 one-of
 optional

 ;; Collections
 lists
 tuples
 dicts
 hashmaps

 ;; Format
 emails
 urls
 domains
 ipv4-addresses
 ipv6-addresses
 ip-addresses
 dates
 times
 datetimes
 from-regex)
