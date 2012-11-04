{-# LANGUAGE OverloadedStrings #-}
module Lupo.Util
  ( paramId
  , paramNum
  , param
  , textSplice
  , zonedDay
  , toText
  , safeLast
  , formatTime
  ) where

import qualified Data.Attoparsec.Text as A
import qualified Data.ByteString.Char8 as BS
import qualified Data.Text.Encoding as TE
import qualified Data.Text as T
import qualified Data.Time as Time
import Prelude hiding (filter)
import Snap
import qualified Snap.Snaplet.Heist as H
import qualified System.Locale as L
import qualified Text.Templating.Heist as TH

paramId :: (MonadSnap m, Integral a) => m a
paramId = paramNum "id"

paramNum :: (MonadSnap m, Integral a) => BS.ByteString -> m a
paramNum name = either (error "invalid param type") id . toIntegral <$> param name
  where
    toIntegral = A.parseOnly A.decimal

param :: MonadSnap m => BS.ByteString -> m T.Text
param name = maybe (error "missing param") TE.decodeUtf8 <$> getParam name

textSplice :: T.Text -> H.SnapletSplice a b
textSplice = H.liftHeist . TH.textSplice

zonedDay :: Time.ZonedTime -> Time.Day
zonedDay = Time.localDay . Time.zonedTimeToLocalTime

toText :: Show a => a -> T.Text
toText = T.pack . show

safeLast :: [a] -> Maybe a
safeLast [] = Nothing
safeLast xs = Just $ last xs

formatTime :: Time.FormatTime t => String -> t -> T.Text
formatTime fmt d = T.pack $ Time.formatTime L.defaultTimeLocale fmt d
