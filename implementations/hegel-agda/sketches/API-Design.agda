{-
  API Design Sketch: Core types and module structure for hegel-agda.
  This is the authoritative design document. Not expected to compile yet.

  Architecture:
  - Protocol layer (CBOR, packets, connection, streams) is in Haskell,
    exposed to Agda via {-# FOREIGN GHC #-} and postulates.
  - Generator types, combinators, and user API are in Agda.
  - The Agda code compiles to Haskell via the GHC backend.
-}

-- =============================================================================
-- Module: Hegel.Core — Opaque types from Haskell FFI
-- =============================================================================
module Hegel.Core where

-- These are backed by Haskell types via FOREIGN GHC pragmas
postulate
  TestCase    : Set     -- opaque handle to the current test case
  Connection  : Set     -- opaque handle to the server connection
  Value       : Set     -- CBOR value type (maps to Haskell's CBOR Value)
  Schema      : Set     -- CBOR schema (a Value used as a generation schema)

-- =============================================================================
-- Module: Hegel.Generator — The Generator abstraction
-- =============================================================================
module Hegel.Generator where

open import Hegel.Core

-- A BasicGenerator has a schema and an optional transform.
-- map on a BasicGenerator produces a new BasicGenerator (preserving schema).
record BasicGenerator (A : Set) : Set where
  field
    schema    : Schema
    transform : Value → A

-- A Generator can produce values of type A from a TestCase.
-- It may or may not have a basic (schema-based) representation.
record Generator (A : Set) : Set₁ where
  field
    generate : TestCase → IO A
    asBasic  : Maybe (BasicGenerator A)

-- Smart constructor: lift a BasicGenerator to a Generator
fromBasic : {A : Set} → BasicGenerator A → Generator A

-- =============================================================================
-- Module: Hegel.Combinators — map, filter, flatMap
-- =============================================================================
module Hegel.Combinators where

-- map: preserves basicness when source is basic
gmap : {A B : Set} → (A → B) → Generator A → Generator B

-- filter: always produces a composite generator
gfilter : {A : Set} → (A → Bool) → Generator A → Generator A

-- flatMap: always produces a composite generator
flatMap : {A B : Set} → Generator A → (A → Generator B) → Generator B

-- =============================================================================
-- Module: Hegel.Generators.Primitives
-- =============================================================================
module Hegel.Generators.Primitives where

-- Integer generation
record IntegerOpts : Set where
  field
    minValue : Maybe ℤ
    maxValue : Maybe ℤ

defaultIntegerOpts : IntegerOpts

integers : Generator ℤ                          -- unbounded (within Int64)
integersWith : IntegerOpts → Generator ℤ         -- with options
integersIn : ℤ → ℤ → Generator ℤ                 -- convenience: min, max

-- Float generation
record FloatOpts : Set where
  field
    minValue      : Maybe Float
    maxValue      : Maybe Float
    allowNaN      : Bool        -- default: true (when no bounds)
    allowInfinity : Bool        -- default: true (when no bounds)
    excludeMin    : Bool        -- default: false
    excludeMax    : Bool        -- default: false

defaultFloatOpts : FloatOpts

floats : Generator Float
floatsWith : FloatOpts → Generator Float
floatsIn : Float → Float → Generator Float

-- Boolean generation
booleans : Generator Bool

-- Text generation
record TextOpts : Set where
  field
    minSize           : ℕ
    maxSize           : Maybe ℕ
    -- Character filtering (all optional)
    codec             : Maybe String
    minCodepoint      : Maybe ℕ
    maxCodepoint      : Maybe ℕ
    categories        : Maybe (List String)
    excludeCategories : Maybe (List String)
    includeCharacters : Maybe String
    excludeCharacters : Maybe String

defaultTextOpts : TextOpts

text : Generator String
textWith : TextOpts → Generator String

-- Binary generation
record BinaryOpts : Set where
  field
    minSize : ℕ
    maxSize : Maybe ℕ

defaultBinaryOpts : BinaryOpts

binary : Generator ByteString
binaryWith : BinaryOpts → Generator ByteString

-- Constant value
just : {A : Set} → A → Generator A

-- Sample from a list
sampledFrom : {A : Set} → List A → Generator A

-- =============================================================================
-- Module: Hegel.Generators.Collections
-- =============================================================================
module Hegel.Generators.Collections where

record ListOpts : Set where
  field
    minSize : ℕ
    maxSize : Maybe ℕ

defaultListOpts : ListOpts

lists : {A : Set} → Generator A → Generator (List A)
listsWith : {A : Set} → ListOpts → Generator A → Generator (List A)

tuples : {A B : Set} → Generator A → Generator B → Generator (A × B)

record DictOpts : Set where
  field
    minSize : ℕ
    maxSize : Maybe ℕ

defaultDictOpts : DictOpts

dicts : {K V : Set} → Generator K → Generator V → Generator (List (K × V))
dictsWith : {K V : Set} → DictOpts → Generator K → Generator V
          → Generator (List (K × V))

-- =============================================================================
-- Module: Hegel.Generators.Combinators
-- =============================================================================
module Hegel.Generators.Combinators where

oneOf : {A : Set} → List (Generator A) → Generator A
optional : {A : Set} → Generator A → Generator (Maybe A)

-- =============================================================================
-- Module: Hegel.Generators.Format — format string generators
-- =============================================================================
module Hegel.Generators.Format where

emails    : Generator String
urls      : Generator String
domains   : Generator String
ipv4      : Generator String
ipv6      : Generator String
dates     : Generator String      -- ISO format dates
times     : Generator String      -- ISO format times
datetimes : Generator String      -- ISO format datetimes

-- =============================================================================
-- Module: Hegel.Generators.Regex
-- =============================================================================
module Hegel.Generators.Regex where

record RegexOpts : Set where
  field
    fullmatch : Bool            -- default: false

defaultRegexOpts : RegexOpts

fromRegex : String → Generator String
fromRegexWith : RegexOpts → String → Generator String

-- =============================================================================
-- Module: Hegel.Control — Test control functions
-- =============================================================================
module Hegel.Control where

-- Reject the current test case (non-local exit via Haskell exception)
assume : TestCase → Bool → IO ⊤

-- Record a note for debugging (shown on final failing case)
note : TestCase → String → IO ⊤

-- Guide the search toward higher values
target : TestCase → Float → String → IO ⊤

-- Draw a value from a generator
draw : {A : Set} → TestCase → Generator A → IO A

-- =============================================================================
-- Module: Hegel.Settings — Test configuration
-- =============================================================================
module Hegel.Settings where

data Verbosity : Set where
  quiet normal verbose debug : Verbosity

data HealthCheck : Set where
  tooSlow    : HealthCheck
  filterTooMuch : HealthCheck

record Settings : Set where
  field
    testCases          : ℕ
    seed               : Maybe ℕ
    derandomize        : Bool
    database           : Maybe String
    suppressHealthCheck : List HealthCheck
    verbosity          : Verbosity

defaultSettings : Settings
defaultSettings = record
  { testCases           = 100
  ; seed                = nothing
  ; derandomize         = false
  ; database            = nothing
  ; suppressHealthCheck = []
  ; verbosity           = normal
  }

-- =============================================================================
-- Module: Hegel — Top-level re-exports
-- =============================================================================
module Hegel where

-- Run a single named test
runHegelTest : Settings → (TestCase → IO ⊤) → IO ⊤

-- Run multiple named tests
runHegelTests : Settings → List (String × (TestCase → IO ⊤)) → IO ⊤

-- Re-export everything the user needs:
-- draw, assume, note, target
-- Generator, BasicGenerator
-- integers, floats, booleans, text, binary, just, sampledFrom
-- lists, tuples, dicts, oneOf, optional
-- gmap, gfilter, flatMap
-- emails, urls, domains, ipv4, ipv6, dates, times, datetimes
-- fromRegex
-- Settings, defaultSettings
