# Changelog

## 1.0 · 2026-11-12

The first release.

- 19 sensors, each with its own live monitor: ATTITUDE, QUAT, GRAVITY, GYRO, ACCEL, USER ACCEL, LOCATION, MAGNET, BARO, WEATHER, TOUCH, MIC, PROX, BATTERY, TIME, FACE TRACK and HAND TRACK send OSC, each with its toy; VIDEO and DEPTH send NDI®.
- VIDEO and DEPTH: the camera and its depth as NDI® sources. DEPTH is 16-bit and metric (LiDAR or TrueDepth), at VIDEO's size with its edges on the picture's (a guided filter on the GPU), with DETAIL AI for edges, hair and folds finer than the sensor (Depth Anything on the Neural Engine, tied to the sensor every frame), coded by 1/distance so near things and faces show their relief (FAR's FACE and EQ give a face all the greys; SMOOTH on or off), and cleaned on the phone (edges without stray points, calm without lagging); every frame carries its lens, its time and, on the back camera, where the phone is. With the people cut out (MATTE) and the sound, if you like.
- Every value on its own OSC address, over UDP or TCP, or as JSON. As many destinations as you like, each with its own PREFIX.
- DESTINATIONS finds the OSC apps that announce themselves on your network: one tap adds them, address and port filled in.
- SEND RATE from 15 to 120 a second; values that do not change stay quiet.
- REC writes CSV files: a column for every value, named after its address.
- IN BACKGROUND keeps sending with the phone locked. PRESETS keep your setups.
- A quick tour at the first launch: five stops, each lighting one part of the app while the rest waits, the last a card to start your first sensor. SKIP ends it; SETTINGS › GUIDE plays it again.
- Free, all of it. A paper pot stands on HELLO's floor (and the tip jar in ABOUT): a tip, through Apple, helps its maker keep SensorLove going and unlocks nothing. The first tip plants the pot's love tree in the ground, the second makes it a big tree, the ones after it bring fruit, each with a little celebration.
