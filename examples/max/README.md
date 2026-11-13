# Max

`sensorlove.maxpat`: `[udpreceive 9000]` takes SensorLove's OSC, `[route]` picks ACCEL's x and y, and a sine wave plays. Tilt the phone left and right for the pitch, hold it up to make it louder. Flat on the table it is silent.

## Play

1. Open `sensorlove.maxpat` in Max.
2. In SensorLove, add your computer in DESTINATIONS (IP, PORT 9000) and switch it on. Start ACCEL.
3. Click the speaker to turn audio on, pick up the phone and tilt it.

Each OSC message comes out of `[udpreceive]` starting with its address, `/sensorlove/accel/x 0.12`, so `[route]` can pick any address from [Sensors](../../docs/sensors.md).

## Tried

Not yet: written from Max's reference and checked as a file (every patch cord joins boxes that exist), but not opened in Max.
