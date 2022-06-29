module FilesMagic where 
    
import Control.Concurrent.MVar

import MinerState
import TBlock
import NetworkRules
import NetworkMagic

import Data.Binary
import qualified Data.ByteString.Lazy as LB
-- import System.Directory

import Control.Concurrent.MVar

type Path = String

loadBlocks :: Path -> Handler
loadBlocks filePath stateRef = do
    bytes <- LB.readFile filePath
    case decodeOrFail bytes of
        Left _ -> putStrLn "Something wrong!"
        Right (_, _, blocksData) -> modifyMVar_ stateRef (\minerState -> do
            let present = blocks minerState
            case mergeBranches blocksData present of
                Left merged -> do
                    putStrLn "Got new blocks from file"
                    propagateLastBlockToNet stateRef
                    return minerState{ blocks = merged }
                Right merged -> do
                    putStrLn "Local chain is better"
                    return minerState{ blocks = merged }
            )

writeBlocks :: Path -> Handler
writeBlocks filePath stateRef = do
    miner <- readMVar stateRef
    LB.writeFile filePath (encode (blocks miner))
    return ()