# TouchDesigner

`sensorlove.py` builds a small network that takes SensorLove's OSC: an OSC In CHOP on UDP port 9000, a Select CHOP for ATTITUDE and one for FACE TRACK's jawOpen, and a render where the phone on screen turns as yours does and the ball grows as you open your mouth.

## Build it

1. Open TouchDesigner and start a new project (File › New).
2. Open the Textport: Dialogs › Textport and DATs, or Alt+Shift+T.
3. Copy all of `sensorlove.py`, paste it into the Textport and press Enter. `/project1/sensorlove` appears, its tile showing the picture.

Or paste the script into a Text DAT and choose Run Script from its right-click menu.

## Play

1. In SensorLove, add your computer in DESTINATIONS (IP, PORT 9000) and switch it on. Start ATTITUDE and FACE TRACK.
2. Lay the phone flat with its top toward the screen. Tap the monitor for SCOPE, then ZERO under it: the phone on screen now faces the way yours does.
3. Open your mouth: the ball grows.

## Save it

- **The project:** File › Save As, `sensorlove.toe`.
- **The component**, to drop into your own projects: right-click `sensorlove`, Save Component .tox, `sensorlove.tox`. Drag the .tox into any network.

## Inside

Double-click `sensorlove`. Every address comes in as a channel named like it, without the first slash: `/sensorlove/accel/x` is `sensorlove/accel/x`. For another sensor, add a Select CHOP with CHOP `oscin1` and Channel Names `sensorlove/accel/*`. The two texts, LOCATION's address and WEATHER's sky, need an OSC In DAT, which can share port 9000 with the CHOP. Addresses: [Sensors](../../docs/sensors.md).

## Tried

TouchDesigner 2025.32460 on Windows, with packets shaped like the app's, sent from the same computer. The script built the network without errors both from a Text DAT and fed line by line to a Python console, standing in for the Textport (the Textport itself was not tried). The channels arrived, the phone turned and the ball grew. The phone turns in iOS's angle order, checked by numbers, not yet with a phone. Not tried in TouchDesigner 2023.
