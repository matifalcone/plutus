{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE MonoLocalBinds      #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fno-warn-incomplete-uni-patterns -fno-warn-unused-do-bind #-}
module Spec.Vesting(tests, retrieveFundsTrace, vesting) where

import Control.Monad (void)
import           Test.Tasty
import qualified Test.Tasty.HUnit                                 as HUnit

import           Spec.Lib                                         as Lib

import qualified Language.PlutusTx                                as PlutusTx
import           Language.PlutusTx.Coordination.Contracts.Vesting
import           Language.PlutusTx.Lattice
import qualified Language.PlutusTx.Numeric                        as Numeric
import qualified Ledger
import qualified Ledger.Ada                                       as Ada

import           Language.Plutus.Contract.Test
import qualified Plutus.Trace.Emulator    as Trace
import Plutus.Trace.Emulator (EmulatorTrace)
import           Prelude                                          hiding (not)

w1, w2 :: Wallet
w1 = Wallet 1
w2 = Wallet 2

tests :: TestTree
tests =
    let con = vestingContract vesting in
    testGroup "vesting"
    [ checkPredicate "secure some funds with the vesting script"
        (walletFundsChange w2 (Numeric.negate $ totalAmount vesting))
        $ do
            hdl <- Trace.activateContractWallet w2 con
            Trace.callEndpoint @"vest funds" w2 hdl ()

    , checkPredicate "retrieve some funds"
        (walletFundsChange w2 (Numeric.negate $ totalAmount vesting)
        .&&. assertNoFailedTransactions
        .&&. walletFundsChange w1 (Ada.lovelaceValueOf 10))
        retrieveFundsTrace

    , checkPredicate "cannot retrieve more than allowed"
        (walletFundsChange w1 mempty
        .&&. assertContractError con (Trace.walletInstanceTag w1) (== expectedError) "error should match")
        $ do
            hdl1 <- Trace.activateContractWallet w1 con
            hdl2 <- Trace.activateContractWallet w2 con
            Trace.callEndpoint @"vest funds" w2 hdl2 ()
            Trace.waitNSlots 10
            Trace.callEndpoint @"retrieve funds" w1 hdl1 (Ada.lovelaceValueOf 30)
            void $ Trace.waitNSlots 1

    , checkPredicate "can retrieve everything at the end"
        (walletFundsChange w1 (totalAmount vesting)
        .&&. assertNoFailedTransactions
        .&&. assertDone con (Trace.walletInstanceTag w1) (const True) "should be done")
        $ do
            hdl1 <- Trace.activateContractWallet w1 con
            hdl2 <- Trace.activateContractWallet w2 con
            Trace.callEndpoint @"vest funds" w2 hdl2 ()
            Trace.waitNSlots 20
            Trace.callEndpoint @"retrieve funds" w1 hdl1 (totalAmount vesting)
            void $ Trace.waitNSlots 1

    , Lib.goldenPir "test/Spec/vesting.pir" $$(PlutusTx.compile [|| validate ||])
    , HUnit.testCase "script size is reasonable" (Lib.reasonable (vestingScript vesting) 33000)
    ]

-- | The scenario used in the property tests. It sets up a vesting scheme for a
--   total of 60 lovelace over 20 blocks (20 lovelace can be taken out before
--   that, at 10 blocks).
vesting :: VestingParams
vesting =
    VestingParams
        { vestingTranche1 = VestingTranche (Ledger.Slot 10) (Ada.lovelaceValueOf 20)
        , vestingTranche2 = VestingTranche (Ledger.Slot 20) (Ada.lovelaceValueOf 40)
        , vestingOwner    = Ledger.pubKeyHash $ walletPubKey w1 }

retrieveFundsTrace :: EmulatorTrace ()
retrieveFundsTrace = do
    let con = vestingContract @VestingError vesting
    hdl1 <- Trace.activateContractWallet w1 con
    hdl2 <- Trace.activateContractWallet w2 con
    Trace.callEndpoint @"vest funds" w2 hdl2 ()
    Trace.waitNSlots 10
    Trace.callEndpoint @"retrieve funds" w1 hdl1 (Ada.lovelaceValueOf 10)
    void $ Trace.waitNSlots 1

expectedError :: VestingError
expectedError =
    let payment = Ada.lovelaceValueOf 30
        maxPayment = Ada.lovelaceValueOf 20
        mustRemainLocked = Ada.lovelaceValueOf 40
    in InsufficientFundsError payment maxPayment mustRemainLocked
