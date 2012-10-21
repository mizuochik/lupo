{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolymorphicComponents #-}
{-# LANGUAGE DoAndIfThenElse #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Lupo.Database
    ( HasDatabase(..)
    , DatabaseContext
    , Entry(..)
    , Saved(..)
    , getCreatedDay
    , Database(..)
    , makeDatabase
    ) where

import Control.Applicative
import Control.Monad
import Control.Monad.Trans
import Control.Monad.CatchIO
import Data.Enumerator
import qualified Data.Enumerator.List as EL
import Data.Monoid
import qualified Data.Text as T
import qualified Data.Time as Time
import qualified Database.HDBC as DB
import Prelude hiding (all)

import Lupo.Exception
import Lupo.Util

class HasDatabase m where
    getDatabase :: m Database

class (MonadCatchIO m, Applicative m, Functor m) => DatabaseContext m

data Entry = Entry
    { title :: T.Text
    , body :: T.Text
    } deriving (Show, Eq)

data Saved o = Saved
    { idx :: Integer
    , createdAt :: Time.ZonedTime
    , modifiedAt :: Time.ZonedTime
    , refObject :: o
    } deriving Show

data Database = Database
    { select :: DatabaseContext m => Integer -> m (Saved Entry)
    , selectDay :: DatabaseContext m => Time.Day -> m [Saved Entry]
    , all :: DatabaseContext m => m (Enumerator (Saved Entry) m a)
    , search :: DatabaseContext m => T.Text -> m (Enumerator (Saved Entry) m a)
    , insert :: DatabaseContext m => Entry -> m ()
    , update :: DatabaseContext m => Integer -> Entry -> m ()
    , delete :: DatabaseContext m => Integer -> m ()
    , beforeSavedDays :: DatabaseContext m => Time.Day -> m (Enumerator Time.Day m a)
    , afterSavedDays :: DatabaseContext m => Time.Day -> m (Enumerator Time.Day m a)
    }

getCreatedDay :: Saved a -> Time.Day
getCreatedDay = zonedDay . createdAt

makeDatabase :: DB.IConnection conn => conn -> Database
makeDatabase conn = Database
    { select = \i -> do
        row <- liftIO $ do
            stmt <- DB.prepare conn "SELECT * FROM entries WHERE id = ?"
            void $ DB.execute stmt [DB.toSql i]
            DB.fetchRow stmt
        maybe (throw RecordNotFound) (pure . fromSql) row

    , selectDay = \(DB.toSql -> day) -> do
        rows <- liftIO $ do
            stmt <- DB.prepare conn "SELECT * FROM entries WHERE day = ? ORDER BY created_at ASC"
            void $ DB.execute stmt [day]
            DB.fetchAllRows stmt
        pure $ fromSql <$> rows

    , all = dbAll

    , search = \(DB.toSql -> word) -> do
        rows <- liftIO $ do
            stmt <- DB.prepare conn $
                   "SELECT * FROM entries "
                <> "WHERE title LIKE '%' || ? || '%' OR body LIKE '%' || ? || '%' "
                <> "ORDER BY id DESC"
            void $ DB.execute stmt [word, word]
            DB.fetchAllRows stmt
        pure $ enumList 1 rows $= EL.map fromSql

    , insert = \Entry {..} -> do
        liftIO $ do
            now <- Time.getZonedTime
            void $ DB.run conn
                "INSERT INTO entries (created_at, modified_at, day, title, body) VALUES (?, ?, ?, ?, ?)"
                [ DB.toSql now
                , DB.toSql now
                , DB.toSql $ zonedDay now
                , DB.toSql title
                , DB.toSql body
                ]
            DB.commit conn

    , update = \i Entry {..} -> do
        liftIO $ do
            now <- Time.getZonedTime
            void $ DB.run conn "UPDATE entries SET modified_at = ?, title = ?, body = ? WHERE id = ?"
                [ DB.toSql now
                , DB.toSql title
                , DB.toSql body
                , DB.toSql i
                ]
            DB.commit conn

    , delete = \i -> do
        liftIO $ do
            status <- DB.run conn "DELETE FROM entries WHERE id = ?" [DB.toSql i]
            if status /= 1 then
                throw RecordNotFound
            else do
                DB.commit conn

    , beforeSavedDays = \(DB.toSql -> d) -> do
        rows <- liftIO $ do
            stmt <- DB.prepare conn
                "SELECT day FROM entries WHERE day <= ? GROUP BY day ORDER BY day DESC"
            void $ DB.execute stmt [d]
            DB.fetchAllRows stmt
        pure $ enumList 1 rows $= EL.map (DB.fromSql . Prelude.head)

    , afterSavedDays = \(DB.toSql -> d) -> do
        rows <- liftIO $ do
            stmt <- DB.prepare conn
                "SELECT day FROM entries WHERE day >= ? GROUP BY day ORDER BY day ASC"
            void $ DB.execute stmt [d]
            DB.fetchAllRows stmt
        pure $ enumList 1 rows $= EL.map (DB.fromSql . Prelude.head)
    }
  where
    dbAll :: DatabaseContext m => m (Enumerator (Saved Entry) m a)
    dbAll = do
        rows <- liftIO $ do
            stmt <- DB.prepare conn "SELECT * FROM entries ORDER BY created_at DESC"
            void $ DB.execute stmt []
            DB.fetchAllRows stmt
        pure $ enumList 1 rows $= EL.map fromSql

    fromSql [ DB.fromSql -> id_
            , DB.fromSql -> c_at
            , DB.fromSql -> m_at
            , _
            , DB.fromSql -> t
            , DB.fromSql -> b ] = Saved
            { idx = id_
            , createdAt = c_at
            , modifiedAt = m_at
            , refObject = Entry {title = t, body = b}
            }
    fromSql _ = undefined