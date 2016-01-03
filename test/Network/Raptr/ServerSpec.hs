{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Network.Raptr.ServerSpec where

import           Control.Concurrent.MVar
import           Control.Concurrent.Queue
import           Control.Exception
import           Control.Monad
import           Data.Binary
import           Network.Raptr.Raptr
import           Network.URI
import           Network.Wai              (Application)
import           Test.Hspec
import           Test.Hspec.Wai

app :: IO Application
app = do
  q <- newQueueIO 10
  mvar <- newMVar q
  return $ server mvar

startStopServer action = bracket
                         (app >>= start defaultConfig)
                         stop
                         action
clientSpec :: Spec
clientSpec = around startStopServer $ do

  it "can send message from client to server" $ \ srv -> do
    let p = raptrPort srv
        Just uri = parseURI $ "http://localhost:" ++ show p ++"/raptr/bar"
        client = NodeClient "foo" uri
        msg :: Message Value = MRequestVote $ RequestVote term0 "foo" index0 term0
    sendClient msg client -- expect no exception

serverSpec :: Spec
serverSpec = with app $ do

  let msg :: Message Value = MRequestVote $ RequestVote term0 "foo" index0 term0

  it "on POST /raptr/foo it enqueues event and returns it" $ do
    let ev = EMessage "foo" msg
    post "/raptr/foo" (encode msg) `shouldRespondWith` ResponseMatcher { matchStatus = 200
                                                                       , matchHeaders = ["Content-Type" <:> "application/octet-stream"]
                                                                       , matchBody = Just $ encode ev }

  it "on POST /raptr/foo it returns 503 if queue is full" $ do
    replicateM 10 $ post "/raptr/foo" (encode msg)

    post "/raptr/foo" (encode msg) `shouldRespondWith` 503
