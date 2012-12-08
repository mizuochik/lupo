{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module UtilTest (
    utilTest
  ) where

import Control.Applicative
import qualified Data.Text as T
import qualified Data.Time as Time
import Test.Framework
import Test.Framework.Providers.QuickCheck2
import Test.QuickCheck

import qualified Lupo.Util as U

instance Arbitrary Time.ZonedTime where
  arbitrary = do
    utc <- arbitrary
    pure $ Time.utcToZonedTime someTimeZone utc
    where
      someTimeZone = Time.minutesToTimeZone 0

instance Arbitrary Time.UTCTime where
  arbitrary = do
    d <- arbitrary
    pure $ Time.UTCTime d someDiffTime
    where
      someDiffTime = Time.secondsToDiffTime 0

instance Arbitrary Time.Day where
  arbitrary = do
    y <- elements [2000..2020]
    m <- elements [1..12]
    d <- elements [1..31]
    pure $ Time.fromGregorian y m d

utilTest :: Test
utilTest = testGroup "utilities" [
    testProperty "zonedDay" $ \zoned ->
      U.zonedDay zoned == Time.localDay (Time.zonedTimeToLocalTime zoned)

  , testProperty "toText" $ \(v :: Integer) ->
      U.toText v == T.pack (show v)

  , testProperty "safeIndex" $ \(xs :: [Int]) (i :: Int) ->
      case U.safeIndex xs i of
        Just x -> x == xs !! i
        Nothing -> i < 0 || length xs <= i
  ]