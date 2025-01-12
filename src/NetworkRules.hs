{-# OPTIONS_GHC -Wall -fno-warn-type-defaults #-}
{-# OPTIONS_GHC -fdefer-typed-holes -fshow-hole-constraints -funclutter-valid-hole-fits #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant bracket" #-}
module NetworkRules where

import Data.Binary
import Data.ByteString hiding (head, dropWhile, elem, map, null, break, length, reverse, all)
import MinerState
import TBlock
import AccountBalance
import CryptoMagic
import Control.Exception

import qualified Data.List as DL

data SystemState = SystemState [(SenderHash, Amount)] TransList
  deriving (Show)

-- | check enough coins
checkEnoughCoins :: MinerState -> SenderHash -> Amount -> Bool
checkEnoughCoins minerState senderHash amount
  | userBalance' >= amount = True
  | otherwise = False
  where
    pendingTrans = pendingTransactions minerState
    minerBlocks = blocks minerState
    userTransactions = getListTransactions senderHash minerBlocks
    userBalance' = getBalance senderHash minerBlocks (userTransactions ++ pendingTrans)

-- | function checks the presence of a key in the dictionary, 
-- | in case of absence, adds a new key value, otherwise updates the value of the existing key
setValue :: Eq a => a -> b -> [(a, b)] -> [(a, b)]
setValue key newVal dict = newDict
  where
    indexElement = DL.elemIndex key (map fst dict)

    newDict = case indexElement of
                Just index' -> result
                  where
                    (prefix, _: suffix) = DL.splitAt index' dict
                    result = prefix ++ ((key, newVal) : suffix)
                Nothing -> (key, newVal) : dict

-- | verification of transaction signatures
-- | check that the transaction is unique (it was not before)
-- | whether there is enough money for the transaction [Block] -> Transaction -> bool
validateWholeChain :: [Block] -> TransList -> Bool
validateWholeChain blocks' = validateChain (reverse blocks') []

-- | checking the blockchain for balance, uniqueness of transactions,
-- | coherence, signature of transactions
validateChain :: [Block] -> [(SenderHash, Amount)] -> TransList -> Bool
validateChain blocks' uBalance pendingTrans = validateNonces blocks' && (case validateBlocks blocks' newState of
                                                                     Nothing -> False
                                                                     Just state@(SystemState _ _) ->
                                                                       case validateTransactions pendingTrans state of
                                                                         Nothing -> False
                                                                         Just _ -> True)
  where
    newState = Just (SystemState uBalance [])

-- | supporting function for validateChain
validateBlocks :: [Block] -> Maybe SystemState -> Maybe SystemState
validateBlocks _ Nothing = Nothing
validateBlocks [] state = state
validateBlocks (block: xs) (Just state) = case validateConnection block xs of
  False -> Nothing
  True -> case newState of
      Nothing -> Nothing
      Just _ -> validateBlocks xs newState
    where
      newState = validateBlock block state

validateNonces :: [Block] -> Bool
validateNonces = all validateBlockNonce

-- | supporting function for validateChain
validateConnection :: Block -> [Block] -> Bool
validateConnection _ [] = True
validateConnection block1 (block2: _) = getBlockHash block1 == (bPrevHash block2)

-- | supporting function for validateChain
validateBlock :: Block -> SystemState -> Maybe SystemState
validateBlock block state@(SystemState _ _) = newState
  where
    tmpState = validateTransactions (bTransList block) state
    newState = case tmpState of
      Nothing -> Nothing
      Just (SystemState usersBalance newTranses) -> Just (SystemState newUsersBalance newTranses)
        where
          newUsersBalance = case lookup (bMinerHash block) usersBalance of
            Nothing -> setValue (bMinerHash block) reward usersBalance
            Just value -> setValue (bMinerHash block) (reward + value) usersBalance

-- | supporting function for validateChain
validateTransactions :: TransList -> SystemState -> Maybe SystemState
validateTransactions [] state = Just state
validateTransactions (transaction: xs) state =
  case validateTransaction transaction state of
      Nothing -> Nothing
      Just newState' -> validateTransactions xs newState'

-- | supporting function for validateChain
validateTransaction :: Transaction -> SystemState -> Maybe SystemState
validateTransaction transaction@(Transaction senderHash recvHash amount _ _) (SystemState usersBalance transes) = result
  where
    result = if validateTransactionSignature transaction then (case DL.find (== transaction) transes of -- check is transaction in list of transactions
                                                         Just _ -> Nothing
                                                         Nothing -> case lookup senderHash usersBalance of
                                                           Nothing -> Nothing
                                                           Just senderUserBalance -> if senderUserBalance < amount then Nothing else (Just (SystemState newUsersBalance newTranses))
                                                             where
                                                               tmpUsersBalance = setValue senderHash (senderUserBalance - amount) usersBalance -- change balance of sender
                                                               newUsersBalance = case lookup recvHash tmpUsersBalance of -- change balance of recv
                                                                 Nothing -> setValue recvHash amount tmpUsersBalance
                                                                 Just recvUserBalance -> setValue recvHash (amount + recvUserBalance) tmpUsersBalance
                                                               newTranses = transaction : transes) else Nothing

-- | gets a nonсe
genNonces :: Block -> [Block]
genNonces (Block prevHash minerId _ trans transList) = blocks'
    where
        blocks' = map compueWithNonce [0,1..]
        compueWithNonce :: Nonce -> Block
        compueWithNonce nonce =
            Block prevHash minerId nonce trans transList

-- | gets a hash block that fits
mineBlock :: Block -> IO Block
mineBlock block = evaluate (head (dropWhile (not . validateBlockNonce) (genNonces block)))

-- | checks whether the block fits the network rules
validateBlockNonce :: Block -> Bool
validateBlockNonce block = case show (hashFunc (toStrict $ encode block)) of
    '0':'0':'0':'0':'0':_ -> True
    _ -> False

-- | Validates transaction signature
validateTransactionSignature :: Transaction -> Bool
validateTransactionSignature (Transaction sender receiver amount time (pubkey, signature)) =
    verifyStringMsg pubkey (toStrict $ encode trans) signature
    where
      trans = TransactionCandidate sender receiver amount time

data PreliminaryJudgement = Accept | AlreadyPresent | BranchDivergence

-- | Makes a preliminary judgement about new block
preliminaryJudgeBlock :: MinerState -> Block -> PreliminaryJudgement
preliminaryJudgeBlock minerState newBlock =
    if (elem newBlock (blocks minerState)) then
        AlreadyPresent
    else
        if getBlockHash (getNewestBlock minerState) == (bPrevHash newBlock) then
            Accept
        else
            BranchDivergence

-- | Tells if present chain part should be preserved instead of rebasing to incoming part
canPreserveLocalChainPart :: [Block] -> [Block] -> Bool
canPreserveLocalChainPart [] _ = True
canPreserveLocalChainPart _ [] = False
canPreserveLocalChainPart incoming present
  | (length incoming) > (length present) = False
  | (length incoming) < (length present) = True
  | (getBlockHash (head incoming)) < (getBlockHash (head present)) = False
  | otherwise = True

-- | Selects chain from present chain and incoming full chain of part of incoming chain with some common block(s) in the oldest
selectChain :: [Block] -> [Block] -> Either [Block] [Block]
selectChain incoming present = if canPreserveLocalChainPart incomingPart presentDivergedPart then
        Right present
    else
        Left (incomingPart ++ commonPart)
    where
        (incomingPart, commonSubpart) = break (\x -> elem x present) incoming
        firstCommonBlock = head commonSubpart
        (presentDivergedPart, commonPart) = break (== firstCommonBlock) present
