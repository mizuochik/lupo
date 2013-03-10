{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}

module Lupo.URLMapper
  ( HasURLMapper (..)
  , URLMapper (..)
  , Path
  , getURL
  , toURLSplice
  , makeURLMapper
  ) where

import Control.Applicative
import qualified Data.ByteString.Char8 as BS
import Data.Monoid
import qualified Data.Text as T
import qualified Data.Text.Encoding as Encoding
import qualified Data.Time as Time
import Text.Shakespeare.Text
import qualified Heist.Interpreted as H

import qualified Lupo.Entry as E
import Lupo.Util

class Functor m => HasURLMapper m where
  getURLMapper :: m URLMapper

data URLMapper = URLMapper
  { entryPath :: E.Saved E.Entry -> Path
  , entryEditPath :: E.Saved E.Entry -> Path
  , singleDayPath :: Time.Day -> Path
  , multiDaysPath :: Time.Day -> Int -> Path
  , monthPath :: Time.Day -> Path
  , topPagePath :: Path
  , adminPath :: Path
  , loginPath :: Path
  , initAccountPath :: Path
  , commentPostPath :: Time.Day -> Path
  , newCommentPath :: Time.Day -> Path
  , commentsPath :: Time.Day -> Path
  , cssPath :: BS.ByteString -> Path
  , fullPath :: Path -> Path
  }

type Path = BS.ByteString

getURL :: HasURLMapper m => (URLMapper -> a) -> m a
getURL = (<$> getURLMapper)

toURLSplice :: Monad m => Path -> H.Splice m
toURLSplice = H.textSplice . Encoding.decodeUtf8

makeURLMapper :: Path -> URLMapper
makeURLMapper basePath = URLMapper
  { entryPath = \E.Saved {..} -> fullPath' $ "entries" </> show idx
  , entryEditPath = \E.Saved {..} -> fullPath' $ "admin" </> show idx </> "edit"
  , singleDayPath = fullPath' . dayPath
  , multiDaysPath = \d n -> fullPath' $ T.unpack [st|#{dayPath d}-#{show n}|]
  , monthPath = fullPath' . T.unpack . formatTime "%Y%m"
  , topPagePath = fullPath' ""
  , adminPath = fullPath' "admin"
  , loginPath = fullPath' "login"
  , initAccountPath = fullPath' "init-account"
  , commentPostPath = \d -> fullPath' $ dayPath d </> "comment#new-comment"
  , newCommentPath = \d -> fullPath' $ dayPath d <> "#new-comment"
  , commentsPath = \d -> fullPath' $ dayPath d <> "#comments"
  , cssPath = \(BS.unpack -> css) -> fullPath' $ "css" </> css
  , fullPath = \(BS.unpack -> path) -> fullPath' path
  }
  where
    dayPath = T.unpack . formatTime "%Y%m%d"
    fullPath' = BS.pack . (BS.unpack basePath </>)

    p </> c = p <> "/" <> c
    infixl 5 </>
