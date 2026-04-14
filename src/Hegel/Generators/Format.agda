module Hegel.Generators.Format where

open import Data.Bool.Base using (Bool; true; false)
open import Data.List.Base using (List; []; _∷_)
open import Data.Integer.Base using (ℤ; +_)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.String.Base using (String)
open import Data.Unit.Base using (⊤)
open import IO.Primitive.Core as Prim using (IO)

open import Hegel.FFI
open import Hegel.Generator
open import Hegel.Combinators using (oneOf)

-- ============================================================================
-- Format string generators
-- ============================================================================

private
  formatGen : String → Generator String
  formatGen typeName = fromBasic (mkBasicGen schema parseText)
    where
      schema = cborMap ((cborText "type" ,ᵥ cborText typeName) ∷ [])
      parseText : Value → String
      parseText v with valueToText v
      ... | just s  = s
      ... | nothing = ""

emails : Generator String
emails = formatGen "email"

urls : Generator String
urls = formatGen "url"

domains : Generator String
domains = fromBasic (mkBasicGen schema parseText)
  where
    schema = cborMap
      ( (cborText "type"       ,ᵥ cborText "domain")
      ∷ (cborText "max_length" ,ᵥ cborInt (+ 255))
      ∷ [])
    parseText : Value → String
    parseText v with valueToText v
    ... | just s  = s
    ... | nothing = ""

ipv4 : Generator String
ipv4 = formatGen "ipv4"

ipv6 : Generator String
ipv6 = formatGen "ipv6"

ipAddresses : Generator String
ipAddresses = oneOf (ipv4 ∷ ipv6 ∷ [])

dates : Generator String
dates = formatGen "date"

times : Generator String
times = formatGen "time"

datetimes : Generator String
datetimes = formatGen "datetime"

-- ============================================================================
-- fromRegex
-- ============================================================================

fromRegex : String → Generator String
fromRegex pat = fromBasic (mkBasicGen schema parseText)
  where
    schema = cborMap
      ( (cborText "type"      ,ᵥ cborText "regex")
      ∷ (cborText "pattern"   ,ᵥ cborText pat)
      ∷ (cborText "fullmatch" ,ᵥ cborBool false)
      ∷ [])
    parseText : Value → String
    parseText v with valueToText v
    ... | just s  = s
    ... | nothing = ""

fromRegexFullmatch : String → Generator String
fromRegexFullmatch pat = fromBasic (mkBasicGen schema parseText)
  where
    schema = cborMap
      ( (cborText "type"      ,ᵥ cborText "regex")
      ∷ (cborText "pattern"   ,ᵥ cborText pat)
      ∷ (cborText "fullmatch" ,ᵥ cborBool true)
      ∷ [])
    parseText : Value → String
    parseText v with valueToText v
    ... | just s  = s
    ... | nothing = ""
