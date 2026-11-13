# OSC

## Addresses

Every value has its own address, `/sensorlove/<sensor>/<value>`: `/sensorlove/accel/x`, `/sensorlove/face/jawOpen`. Each message carries one 32-bit float. Two carry text, as an OSC string: LOCATION's street address (`/sensorlove/location/address`) and WEATHER's sky in words (`/sensorlove/weather/text`). [Sensors](sensors.md) lists them all.

A destination's PREFIX goes right after the root, so several phones can share one computer: with the PREFIX `phone1`, `/sensorlove/phone1/accel/x`.

## How they travel

- **UDP:** each send is an OSC bundle with the time tag 1, "now". A bundle stays under 1400 bytes, so it never breaks up on the way; a big sensor such as FACE goes out in several.
- **TCP:** the same bundles, framed with SLIP (OSC 1.1).
- **JSON:** instead of OSC, one JSON object per send, on its own line, over UDP or TCP. Each address under the root is a path in it, `{"accel": {"x": 0.01, "y": -0.98, "z": 0.05}}`, with `"timestamp"` (Unix time in seconds) and `"prefix"` (if set) beside it. A JSON line carries every running value, and one goes out whenever something changed.

## When they are sent

- SEND RATE sets how often SensorLove reads the sensors: 15, 30, 60 or 120 times a second. FACE and HAND send at CAMERA's rate, 15, 30 or 60, never above SEND RATE.
- Only what changes goes out: a new value is sent, sent once more 0.2 seconds later in case a packet was lost, then its address stays quiet until it changes again.
- TIME, WEATHER and the two texts are sent again every 5 seconds, so a patch opened later gets them too.
- Switching a destination off and on sends everything once.
- A hand out of view sends only its ACTIVE, 0; a face that is lost, only DETECTED, 0.
