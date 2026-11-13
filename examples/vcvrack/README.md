# VCV Rack

`sensorlove.vcv`, for VCV Rack 2: trowaSoft's free [cvOSCcv](https://library.vcvrack.com/trowaSoft/cvOSCcv) takes SensorLove's OSC on UDP port 9000 and turns ACCEL's x and y into voltages. x goes through a slew limiter, which calms the jitter, and a quantizer, which snaps it to a pentatonic scale, into a VCO's pitch. y opens a VCA. Roll the phone left and right for the notes, dip its top edge away from you to make it louder. Flat in your hand it is silent.

## Play

1. Add trowaSoft to your Rack from the [VCV Library](https://library.vcvrack.com/trowaSoft/cvOSCcv) (free). The other modules come with Rack.
2. Open `sensorlove.vcv` (File › Open). cvOSCcv starts listening on port 9000 by itself. On AUDIO, pick your sound card.
3. In SensorLove, add your computer in DESTINATIONS (IP, PORT 9000) and switch it on. Start ACCEL. The IP is your computer's on the network, not the 127.0.0.1 in cvOSCcv's CONFIG: that one is where cvOSCcv sends.
4. Hold the phone flat, screen up. Dip its top edge away from you: the note fades in. Roll it left and right: the note steps up and down the scale, an octave each way.

## Inside

- **cvOSCcv:** click CONFIG to see it. Under OSC -> CV, channel 1 is `/sensorlove/accel/x`, as it comes (about -1 to 1 V). Channel 2 is `/sensorlove/accel/y`, its ADV set to Convert and Clip: 0 to 1 becomes 0 to 10 V, so it opens the VCA only when the top dips away (cvOSCcv needs each Min below its Max, so it cannot turn a range around).
- **Process, Quantizer, VCO:** the first Process slews x at 500 ms a volt, the Quantizer keeps C, D, E, G and A, the VCO plays it from middle C.
- **Process, VCA:** the second Process slews y at 50 ms a volt, so the volume moves without clicks.

cvOSCcv matches each address in full, so another value is another channel: type `/sensorlove/gyro/x` as an address in CONFIG. A destination's PREFIX goes into the address too: `/sensorlove/phone1/accel/x`. Addresses: [Sensors](../../docs/sensors.md).

## Tried

VCV Rack Free 2.6.6 on Windows with trowaSoft 2.0.9 and Fundamental 2.6.4, run without its window, with packets shaped like the app's sent from the same computer. The patch opened and cvOSCcv listened on 9000 by itself. A copy of it sent the quantizer's output and the VCA's voltage back over OSC: x 0.5 played G (0.583 V), 0.95 the C above (1 V), -0.3 the G below (the quantizer rounds 8 semitones down), each in about a quarter to half a second; y 0.5 gave 4.9 V, 1.2 gave 10 V, -0.5 gave 0 V. Then the app's full stream for 20 seconds, 163 addresses 120 times a second with a text among them: Rack kept running and the notes kept following. Then with a phone, on 14 November 2026: it played, the note and the volume following the phone. Not yet on macOS or Linux.
