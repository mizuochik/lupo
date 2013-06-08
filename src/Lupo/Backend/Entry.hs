{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}

module Lupo.Backend.Entry
  ( makeEntryDatabase
  ) where

import Control.Applicative
import Control.Monad
import Control.Monad.CatchIO
import Control.Monad.Trans
import Control.Monad.Writer
import qualified Data.Enumerator as E
import qualified Data.Enumerator.Internal as EI
import qualified Data.Enumerator.List as EL
import qualified Data.Time as Time
import qualified Database.HDBC as DB
import Prelude hiding (all)

import Lupo.Entry
import Lupo.Exception
import qualified Lupo.FieldValidator as FV
import Lupo.Util

makeEntryDatabase :: DB.IConnection conn => conn -> (Comment -> Bool) -> IO EDBWrapper
makeEntryDatabase conn spamFilter = pure $ EDBWrapper EntryDatabase
  { selectOne = \(DB.toSql -> id') ->
      withTransactionGeneric conn $ liftIO $ do
        stmt <- useStatement pool "SELECT * FROM entries WHERE id = ?"
        void $ DB.execute stmt [id']
        row <- DB.fetchRow stmt
        maybe (throw RecordNotFound) (pure . sqlToEntry) row

  , selectAll = enumStatement "SELECT * FROM entries ORDER BY created_at DESC" [] E.$= EL.map sqlToEntry

  , selectPage = \d@(DB.toSql -> sqlDay) ->
      withTransactionGeneric conn $ do
        entries <- E.run_ $ enumStatement "SELECT * FROM entries WHERE day = ? ORDER BY created_at ASC" [sqlDay]
                       E.$= EL.map sqlToEntry
                       E.$$ EL.consume
        comments <- E.run_ $ enumStatement "SELECT * FROM comments WHERE day = ? ORDER BY created_at ASC" [sqlDay]
                        E.$= EL.map sqlToComment
                        E.$$ EL.consume
        pure $ makePage d entries comments

  , search = \(DB.toSql -> word) ->
      enumStatement "SELECT * FROM entries WHERE title LIKE '%' || ? || '%' OR body LIKE '%' || ? || '%' ORDER BY id DESC" [word, word] E.$= EL.map sqlToEntry

  , insert = \Entry {..} ->
      withTransactionGeneric conn $ liftIO $ do
        stmt <- useStatement pool "INSERT INTO entries (created_at, modified_at, day, title, body) VALUES (?, ?, ?, ?, ?)"
        now <- Time.getZonedTime
        void $ DB.execute stmt
          [ DB.toSql now
          , DB.toSql now
          , DB.toSql $ zonedDay now
          , DB.toSql entryTitle
          , DB.toSql entryBody
          ]

  , update = \i Entry {..} ->
      withTransactionGeneric conn $ liftIO $ do
        stmt <- useStatement pool "UPDATE entries SET modified_at = ?, title = ?, body = ? WHERE id = ?"
        now <- Time.getZonedTime
        void $ DB.execute stmt
          [ DB.toSql now
          , DB.toSql entryTitle
          , DB.toSql entryBody
          , DB.toSql i
          ]

  , delete = \(DB.toSql -> i) -> liftIO $
      withTransactionGeneric conn $ do
        stmt <- liftIO $ useStatement pool "DELETE FROM entries WHERE id = ?"
        status <- liftIO $ DB.execute stmt [i]
        when (status /= 1) $
          throw RecordNotFound

  , beforeSavedDays = \(DB.toSql -> d) ->
      enumStatement "SELECT day FROM entries WHERE day <= ? GROUP BY day ORDER BY day DESC" [d] E.$= EL.map (DB.fromSql . Prelude.head)

  , afterSavedDays = \(DB.toSql -> d) ->
      enumStatement "SELECT day FROM entries WHERE day >= ? GROUP BY day ORDER BY day ASC" [d] E.$= EL.map (DB.fromSql . Prelude.head)

  , insertComment = \d c@Comment {..} -> do
      FV.validate commentValidator c
      withTransactionGeneric conn $ liftIO $ do
        stmt <- useStatement pool "INSERT INTO comments (created_at, modified_at, day, name, body) VALUES (?, ?, ?, ?, ?)"
        now <- Time.getZonedTime
        void $ DB.execute stmt
          [ DB.toSql now
          , DB.toSql now
          , DB.toSql d
          , DB.toSql commentName
          , DB.toSql commentBody
          ]
  }
  where
    enumStatement stmt values step =
      withTransactionGeneric conn $ do
        stmt' <- liftIO $ useStatement pool stmt
        void $ liftIO $ DB.execute stmt' values
        loop stmt' step
      where
        loop stmt' (E.Continue f) = do
          e <- liftIO $ DB.fetchRow stmt'
          loop stmt' E.==<< f (maybe E.EOF (E.Chunks . pure) e)
        loop _ s = EI.returnI s

    pool = makeStatementPool conn

    sqlToComment [ DB.fromSql -> id'
                 , DB.fromSql -> c_at
                 , DB.fromSql -> m_at
                 , _
                 , DB.fromSql -> n
                 , DB.fromSql -> b
                 ] = Saved
      { idx = id'
      , createdAt = c_at
      , modifiedAt = m_at
      , savedContent = Comment n b
      }
    sqlToComment _ = error "in sql->comment conversion"

    commentValidator = FV.makeFieldValidator $ \c@Comment {..} -> do
      FV.checkIsEmtpy commentName "Name"
      FV.checkIsTooLong commentName "Name"
      FV.checkIsEmtpy commentBody "Content"
      FV.checkIsTooLong commentBody "Content"
      unless (spamFilter c) $ tell $ pure "Comment is invalid."

data StatementPool m = StatementPool
  { useStatement :: String -> m DB.Statement
  }

makeStatementPool :: (DB.IConnection conn, MonadIO m) => conn -> StatementPool m
makeStatementPool conn = StatementPool $ \stmt -> liftIO $ DB.prepare conn stmt

sqlToEntry :: [DB.SqlValue] -> Saved Entry
sqlToEntry [ DB.fromSql -> id'
           , DB.fromSql -> c_at
           , DB.fromSql -> m_at
           , _
           , DB.fromSql -> t
           , DB.fromSql -> b
           ] = Saved
  { idx = id'
  , createdAt = c_at
  , modifiedAt = m_at
  , savedContent = Entry t b
  }
sqlToEntry _ = error "in sql->entry conversion"

withTransactionGeneric :: (Applicative m, MonadCatchIO m, DB.IConnection conn) => conn -> m a -> m a
withTransactionGeneric conn action = onException action (liftIO $ DB.rollback conn)
                                  <* liftIO (DB.commit conn)

makePage :: Time.Day -> [Saved Entry] -> [Saved Comment] -> Page
makePage d es cs = Page
  { pageDay = d
  , pageEntries = es
  , pageComments = cs
  , numOfComments = Prelude.length cs
  }
