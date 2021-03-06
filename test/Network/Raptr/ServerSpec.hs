{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Network.Raptr.ServerSpec where

import           Control.Concurrent.MVar
import           Control.Concurrent.Queue
import           Control.Exception
import           Control.Monad
import           Data.Binary
import           Network.Raptr.Raptr
import           Network.Raptr.TestUtils
import           Network.URI
import           Network.Wai              (Application)
import           System.Directory         (removePathForcibly)
import           System.IO
import           System.Posix.Temp
import           Test.Hspec
import           Test.Hspec.Wai
import           Test.Hspec.Wai.Matcher

app :: FilePath -> IO Application
app logFile = do
  nodeLog <- openLog logFile
  node <- newNode Nothing defaultRaftConfig (Client emptyNodes) nodeLog
  return $ server node


startStopServer = bracket startServer stopServer
  where
    startServer = do
      (logfile, hdl) <- mkstemp "test-log"
      hClose hdl
      theApp <- app logfile
      s <- start defaultConfig theApp
      pure (logfile, s)
    stopServer (logFile, s) = do
      stop s
      removePathForcibly logFile

clientSpec :: Spec
clientSpec = around startStopServer $ do

  it "can send message from client to server" $ \ (_, srv) -> do
    let p = raptrPort srv
        Just uri = parseURI $ "http://localhost:" ++ show p ++"/raptr/bar"
        msg :: Message Value = MRequestVote $ RequestVote term0 "foo" index0 term0
    sendClient msg uri -- expect no exception

serverSpec :: Spec
serverSpec = with (app "/dev/null") $ do

  let msg :: Message Value = MRequestVote $ RequestVote term0 "foo" index0 term0

  it "on POST /raptr/foo it enqueues event and returns it" $ do
    let ev = EMessage "foo" msg
    post "/raptr/foo" (encode msg) `shouldRespondWith` ResponseMatcher { matchStatus = 200
                                                                       , matchHeaders = ["Content-Type" <:> "application/octet-stream"]
                                                                       , matchBody = bodyEquals (encode ev) }

  it "on POST /raptr/foo it returns 503 if queue is full" $ do
    replicateM 10 $ post "/raptr/foo" (encode msg)

    post "/raptr/foo" (encode msg) `shouldRespondWith` 503
