# SensorLove Privacy Policy

Last updated: 2 November 2026

SensorLove is a free community tool. The app has no accounts, no ads, no analytics and no tracking: the people who make it do not collect, receive, store, share or sell any data about you through it. The website counts its visits with Google Analytics (see This website, below).

## What SensorLove reads, and where it goes

SensorLove turns your iPhone's sensors into live data for your own creative tools (TouchDesigner, Max/MSP, Unreal and others). It reads a sensor only while you switch it on, and it sends the readings only to the destinations you add yourself: devices on your network, or addresses you type in. Nothing goes to us.

- **Motion, barometer, touch, battery, proximity:** numbers, sent to your destinations.
- **Microphone:** MIC works out only how loud it is. With VIDEO's SOUND on, the sound goes out live with VIDEO's picture (below). Nothing is recorded or kept.
- **Camera (FACE, HAND):** each frame is read on your iPhone (Apple's ARKit and Vision) to find a face and hands; only the numbers that come out are sent. The REAL view shows the camera's picture on your screen only. For FACE, see Face data, below.
- **Camera (VIDEO, DEPTH):** while you switch them on, the camera's picture and its depth go out live as NDI sources on your local network, to the apps there that open them, such as TouchDesigner or OBS. Nothing is recorded or kept, and nothing goes to us.
- **Location:** sent to your destinations while LOCATION is on. To show your address and a map, SensorLove asks Apple's map services (Apple's privacy policy applies to them).
- **Weather (WEATHER):** to get the weather where you are, SensorLove sends your approximate location (rounded to about 1 km) to Open-Meteo (open-meteo.com), only while WEATHER is on. Open-Meteo keeps its server logs, which may hold that location and your IP address, for up to 90 days (open-meteo.com/en/terms).
- **Recordings (REC):** CSV files kept on your iPhone (Files app › SensorLove). They leave your phone only if you share them.
- **Settings and presets:** kept on your iPhone only.

## Face data (TrueDepth camera)

SensorLove uses the TrueDepth camera (through Apple's ARKit and AVFoundation) only while you switch on FACE, or DEPTH or MATTE on the front camera.

- **What it reads:** with FACE on, ARKit's numbers for your face, frame by frame: where your head is and how it is turned, where your eyes are and where they look, and ARKit's 52 expression values (such as jawOpen or eyeBlinkLeft). With DEPTH on the front camera, the TrueDepth camera's depth image: how far away each point is. With MATTE, which pixels are a person. The REAL view draws ARKit's face mesh over the camera picture, on your screen only.
- **Why:** only to send it, live, to the destinations you choose (your own computer or app), for your own work: to move visuals, sound or animation with your face. FACE's numbers go out as OSC; DEPTH goes out as an NDI source on your local network.
- **What it is not used for:** SensorLove does not use face data to identify you or anyone else, to unlock or sign in, for advertising or marketing, for analytics, or to build a profile, and it never sells it.
- **Who gets it:** only the destinations you add yourself. Nothing goes to us, the people who make SensorLove, or to any third party: SensorLove has no server that could receive it.
- **Where it is kept, and for how long:** nowhere. Each frame is read in your iPhone's memory and let go as soon as its numbers are sent; no camera picture, depth image or face mesh is saved. The one exception is your own choice: if you start REC while FACE is on, FACE's numbers (never pictures) are written to that recording's CSV file on your iPhone.
- **Deleting:** switch FACE, DEPTH and MATTE off and SensorLove stops reading the TrueDepth camera at once. Delete a recording in the Files app; deleting SensorLove deletes all of them. What reaches your own destinations is kept or deleted by your own software there.

## Tips

The tip jar uses Apple's in-app purchase. Apple takes the payment and handles your payment details: the people who make SensorLove never see them, and get only Apple's sales reports, which do not name you. A tip unlocks nothing. SensorLove counts your tips on your iPhone, to fill the jar. On the United States App Store the jar also links to GitHub Sponsors, which opens in Safari; GitHub's privacy statement applies there.

## In the background

When IN BACKGROUND is on, SensorLove keeps sending while you use another app or the phone is locked. To stay awake it plays silence: nothing is heard, and nothing is recorded (MIC, if it is on, only measures how loud it is).

## Permissions

iOS asks you before SensorLove can use the camera, the microphone, your location, motion & fitness and the local network. You can change each at any time in iOS Settings › SensorLove.

## Deleting

Deleting SensorLove removes everything it kept on your iPhone: settings, presets and recordings. Share the recordings you want to keep first.

## This website

sensor.love counts its visits with Google Analytics. It sets cookies (`_ga` and `_ga_…`) to tell one visit from another, and records the pages you open and how far you scroll them, the site that sent you here, how long you stay, the links you follow out, your browser and device, and roughly where you are (worked out from your IP address, which it does not keep). Its ad features are off. Google keeps these records for 14 months; [Google's privacy policy](https://policies.google.com/privacy) applies to them. If you would rather not be counted, use [Google's opt-out add-on](https://tools.google.com/dlpage/gaoptout) or a tracker blocker. Apart from Google Analytics, the site loads nothing from other sites.

Its SENSORLOVE EXPERIENCE can ask for your phone's motion and, in one game, your microphone: both are read in your browser while you play, and nothing is recorded, kept or sent. GitHub, which hosts it, logs visits, including IP addresses, for its own security; GitHub's privacy statement applies to those logs.

## Children

The app collects no information from anyone, children included. WEATHER sends an approximate location to Open-Meteo, and the website counts its visits with Google Analytics, as described above.

## Changes

If this policy changes, the new version is posted here with its date.

## Contact

Questions about privacy, or anything else: [hello@sensor.love](mailto:hello@sensor.love).
