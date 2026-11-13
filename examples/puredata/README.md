# Pure Data

`sensorlove.pd`, for vanilla Pd: `[netreceive -u -b 9000]` takes the UDP packets, `[oscparse]` turns each OSC message into a list (`sensorlove accel x 0.12`), `[list trim]` and `[route]` pick ACCEL's x and y, and an `[osc~]` plays. Tilt the phone left and right for the pitch, hold it up to make it louder. Flat on the table it is silent.

## Play

1. Open `sensorlove.pd` in Pd.
2. In SensorLove, add your computer in DESTINATIONS (IP, PORT 9000) and switch it on. Start ACCEL.
3. Click `; pd dsp 1` to turn audio on, pick up the phone and tilt it.

`[oscparse]` opens SensorLove's bundles by itself. For another sensor, add a branch after `[route sensorlove]`: `[route gyro]`, then `[route x y z]`. Addresses: [Sensors](../../docs/sensors.md).

## Tried

Pd 0.57-0 on Windows, without its window or sound, with packets shaped like the app's sent from the same computer: the values reached `[route x y z]` and the pitch and volume came out right (x 0.25 gives 311.13 Hz, y -0.75 gives 0.15). Not yet heard, and not yet with a phone.
