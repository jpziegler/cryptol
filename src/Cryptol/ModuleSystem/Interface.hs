-- |
-- Module      :  Cryptol.ModuleSystem.Interface
-- Copyright   :  (c) 2013-2016 Galois, Inc.
-- License     :  BSD3
-- Maintainer  :  cryptol@galois.com
-- Stability   :  provisional
-- Portability :  portable

{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE RecordWildCards #-}
module Cryptol.ModuleSystem.Interface (
    Iface(..)
  , IfaceDecls(..)
  , IfaceTySyn, ifTySynName
  , IfaceNewtype
  , IfaceDecl(..), mkIfaceDecl
  , IfaceParams(..)

  , genIface
  , ifacePrimMap
  , noIfaceParams
  ) where

import           Cryptol.ModuleSystem.Name
import           Cryptol.TypeCheck.AST
import           Cryptol.Utils.Ident (ModName)
import           Cryptol.Utils.Panic(panic)
import           Cryptol.Parser.Position(Located)

import qualified Data.Map as Map
import           Data.Semigroup

import GHC.Generics (Generic)
import Control.DeepSeq

import Prelude ()
import Prelude.Compat


-- | The resulting interface generated by a module that has been typechecked.
data Iface = Iface
  { ifModName   :: !ModName     -- ^ Module name
  , ifPublic    :: IfaceDecls   -- ^ Exported definitions
  , ifPrivate   :: IfaceDecls   -- ^ Private defintiions
  , ifParams    :: IfaceParams  -- ^ Uninterpreted constants (aka module params)
  } deriving (Show, Generic, NFData)

data IfaceParams = IfaceParams
  { ifParamTypes       :: Map.Map Name ModTParam
  , ifParamConstraints :: [Located Prop] -- ^ Constraints on param. types
  , ifParamFuns        :: Map.Map Name ModVParam
  } deriving (Show, Generic, NFData)

noIfaceParams :: IfaceParams
noIfaceParams = IfaceParams
  { ifParamTypes = Map.empty
  , ifParamConstraints = []
  , ifParamFuns = Map.empty
  }

data IfaceDecls = IfaceDecls
  { ifTySyns        :: Map.Map Name IfaceTySyn
  , ifNewtypes      :: Map.Map Name IfaceNewtype
  , ifAbstractTypes :: Map.Map Name IfaceAbstractType
  , ifDecls         :: Map.Map Name IfaceDecl
  } deriving (Show, Generic, NFData)

instance Semigroup IfaceDecls where
  l <> r = IfaceDecls
    { ifTySyns   = Map.union (ifTySyns l)   (ifTySyns r)
    , ifNewtypes = Map.union (ifNewtypes l) (ifNewtypes r)
    , ifAbstractTypes = Map.union (ifAbstractTypes l) (ifAbstractTypes r)
    , ifDecls    = Map.union (ifDecls l)    (ifDecls r)
    }

instance Monoid IfaceDecls where
  mempty      = IfaceDecls Map.empty Map.empty Map.empty Map.empty
  mappend l r = l <> r
  mconcat ds  = IfaceDecls
    { ifTySyns   = Map.unions (map ifTySyns   ds)
    , ifNewtypes = Map.unions (map ifNewtypes ds)
    , ifAbstractTypes = Map.unions (map ifAbstractTypes ds)
    , ifDecls    = Map.unions (map ifDecls    ds)
    }

type IfaceTySyn = TySyn

ifTySynName :: TySyn -> Name
ifTySynName = tsName

type IfaceNewtype = Newtype
type IfaceAbstractType = AbstractType

data IfaceDecl = IfaceDecl
  { ifDeclName    :: !Name          -- ^ Name of thing
  , ifDeclSig     :: Schema         -- ^ Type
  , ifDeclPragmas :: [Pragma]       -- ^ Pragmas
  , ifDeclInfix   :: Bool           -- ^ Is this an infix thing
  , ifDeclFixity  :: Maybe Fixity   -- ^ Fixity information
  , ifDeclDoc     :: Maybe String   -- ^ Documentation
  } deriving (Show, Generic, NFData)

mkIfaceDecl :: Decl -> IfaceDecl
mkIfaceDecl d = IfaceDecl
  { ifDeclName    = dName d
  , ifDeclSig     = dSignature d
  , ifDeclPragmas = dPragmas d
  , ifDeclInfix   = dInfix d
  , ifDeclFixity  = dFixity d
  , ifDeclDoc     = dDoc d
  }

-- | Generate an Iface from a typechecked module.
genIface :: Module -> Iface
genIface m = Iface
  { ifModName = mName m

  , ifPublic      = IfaceDecls
    { ifTySyns    = tsPub
    , ifNewtypes  = ntPub
    , ifAbstractTypes = atPub
    , ifDecls     = dPub
    }

  , ifPrivate = IfaceDecls
    { ifTySyns    = tsPriv
    , ifNewtypes  = ntPriv
    , ifAbstractTypes = atPriv
    , ifDecls     = dPriv
    }

  , ifParams = IfaceParams
    { ifParamTypes = mParamTypes m
    , ifParamConstraints = mParamConstraints m
    , ifParamFuns  = mParamFuns m
    }
  }
  where

  (tsPub,tsPriv) =
      Map.partitionWithKey (\ qn _ -> qn `isExportedType` mExports m )
                          (mTySyns m)
  (ntPub,ntPriv) =
      Map.partitionWithKey (\ qn _ -> qn `isExportedType` mExports m )
                           (mNewtypes m)

  (atPub,atPriv) =
    Map.partitionWithKey (\qn _ -> qn `isExportedType` mExports m)
                         (mPrimTypes m)

  (dPub,dPriv) =
      Map.partitionWithKey (\ qn _ -> qn `isExportedBind` mExports m)
      $ Map.fromList [ (qn,mkIfaceDecl d) | dg <- mDecls m
                                          , d  <- groupDecls dg
                                          , let qn = dName d
                                          ]


-- | Produce a PrimMap from an interface.
--
-- NOTE: the map will expose /both/ public and private names.
ifacePrimMap :: Iface -> PrimMap
ifacePrimMap Iface { .. } =
  PrimMap { primDecls = merge primDecls
          , primTypes = merge primTypes }
  where
  merge f = Map.union (f public) (f private)

  public  = ifaceDeclsPrimMap ifPublic
  private = ifaceDeclsPrimMap ifPrivate

ifaceDeclsPrimMap :: IfaceDecls -> PrimMap
ifaceDeclsPrimMap IfaceDecls { .. } =
  PrimMap { primDecls = Map.fromList (newtypes ++ exprs)
          , primTypes = Map.fromList (newtypes ++ types)
          }
  where
  entry n = case asPrim n of
              Just pid -> (pid,n)
              Nothing ->
                panic "ifaceDeclsPrimMap"
                          [ "Top level name not declared in a module?"
                          , show n ]

  exprs    = map entry (Map.keys ifDecls)
  newtypes = map entry (Map.keys ifNewtypes)
  types    = map entry (Map.keys ifTySyns)
