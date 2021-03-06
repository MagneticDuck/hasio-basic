-- | Definition of an application, constructable from pure semantics, which
-- holds the functionality we can expect from a casio BASIC program and can
-- be executed via an ncurses interface.
module Hasio.Application
    ( module Hasio.Application.Key
    , AppEvent(..)
    , AppDisplay(..), displayFromStrings
    , Application(..)
    , runApplication
    ) where

import Hasio.Application.Key

import Data.List
import UI.NCurses
import Control.Monad
import Control.Concurrent
import Control.Monad.IO.Class

data AppEvent =
    TickEvent Float
    | KeyEvent AppKey

newtype AppDisplay = AppDisplay { stringsFromAppDisplay :: [String] }

displayFromStrings :: [String] -> AppDisplay
displayFromStrings strings =
    AppDisplay . take 7 $ fmap normalString strings ++ repeat ""
    where normalString = take 21 . (++ repeat ' ')

data Application s = Application
    { initialApp :: s
    , displayApp :: s -> AppDisplay
    , incrementApp :: AppEvent -> s -> Maybe s }

updateFromDisplay :: AppDisplay -> Update ()
updateFromDisplay (AppDisplay strings) =
    foldr1 (>>) [ myBorder, drawContents, moveCursor 0 0 ]
    where
        drawContents =
            forM_ [0..6] (\i ->
                moveCursor (i + 1) 1 >>
                    drawString (strings !! fromIntegral i))
        myBorder = mapM_ drawEdge [0, 7] >> mapM_ drawDelim [1..6]
        drawEdge y = moveCursor y 0 >> drawString (replicate 23 '-')
        drawDelim y = moveCursor y 0 >>
            drawString (concat ["|", replicate 21 ' ', "|"])

runApplication :: Application s -> IO ()
runApplication app = runCurses $ do
    setEcho False
    defaultWindow >>= appLoop app (initialApp app)

appLoop :: Application s -> s -> Window -> Curses ()
appLoop app state window = do
    updateWindow window . updateFromDisplay $ displayApp app state
    render
    event <- getEvent window (Just 0)
    let
        mutateEvent = case event of
            Nothing -> return
            Just event ->
                case keyFromEvent event of
                    Just appKey -> incrementApp app (KeyEvent appKey)
                    _ -> return
        mutateDelay = incrementApp app (TickEvent 15)
    liftIO $ threadDelay 15
    forM_ (mutateEvent =<< mutateDelay state) $
        flip (appLoop app) window

handleEvents :: Window -> (Event -> Bool) -> Curses ()
handleEvents w p = loop where
    loop = do
        ev <- getEvent w Nothing
        case ev of
            Nothing -> loop
            Just ev' -> unless (p ev') loop
