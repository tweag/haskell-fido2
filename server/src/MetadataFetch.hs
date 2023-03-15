{-# LANGUAGE ScopedTypeVariables #-}

module MetadataFetch
  ( continuousFetch,
    fetchRegistry,
    registryFromJsonFile,
  )
where

import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Concurrent.STM (TVar, atomically, modifyTVar)
import Control.Monad (forever)
import qualified Crypto.WebAuthn as WA
import qualified Crypto.WebAuthn.Metadata.Service.Decode as WAMeta
import qualified Crypto.WebAuthn.Metadata.Service.Processing as WAMeta
import qualified Crypto.WebAuthn.Metadata.Service.WebIDL as WAMeta
import Data.Aeson (eitherDecodeFileStrict)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.List (intercalate)
import qualified Data.List.NonEmpty as NE
import Data.Maybe (mapMaybe)
import qualified Data.Text as Text
import Data.These (These (That, These, This))
import Network.HTTP.Client (Manager, httpLbs, responseBody)
import Network.HTTP.Client.TLS (newTlsManager)
import System.Hourglass (dateCurrent)

-- | Reads metadata entries from a JSON list. See extra-entries.json for an example
registryFromJsonFile :: FilePath -> IO WA.MetadataServiceRegistry
registryFromJsonFile path = do
  values <-
    eitherDecodeFileStrict path >>= \case
      Left err -> fail $ "Failed to decode JSON file " <> path <> " into a list: " <> err
      Right (values :: [WAMeta.MetadataBLOBPayloadEntry]) -> pure values
  entries <- case sequence (mapMaybe WAMeta.decodeMetadataEntry values) of
    Left err -> fail $ "Failed to decode an metadata entry from file " <> path <> ": " <> Text.unpack err
    Right decodedEntries -> pure $ foldMap NE.toList decodedEntries
  pure $ WAMeta.createMetadataRegistry entries

-- | Continuously fetches the FIDO Metadata and updates a 'TVar' with the decoded results
-- New entries are added to the TVar, entries are not removed if no longer present in the Metadata.
continuousFetch :: TVar WA.MetadataServiceRegistry -> IO ThreadId
continuousFetch var = do
  manager <- newTlsManager
  registry <- fetchRegistry manager
  atomically $ modifyTVar var (<> registry)
  threadId <- forkIO $ forever $ sleepThenUpdate manager var
  pure threadId
  where
    -- 1 hour delay for testing purposes. In reality this only needs to happen
    -- perhaps once a month, see also the 'Service.mpNextUpdate' field
    delay :: Int
    delay = 60 * 60 * 1000 * 1000

    sleepThenUpdate :: Manager -> TVar WA.MetadataServiceRegistry -> IO ()
    sleepThenUpdate manager var = do
      putStrLn $ "Sleeping for " <> show (delay `div` (1000 * 1000)) <> " seconds"
      threadDelay delay
      registry <- fetchRegistry manager
      atomically $ modifyTVar var (<> registry)

-- | Fetches the fidoalliance provided metadata blob. The latest version of the
-- blob is always available at @https://mds.fidoalliance.org@.
fetchBlob :: Manager -> IO BS.ByteString
fetchBlob manager = do
  putStrLn "Fetching Metadata"
  response <- httpLbs "https://mds.fidoalliance.org" manager
  pure $ LBS.toStrict $ responseBody response

-- | Fetch the metadata blob and decode it, used in the `continuousFetch`
-- function of this module.
fetchRegistry :: Manager -> IO WA.MetadataServiceRegistry
fetchRegistry manager = do
  blobBytes <- fetchBlob manager
  now <- dateCurrent
  case WA.metadataBlobToRegistry blobBytes now of
    Left err -> error $ Text.unpack err
    Right (This err) -> error $ "Unexpected MDS parsing errors: " <> intercalate "," (Text.unpack <$> NE.toList err)
    Right (These err res) -> putStrLn ("Unexpected MDS parsing errors: " <> intercalate "," (Text.unpack <$> NE.toList err)) >> pure res
    Right (That res) -> pure res
