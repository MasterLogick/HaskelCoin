module HelpCommand where

import MinerState

printHelp :: Handler
printHelp _ = do
    putStrLn "exit                                              - exit from program"
    putStrLn "build                                             - build new block"
    putStrLn "show                                              - print chain of blocks"
    putStrLn "commit [senderHash] [recieverHash] [amountMoney]  - create transaction"
    putStrLn "connect [ip] [port]                               - connect to server at specified ip and port (WIP)"
    putStrLn "balance [userHash]                                - print user's balance"
    putStrLn "id                                                - print user's id"
    putStrLn "generate                                          - generate & print new key pair"
    putStrLn "key                                               - print current user's key pair"
    putStrLn "start server [ip] [port]                          - start server at specified ip and port (WIP)"