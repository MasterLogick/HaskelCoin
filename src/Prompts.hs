{-# LANGUAGE TypeApplications #-}
module Prompts where

import Control.Concurrent.MVar
import MinerState
import qualified Control.Exception as CE 
import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Base64.URL as DBU
import Data.ByteString
import System.IO
import Data.Complex (imagPart)
import CryptoHandler
import CryptoMagic
import FilesMagic
import NetworkMagic

data ResponceJudgement = Accepted | Reject | WrongResponce

-- | Outputs and inputs in concole with prompt.
prompt :: String -> IO ByteString
prompt text = do
    System.IO.putStr text
    hFlush stdout
    Data.ByteString.getLine

checkUserResponse :: String -> ResponceJudgement
checkUserResponse response = 
    case response of
        "Yes" -> Accepted
        "yes" -> Accepted
        "y"   -> Accepted
        "Y"   -> Accepted
        "No"  -> Reject
        "no"  -> Reject
        "n"   -> Reject
        "N"   -> Reject
        _     ->  WrongResponce


-- | Starts parsing command for getting private key.
startParseCommand :: MVar MinerState -> IO()
startParseCommand minerState = do
    putStrLn "Do you want to generate new private key? Yes/No"
    byteInput <- prompt "answer> "
    let input = C8.unpack byteInput
    case checkUserResponse input of
        Accepted -> accept
        Reject -> reject
        WrongResponce -> do
            putStrLn "ERROR: unrecognized command"
            startParseCommand minerState
    where 
        accept = genPair minerState
        reject = do
            putStrLn "Enter your private key:"
            privateKey <- prompt "Private key> "
            publicKey <- CE.evaluate $ generatePublic (DBU.decodeLenient privateKey)
            modifyMVar_ minerState (\miner -> return miner{keyPair = (DBU.decodeLenient privateKey, publicKey)})


-- | Starts parsing command for uploading backup of chain from file.
startParseBackup :: MVar MinerState -> IO()
startParseBackup stateRef = do
    putStrLn "Do you want to load backup of chain from file? Yes/No"
    byteInput <- prompt "answer> "
    let input = C8.unpack byteInput
    case checkUserResponse input of
        Accepted -> accept
        Reject -> reject
        WrongResponce -> do
            putStrLn "ERROR: unrecognized command"
            startParseBackup stateRef
    where 
        accept = do
            path <- prompt "Enter your path:"
            loadBlocks path stateRef
        reject = return ()

-- | Starts parsing command for connecting to the network.
startParseConnect :: MVar MinerState -> IO()
startParseConnect stateRef = do
    putStrLn "Do you want to connect to the network? Yes/No"
    byteInput <- prompt "answer> "
    let input = C8.unpack byteInput
    case checkUserResponse input of
        Accepted -> accept
        Reject -> reject
        WrongResponce -> do
            putStrLn "ERROR: unrecognized command"
            startParseConnect stateRef
    where 
        accept = do
            ip <- prompt "Enter your remote ip:"
            port <- prompt "Enter your remote port:"
            connectAndSync ip port stateRef
        reject = return ()

-- | Starts parsing command for listening network.
startParseListen :: MVar MinerState -> IO()
startParseListen stateRef = do
    putStrLn "Do you want to start listening? Yes/No"
    byteInput <- prompt "answer> "
    let input = C8.unpack byteInput
    case checkUserResponse input of
        Accepted -> accept
        Reject -> reject
        WrongResponce -> do
            putStrLn "ERROR: unrecognized command"
            startParseListen stateRef
    where 
        accept = do
            ip <- prompt "Enter your ip:"
            port <- prompt "Enter your port:"
            setupServer ip port stateRef
        reject = return ()