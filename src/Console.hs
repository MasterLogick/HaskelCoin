module Console where

import MinerState
import TBlock
import Commiter
import Sender

import Text.Read (readMaybe)

data Command
    = Exit_
    | Commit Transaction
    | BuildAndSend 

makeProgram :: a -> IO a
makeProgram = return

type Handler = MinerState -> (String, Maybe MinerState)


handleExit_ :: Handler
handleExit_ _ = ("Bye!", Nothing)

handleBuild :: Handler
handleBuild ms = ("Block is built.", Just (buildAndSendToNet ms))

handleCommit :: Transaction -> Handler
handleCommit t ms = ("Transaction is added to pending block.", Just (commitTransaction t ms))

handleCommand :: Command -> Handler
handleCommand command = case command of
  Exit_ -> handleExit_
  BuildAndSend -> handleBuild
  Commit trans -> handleCommit trans
        
-- | Parse a task manager bot command.
--
-- >>> parseCommand "/done 3"
-- Just (RemoveTask 3)
-- >>> parseCommand "/done 1 2 3"
-- Nothing
parseCommand :: String -> Maybe Command
parseCommand input =
    case input of
        "exit" -> Just Exit_
        "build" -> Just BuildAndSend
        _ ->
            case words input of
                ["commit", id_sender, id_reciver, amt] -> 
                    case readMaybe amt of
                        Nothing -> Nothing
                        Just amount -> 
                            case readMaybe id_sender of
                                Nothing -> Nothing
                                Just sender ->
                                    case readMaybe id_reciver of
                                        Nothing -> Nothing
                                        Just reciver -> Just (Commit (Transaction sender reciver amount))
                _ -> Nothing

-- | Init state of the system
initMinerState :: MinerState
initMinerState = MinerState [] []

-- | Default entry point.
run :: IO ()
run = runWith initMinerState parseCommand handleCommand

runWith
    :: state
    -> (String -> Maybe command)
    -> (command -> state -> (String, Maybe state))
    -> IO () 
runWith tasks parse handle = do
    putStr "command> "
    input <- getLine
    case parse input of
        Nothing -> do
            putStrLn "ERROR: unrecognized command"
            runWith tasks parse handle
        Just command' -> do
            case handle command' tasks of
                (feedback, newTasks) -> do
                    putStrLn feedback
                    case newTasks of
                        Nothing -> return ()
                        Just newTasks' -> do
                            runWith newTasks' parse handle
