# Getting started

SensorLove sends your iPhone's sensors to the apps on your computer, over OSC. The phone and the computer only need to be on the same Wi-Fi.

## What you need

- SensorLove, from the [App Store](https://apps.apple.com/app/sensorlove/id6760937599).
- An iPhone with iOS 18.2 or later. FACE TRACK needs an iPhone with Face ID.
- A computer on the same network with anything that takes OSC, or an OSC monitor such as Protokol to watch the values arrive.

## Try it on the phone

1. Tap a sensor card, ACCEL for example: it starts, and its toy plays on the monitor at the top.
2. Tap the card again for its values.
3. Its red LED switches it off.

## Send to your computer

1. Find your computer's IP address on the Wi-Fi: on a Mac in System Settings › Wi-Fi › Details, on Windows with `ipconfig`.
2. In SensorLove, open DESTINATIONS and tap + ADD. Type the address in IP. PORT is 9000.
3. Switch the destination on with its LED. The first time, iOS asks for Local Network access: allow it.
4. On the computer, take OSC in on UDP port 9000. The values arrive at addresses like `/sensorlove/accel/x`.

Apps that announce themselves on the network show up in DESTINATIONS under FOUND ON THIS NETWORK, with their address and port. Tap ADD and skip steps 1 and 2.

[Sensors](sensors.md) lists every sensor and its addresses. VIDEO and DEPTH send the camera and its depth as video, over NDI: [NDI](ndi.md).

Ready-made patches and scripts that receive them are in [examples](../examples/README.md).

## Away from the studio

- **No shared Wi-Fi:** the phone can make the network. Turn on its Personal Hotspot and join it from the computer, over Wi-Fi or with a USB cable (the cable is the steadiest). The computer's address on it usually starts with 172.20.10: type that in IP.
- **Far apart:** a free private network such as Tailscale or ZeroTier puts the phone and the computer on one network wherever they are, even on mobile data. Install it on both and type the computer's address in it. No router settings needed.

## More to know

- **SEND RATE:** 15, 30, 60 or 120 times a second, 60 to start with. CAMERA sets how often FACE and HAND send: 15, 30 or 60, never more than the rate.
- **Several phones, one computer:** give each phone's destination its own PREFIX, such as `phone1`. Its addresses become `/sensorlove/phone1/accel/x`.
- **ZERO and SMOOTH:** tap a motion sensor's monitor for SCOPE, a trace for every value. Under it, ZERO takes the phone's position as 0 and SMOOTH calms the values (OFF, LO, HI). What you see is what is sent.
- **REC** (in CONSOLE): writes every running sensor to a CSV file, one row per send. Your takes are in the Files app, in SensorLove; SAVE CSV shares one.
- **IN BACKGROUND** (in SETTINGS): keeps sending while another app is open or the phone is locked. FACE, HAND and PROX pause there: iOS stops the camera and the sensor by the earpiece.
- **PRESETS** (in SETTINGS): setups to come back to: which sensors run, the cards' order, the rate and the destinations.
- **Permissions:** SensorLove asks only when a sensor needs one. SETTINGS › PERMISSIONS shows them all; iOS Settings › SensorLove changes them.
