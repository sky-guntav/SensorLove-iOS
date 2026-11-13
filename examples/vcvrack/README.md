# VCV Rack

A patch you build in a couple of minutes, for VCV Rack 2: trowaSoft's free [cvOSCcv](https://library.vcvrack.com/trowaSoft/cvOSCcv) takes SensorLove's OSC on UDP port 9000 and turns ACCEL's x and y into voltages. x goes through a slew limiter, which calms the jitter, and a quantizer, which snaps it to a scale, into a VCO's pitch. y opens a VCA. Roll the phone left and right for the notes, dip its top edge away from you to make it louder. Flat in your hand it is silent.

There is no .vcv file to download yet: see Tried.

## Build it

1. Add trowaSoft to your Rack from the [VCV Library](https://library.vcvrack.com/trowaSoft/cvOSCcv) (free), then add these modules: **cvOSCcv** (trowaSoft), **Process**, a second **Process**, **Quantizer**, **VCO**, **VCA** (all VCV Fundamental) and **Audio 2** (Core).
2. On cvOSCcv, click CONFIG. Set In Port to `9000`, leave Out Port as it is, Namespace empty, tick Auto Con and click ENABLE.
3. Still in CONFIG, under OSC -> CV, type `/sensorlove/accel/x` as channel 1's address and `/sensorlove/accel/y` as channel 2's. Values arrive as they are, about -1 to 1 V.
4. Click channel 2's ADV: tick Convert Values and Clip Values, leave OSC VALUE at 0 to 1 and set CONTROL VOLTAGE to 0 to 10. Save, then click CONFIG again to close it.
5. Patch x: cvOSCcv's channel 1 VAL output to the first Process's IN, its SLEW output to Quantizer's IN, Quantizer's OUT to VCO's V/OCT.
6. Patch y: cvOSCcv's channel 2 VAL output to the second Process's IN, its SLEW output to VCA's CV.
7. Patch the sound: VCO's SIN to VCA's IN, VCA's OUT to both inputs of Audio 2. Pick your sound card on Audio 2.
8. Turn both Process modules' SLEW knobs up a little, to about a tenth of a second. On Quantizer, click its keys so only C, D, E, G and A stay lit: a pentatonic scale, hard to play a wrong note in.
9. Save the patch (File › Save as), `sensorlove.vcv`.

Hover a port in Rack to read its name.

## Play

1. In SensorLove, add your computer in DESTINATIONS (IP, PORT 9000) and switch it on. Start ACCEL. A SEND RATE of 30 or 60 is plenty.
2. Hold the phone flat, screen up. Dip its top edge away from you: the note fades in. Roll it left and right: the note steps up and down the scale, an octave each way.

cvOSCcv matches each address in full, so another value is another channel: `/sensorlove/gyro/x`, for example. A destination's PREFIX goes into the address too: `/sensorlove/phone1/accel/x`. Addresses: [Sensors](../../docs/sensors.md).

## Tried

Not yet in Rack, and not yet with a phone. Written from cvOSCcv 2.0.9's source code (how its CONFIG screen saves, how it matches an address, its Convert and Clip, which need each Min below its Max: so y opens the VCA when the top dips away, never when it stands up) and from the list of modules in VCV Fundamental 2.6.4. trowaSoft is not installed on the computer this was written on, so no .vcv file could be saved and checked: once someone builds it in Rack, the file goes here.
