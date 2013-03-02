{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Lupo.Application
  ( Lupo (Lupo, entryDB)
  , LupoHandler
  , heist
  , session
  , auth
  , getNoticeDB
  ) where

import Control.Lens
import Control.Monad
import Prelude hiding (filter)
import Snap
import qualified Snap.Snaplet.Auth as A
import qualified Snap.Snaplet.Heist as SH
import qualified Snap.Snaplet.Session as S

import Lupo.Config
import qualified Lupo.Entry as E
import qualified Lupo.Locale as L
import qualified Lupo.Notice as N
import qualified Lupo.URLMapper as U

data Lupo = Lupo
  { _heist :: Snaplet (SH.Heist Lupo)
  , _session :: Snaplet S.SessionManager
  , _auth :: Snaplet (A.AuthManager Lupo)
  , entryDB :: E.DatabaseContext m => IO (E.EntryDatabase m)
  , lupoConfig :: LupoConfig
  , localizer :: L.Localizer
  , noticeDB :: forall b. N.NoticeDB (Handler b Lupo)
  , urlMapper :: U.URLMapper
  }
makeLenses ''Lupo

type LupoHandler = Handler Lupo Lupo

instance SH.HasHeist Lupo where
  heistLens = subSnaplet heist

instance (E.DatabaseContext m, MonadState Lupo m) => E.HasDatabase m where
  getDatabase = do
    getDB <- gets entryDB
    liftIO getDB

instance (MonadState Lupo m, Applicative m, Functor m) => GetLupoConfig m where
  getLupoConfig = gets lupoConfig

instance (MonadState Lupo m, Applicative m, Functor m) => L.HasLocalizer m where
  refLocalizer = gets localizer

instance (MonadState Lupo m, Applicative m, Functor m) => U.HasURLMapper m where
  getURLMapper = gets urlMapper

getNoticeDB :: MonadState Lupo m => m (N.NoticeDB LupoHandler)
getNoticeDB = gets noticeDB
