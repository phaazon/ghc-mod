{-# LANGUAGE CPP #-}
module Language.Haskell.GhcMod.Utils where

import Control.Arrow
import Data.Char
import Language.Haskell.GhcMod.Error
import MonadUtils (MonadIO, liftIO)
import System.Directory (getCurrentDirectory, setCurrentDirectory, doesFileExist)
import System.Exit (ExitCode(..))
import System.Process (readProcessWithExitCode)
import System.Directory (getTemporaryDirectory)
import System.FilePath (splitDrive, pathSeparators)
import System.IO.Temp (createTempDirectory)
#ifndef SPEC
import Control.Applicative ((<$>))
import System.Environment
import System.FilePath ((</>), takeDirectory)
#endif

-- dropWhileEnd is not provided prior to base 4.5.0.0.
dropWhileEnd :: (a -> Bool) -> [a] -> [a]
dropWhileEnd p = foldr (\x xs -> if p x && null xs then [] else x : xs) []

extractParens :: String -> String
extractParens str = extractParens' str 0
 where
   extractParens' :: String -> Int -> String
   extractParens' [] _ = []
   extractParens' (s:ss) level
       | s `elem` "([{" = s : extractParens' ss (level+1)
       | level == 0 = extractParens' ss 0
       | s `elem` "}])" && level == 1 = [s]
       | s `elem` "}])" = s : extractParens' ss (level-1)
       | otherwise = s : extractParens' ss level

readProcess' :: (MonadIO m, MonadError GhcModError m)
             => String
             -> [String]
             -> m String
readProcess' cmd opts = do
  (rv,output,err) <- liftIO (readProcessWithExitCode cmd opts "")
      `modifyError'` GMEProcess ([cmd] ++ opts)
  case rv of
    ExitFailure val -> do
        throwError $ GMEProcess ([cmd] ++ opts) $ strMsg $
          cmd ++ " " ++ unwords opts ++ " (exit " ++ show val ++ ")"
              ++ "\n" ++ err
    ExitSuccess ->
        return output

withDirectory_ :: (MonadIO m, ExceptionMonad m) => FilePath -> m a -> m a
withDirectory_ dir action =
    gbracket (liftIO getCurrentDirectory) (liftIO . setCurrentDirectory)
                (\_ -> liftIO (setCurrentDirectory dir) >> action)

uniqTempDirName :: FilePath -> FilePath
uniqTempDirName dir =
    uncurry (++)
        $ map escapeDriveChar *** map escapePathChar
        $ splitDrive dir
 where
    escapeDriveChar c
        | isAlphaNum c = c
        | otherwise = '-'

    escapePathChar c
        | c `elem` pathSeparators = '-'
        | otherwise = c

newTempDir :: FilePath -> IO FilePath
newTempDir dir =
    flip createTempDirectory (uniqTempDirName dir) =<< getTemporaryDirectory

mightExist :: FilePath -> IO (Maybe FilePath)
mightExist f = do
  exists <- doesFileExist f
  return $ if exists then (Just f) else (Nothing)

-- | Returns the path to the currently running ghc-mod executable. With ghc<7.6
-- this is a guess but >=7.6 uses 'getExecutablePath'.
ghcModExecutable :: IO FilePath
#ifndef SPEC
ghcModExecutable = do
    dir <- getExecutablePath'
    return $ dir </> "ghc-mod"
 where
    getExecutablePath' :: IO FilePath
# if __GLASGOW_HASKELL__ >= 706
    getExecutablePath' = takeDirectory <$> getExecutablePath
# else
    getExecutablePath' = return ""
# endif
#else
ghcModExecutable = return "dist/build/ghc-mod/ghc-mod"
#endif
