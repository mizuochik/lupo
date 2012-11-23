{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ViewPatterns #-}
module Lupo.PublicHandler (
    handleTop
  , handleEntries
  , handleSearch
  , handleComment
  ) where

import Control.Monad as M
import Control.Monad.CatchIO
import qualified Data.Attoparsec.Text as A
import qualified Data.Char as C
import Data.Enumerator as E hiding (head, replicate)
import qualified Data.Enumerator.List as EL
import Data.Maybe
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Time as Time
import Prelude hiding (catch, filter)
import Snap
import System.Locale
import Text.Shakespeare.Text

import Lupo.Application
import Lupo.Config
import qualified Lupo.Database as LDB
import Lupo.Exception
import qualified Lupo.Navigation as N
import Lupo.Util
import qualified Lupo.View as V

handleTop :: LupoHandler ()
handleTop = do
  db <- LDB.getDatabase
  (zonedDay -> today) <- liftIO $ Time.getZonedTime
  latest <- run_ =<< (EL.head >>==) <$> LDB.beforeSavedDays db today
  renderMultiDays (fromMaybe today latest) =<< refLupoConfig lcDaysPerPage

handleEntries :: T.Text -> LupoHandler ()
handleEntries = parseQuery $
      A.try multiDaysResponse
  <|> A.try singleDayResponse
  <|> monthResponse
  where
    parseQuery parser = either (const pass) id . A.parseOnly parser

    multiDaysResponse = do
      from <- dayParser
      void $ A.char '-'
      nentries <- read . pure <$> number
      pure $ renderMultiDays from nentries

    singleDayResponse = do
      reqDay <- dayParser
      pure $ do
        db <- LDB.getDatabase
        day <- LDB.selectDay db reqDay
        nav <- makeNavigation reqDay
        V.render $ V.singleDayView day nav (LDB.Comment "" "") []

handleSearch :: LupoHandler ()
handleSearch = do
  word <- textParam "word"
  enum <- join $ LDB.search <$> LDB.getDatabase <*> pure word
  es <- run_ $ enum $$ EL.consume
  V.render $ V.searchResultView word es

handleComment :: LupoHandler ()
handleComment = method POST $ do
  dayStr <- textParam "day"
  comment <- LDB.Comment <$> textParam"name" <*> textParam"body"
  reqDay <- either (error . show) pure $ A.parseOnly dayParser dayStr
  db <- LDB.getDatabase
  cond <- try $ LDB.insertComment db reqDay comment
  case cond of
    Left (InvalidField msgs) -> do
      dayContent <- LDB.selectDay db reqDay
      nav <- makeNavigation reqDay
      V.render $ V.singleDayView dayContent nav comment msgs
    Right _ -> redirect $ TE.encodeUtf8 [st|/#{dayStr}|]

monthResponse :: A.Parser (LupoHandler ())
monthResponse = do
  reqMonth <- monthParser
  pure $ do
    nav <- makeNavigation reqMonth
    db <- LDB.getDatabase
    enum <- LDB.afterSavedDays db reqMonth
    days <- run_ $ enum $$ toDayContents db =$ takeSameMonthDays reqMonth
    V.render $ V.monthView nav days
  where
    takeSameMonthDays m = EL.takeWhile $ isSameMonth m . LDB.day
      where
        isSameMonth (Time.toGregorian -> (year1, month1, _))
                    (Time.toGregorian -> (year2, month2, _)) =
          year1 == year2 && month1 == month2

    toDayContents db = EL.mapM $ LDB.selectDay db

    monthParser = Time.readTime defaultTimeLocale "%Y%m" <$>
      M.sequence (replicate 6 $ A.satisfy C.isDigit)

renderMultiDays :: Time.Day -> Integer -> LupoHandler ()
renderMultiDays from nDays = do
  db <- LDB.getDatabase
  enum <- LDB.beforeSavedDays db from
  targetDays <- run_ $ enum $$ EL.take nDays
  days <- Prelude.mapM (LDB.selectDay db) targetDays
  nav <- makeNavigation from
  V.render $ V.multiDaysView nav days

makeNavigation :: (Functor m, Applicative m, LDB.HasDatabase m, LDB.DatabaseContext n)
               => Time.Day -> m (N.Navigation n)
makeNavigation current = N.makeNavigation <$> LDB.getDatabase <*> pure current

dayParser :: A.Parser Time.Day
dayParser = Time.readTime defaultTimeLocale "%Y%m%d" <$> M.sequence (replicate 8 number)

number :: A.Parser Char
number = A.satisfy C.isDigit
