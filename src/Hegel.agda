-- | Hegel: Property-based testing for Agda.
--
-- This module re-exports the complete public API.
module Hegel where

-- Core FFI types and control functions
open import Hegel.FFI public
  using ( TestCase ; Value ; ByteString ; Pair ; pair ; fst ; snd
        ; assume ; note ; target
        ; cborMap ; cborText ; cborInt ; cborFloat ; cborBool ; cborNull
        ; cborList ; cborBytes ; _,ᵥ_
        ; valueToInt ; valueToFloat ; valueToBool ; valueToText
        ; valueToBytes ; valueToList
        ; generateFromSchema
        ; runHegelTest ; runHegelTests
        )

-- Generator abstraction
open import Hegel.Generator public
  using ( Generator ; BasicGenerator ; mkGen ; mkBasicGen
        ; fromBasic ; composite ; draw ; mapBasic ; drawBasic
        ; module Labels
        )

-- Combinators
open import Hegel.Combinators public
  using ( gmap ; gfilter ; flatMap ; oneOf ; optional )

-- Primitive generators
open import Hegel.Generators.Primitives public
  using ( IntegerOpts ; mkIntOpts ; defaultIntOpts
        ; integers ; integersWith ; integersIn
        ; FloatOpts ; mkFloatOpts ; defaultFloatOpts
        ; floats ; floatsWith
        ; booleans
        ; TextOpts ; mkTextOpts ; defaultTextOpts
        ; text ; textWith
        ; BinaryOpts ; mkBinaryOpts ; defaultBinaryOpts
        ; binary ; binaryWith
        ; justGen ; sampledFrom
        )

-- Collection generators
open import Hegel.Generators.Collections public
  using ( ListOpts ; mkListOpts ; defaultListOpts
        ; lists ; listsWith
        ; tuples
        ; DictOpts ; mkDictOpts ; defaultDictOpts
        ; dicts
        )

-- Format generators
open import Hegel.Generators.Format public
  using ( emails ; urls ; domains
        ; ipv4 ; ipv6 ; ipAddresses
        ; dates ; times ; datetimes
        ; fromRegex ; fromRegexFullmatch
        )
