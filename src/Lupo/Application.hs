{-# LANGUAGE TemplateHaskell
    , FlexibleInstances #-}
module Lupo.Application
    ( Lupo(Lupo, entryDB)
    , heist
    ) where

import qualified Lupo.EntryDB as EDB
import qualified Lupo.Locale as L
import Lupo.Config
import qualified Snap.Snaplet.Heist as SH
import qualified Text.Templating.Heist as H
import Snap
import Prelude hiding (filter)

data Lupo = Lupo
    { _heist :: Snaplet (SH.Heist Lupo)
    , entryDB :: EDB.EntryDB
    , lupoConfig :: LupoConfig
    , localizer :: L.Localizer
    }
makeLens ''Lupo

instance SH.HasHeist Lupo where
    heistLens = subSnaplet heist

instance EDB.MonadEntryDB (Handler Lupo Lupo) where
    getEntryDB = gets entryDB

instance EDB.MonadEntryDB (H.HeistT (Handler Lupo Lupo)) where
    getEntryDB = gets entryDB

instance GetLupoConfig (Handler Lupo Lupo) where
    getLupoConfig = gets lupoConfig

instance L.HasLocalizer (Handler Lupo Lupo) where
    refLocalizer = gets localizer

instance L.HasLocalizer (H.HeistT (Handler Lupo Lupo)) where
    refLocalizer = gets localizer
