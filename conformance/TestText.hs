{-# LANGUAGE OverloadedStrings #-}
module Main where

import HegelFFI
import Conformance
import qualified Codec.CBOR.Term as CBOR
import Data.Maybe (catMaybes)

main :: IO ()
main = runConformance $ \tc params writer -> do
  let cats = paramStringList "categories" params
      exCats = paramStringList "exclude_categories" params
      schema = cborMap $ catMaybes
        [ Just (cborText "type", cborText "string")
        , Just (cborText "min_size", cborInt (maybe 0 fromIntegral (paramInt "min_size" params)))
        , fmap (\v -> (cborText "max_size", cborInt (fromIntegral v))) (paramInt "max_size" params)
        , fmap (\v -> (cborText "codec", cborText v)) (paramString "codec" params)
        , fmap (\v -> (cborText "min_codepoint", cborInt (fromIntegral v))) (paramInt "min_codepoint" params)
        , fmap (\v -> (cborText "max_codepoint", cborInt (fromIntegral v))) (paramInt "max_codepoint" params)
        , fmap (\v -> (cborText "categories", cborList (map cborText v))) cats
        , fmap (\v -> (cborText "exclude_categories", cborList (map cborText v))) exCats
        , fmap (\v -> (cborText "include_characters", cborText v)) (paramString "include_characters" params)
        , fmap (\v -> (cborText "exclude_characters", cborText v)) (paramString "exclude_characters" params)
        ]
  val <- generate tc schema
  case termToText val of
    Just s  -> do
      let cps = map fromEnum s
          cpsJson = "[" ++ intercalate "," (map show cps) ++ "]"
      writer $ "{\"codepoints\": " ++ cpsJson ++ "}"
    Nothing -> writer "{\"codepoints\": []}"
  where
    intercalate _ [] = ""
    intercalate _ [x] = x
    intercalate sep (x:xs) = x ++ sep ++ intercalate sep xs

paramStringList :: String -> Params -> Maybe [String]
paramStringList k ps = case lookupParam k ps of
  Just (JArr vs) -> Just [s | JStr s <- vs]
  _              -> Nothing
