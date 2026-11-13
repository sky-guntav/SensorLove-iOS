# Processing

`sensorlove/sensorlove.pde`: a box that turns as your phone does (ATTITUDE), with the oscP5 library.

## Play

1. In Processing, install oscP5: Sketch › Import Library › Manage Libraries, search oscP5.
2. Open `sensorlove/sensorlove.pde` and press Run.
3. In SensorLove, add your computer in DESTINATIONS (IP, PORT 9000) and switch it on. Start ATTITUDE.
4. Lay the phone flat with its top toward the screen. Tap the monitor for SCOPE, then ZERO under it: the box now faces the way your phone does.

oscP5 calls `oscEvent()` once for every message, also for each one inside SensorLove's bundles.

## Tried

Not yet: not run in Processing, and the way the box turns is worked out from iOS's angles, not checked against a phone.
