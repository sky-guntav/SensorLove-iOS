# NDI

VIDEO and DEPTH send the camera and its depth as video on your network, as NDI® sources. NDI® is a registered trademark of Vizrt NDI AB; [ndi.video](https://ndi.video/) has its free tools, such as Studio Monitor for a first look.

## Turn them on

1. In SENSORS, tap VIDEO or DEPTH, next to FACE TRACK and HAND TRACK. The first time, iOS asks for the camera.
2. On the computer, open the source: an NDI In TOP in TouchDesigner, an NDI Source in OBS (with the DistroAV plugin); Resolume, vMix and others list it with their NDI sources. It is called `SENSORLOVE VIDEO` or `SENSORLOVE DEPTH`, after the phone's name on the network.
3. NDI ↗ on the monitor opens its settings: the camera (FRONT or BACK), VIDEO's SIZE, MATTE and SOUND, DEPTH's FAR and SMOOTH, and the sources' NAME. Give each phone its own NAME when you use several.

Nothing is worked on while no one watches: the source waits, ready, and the phone stays cool. SensorLove has to stay open on the screen, as iOS gives an app no camera in the background. DARK SCREEN turns the screen down to black while the sources go on; a tap wakes it.

## VIDEO

- 8-bit video at CAMERA's rate. SIZE: MAX (the default) is the camera's own picture: 4K (2160 × 3840) on its own, 1440 × 1920 with DEPTH on that side (the largest the depth cameras pair with), ARKit's largest with FACE or MATTE; or 1080 or 720 on its short side. It stands up the way the phone is held.
- Rec.709 colour. Standing up, a 1080 picture is taller than 1080 lines, which NDI reads as Rec.2020: SensorLove sends it so.
- MATTE puts the people in the alpha channel, straight (not premultiplied). In OBS, set the source's Latency to Normal or the alpha is dropped.
- SOUND sends the microphone with it.
- With DEPTH on, or MATTE on the back camera, it shares the camera's frames with DEPTH, 4:3; otherwise it is the camera's own 16:9 picture.

## DEPTH

- 16-bit grey at VIDEO's size, pixel for pixel (1440 × 1920 with SIZE at MAX), its edges on the picture's. Each depth frame comes with the camera's picture of the same moment, and on the GPU a guided filter (Apple's way for LiDAR) fits the depth in each small patch as a line of the picture's colours; at an edge that line decides where it falls, so an outline, hair and fingers sit where VIDEO shows them. Inside a surface the depth stays its own, so a shirt's pattern never turns into relief. Where the measured surfaces around a pixel are more than 6% apart it takes the nearest of them, so nothing hangs between a face and the wall. NDI compresses in 8 × 8 blocks; at this size their seams are far smaller than at the cameras' own. The sizes below are the cameras' own. Front camera: TrueDepth, 640 × 480, 30 times a second, filtered by iOS (smoothed, holes filled from the picture) and lined up with VIDEO; with FACE or MATTE on, ARKit has the camera: 640 × 360, 15 times a second, unfiltered, made bigger without the picture (long side 1920).
- Back camera (Pro iPhones): the LiDAR scanner through iOS's LiDAR depth camera, as the old SensorLove had it: 320 × 240, 30 times a second, filtered by iOS, lined up with VIDEO. With MATTE on, ARKit has the camera: its LiDAR depth as it measures it each frame (256 × 192), with where the phone is and how sure it is of each pixel: an unsure one weighs less in the guided filter, so it leaves no hole.
- DEPTH goes out as fast as its camera measures: TrueDepth and the LiDAR camera 30 times a second, ARKit's LiDAR (MATTE on the back) up to 60 with CAMERA 60.
- Cleaned on the phone, the way depth cameras clean theirs: a pixel at an edge goes to the side it is nearer, so nothing hangs between a face and the wall; small holes are filled from the side behind; inside a surface the noise is averaged. With MATTE on the back, ARKit's depth is also steadied over time: calm while nothing moves, and what moves is taken as it is, at once.
- Near is white and it fades to black at FAR, by 1/distance: near things get most of the greys, the way the depth cameras' own precision goes (it falls off with the distance squared). Black is also nothing measured, and anything beyond FAR.
- FAR's AUTO follows the scene: it opens out at once when something comes closer or goes further, and closes in slowly; small changes (breathing, the sensor's noise) do not move it, so the picture does not pump. FACE gives all of it to the nearest 40 cm: a face held up to the camera shows its relief, and the room behind goes black. EQ spreads the greys by how much of the picture is at each distance, the way Apple's TrueDepth sample shows depth (histogram equalization): a face, many pixels within a few centimetres, gets most of them; it is the most detail to see, eased so it does not flicker. Or pick a fixed range: from 20 cm to 1.5, 3 or 5 metres.
- SMOOTH (on unless you turn it off) is iOS's own depth filter: smoothed and its holes filled from the picture, cleaner but a frame later and with a trail behind fast motion. Off, each frame comes as the camera measured it: no trail, noisier (on the 14 Pro's TrueDepth about twice as noisy). On the back camera with MATTE on, SMOOTH steadies ARKit's depth over time instead, and what moves is taken at once.
- DETAIL (SENSOR unless you pick AI, in builds that carry the model): AI runs Depth Anything V2 Small (Apple's Core ML conversion, Apache-2.0) on the phone's Neural Engine. It reads the camera's picture and gives edges, hair, fingers and folds finer than the depth cameras can sample, but no distances. Every frame it is tied to the sensor's: a straight line between the two in 1/distance, fitted again without the fifth that disagrees most. The sensor's own shape is kept at large; the network adds only what lies below about a 64th of the frame. A frame where they do not fit (half the pixels more than 60% off) goes as SENSOR. The network runs beside DEPTH at its own pace (about 40 ms a picture on the 14 Pro): DEPTH keeps its rate, each frame taking the newest map, at most two frames old. The detail is the network's reading of the picture, not a measurement: a printed face can get relief.
- Each frame's metadata says its range, `near` and `far`: for any value v above 0, metres = 1 / (1/far + v × (1/near − 1/far)).
- NDI compresses it and keeps 11 of the 16 bits (measured in TouchDesigner, the same at every grey): about 1,750 steps from near to far, finest near. With FAR 5 m a step is 0.25 mm at 30 cm, 0.7 mm at 50 cm, 2.7 mm at 1 m and 11 mm at 2 m; AUTO and FACE are finer still. NDI's compression can still soften an edge by a pixel: for a point cloud, drop points where the depth jumps.
- Apps that take only 8 bits (OBS, Max's jit.ndi, Unity) get it as 8-bit grey: 220 steps.
- On the phone, DEPTH's card shows what goes out: REAL its greys; DITHER its shape, lit from the top left by its true slopes, in Atkinson's dots. In TouchDesigner a Normal Map TOP after the NDI In TOP shows the same shape (its Z Scale about 0.004).

## In TouchDesigner

1. NDI In TOP: pick the source; Input Pixel Format **Native**, Input Color Space **Passthrough**, Bandwidth **High**. Native keeps DEPTH's 16 bits.
2. Each frame's metadata: an Info DAT on the NDI In TOP shows it as XML. An XML DAT turns it into attributes, a DAT to CHOP into channels.
3. Metres: a GLSL TOP after it, Pixel Format 32-bit float, with the code below and uniforms `uNear` and `uFar` from the metadata (step 2). Nothing measured stays 0.
   With FAR EQ, the code is a table instead: `eq` holds 33 distances, and v between two of them is even in metres: s = (1 − v) × 32, then metres = eq[⌊s⌋] + (s − ⌊s⌋) × (eq[⌊s⌋+1] − eq[⌊s⌋]). In a GLSL TOP: put the 33 values in a uniform array (a CHOP of 33 samples), and do the same.
4. A point cloud: the Palette's depthProjection, with Focal Lengths fx / w and fy / w and Optical Center cx / w and cy / h, from the metadata. If it comes out upside down, use 1 − cy / h.

```glsl
uniform float uNear, uFar;
out vec4 fragColor;
void main() {
    float v = texelFetch(sTD2DInputs[0], ivec2(gl_FragCoord.xy), 0).r;   // the grey, 0 to 1
    float m = v > 0.0003 ? 1.0 / (1.0 / uFar + v * (1.0 / uNear - 1.0 / uFar)) : 0.0;
    fragColor = TDOutputSwizzle(vec4(m, m, m, 1.0));
}
```

## Each frame's metadata

Every frame of both sources carries one element:

```
<sensorlove v="3" source="DEPTH" frame="18342" t="5321.204118" w="256" h="192" fx="211.3" fy="211.3" cx="127.6" cy="96.1" near="0.62" far="3.4" code="(1/m-1/far)/(1/near-1/far)" px="0.12" py="1.43" pz="-0.37" qx="0.01" qy="0.7" qz="0.02" qw="0.71"/>
```

- `v`: the metadata's version. Version 3 codes by 1/distance; version 2 (near white) was even in metres; version 1 was white at FAR.
- `frame` counts that source's frames. `t` is the phone's clock in seconds, the same on VIDEO and DEPTH: pair their frames on it.
- `w`, `h`: the frame as sent. `fx`, `fy`, `cx`, `cy`: its lens, in its own pixels.
- `eq` (FAR EQ only, with `code="eq"`): the 33 distances, metres, nearest first, that the greys are spread between.
- `near`, `far`: DEPTH's range for this frame, in metres: white is `near` or closer, the darkest grey `far`. `code` is how a value is worked out from metres `m`.
- `px`, `py`, `pz`, `qx`, `qy`, `qz`, `qw`: where the phone is (metres) and how it is turned, x to the right of the picture, y up, looking down −z. Only while the back camera tracks the room: MATTE on the back camera.
- `age`: milliseconds from the moment the camera took the frame to the moment it went to NDI.
- `detail="ai"`, `ai`, `fit` (DETAIL AI, when the frame got it): the network's milliseconds, and how far half the pixels are from the line that ties it to the sensor (0.01 is 1%).

## Steady and fast

- NDI is heavy: 1080 at 30 frames a second is about 65 Mb/s, at 60 about 130; 4K about four times that, and DEPTH at 1440 × 1920 about as much as 1080 video. On Wi-Fi keep the phone close to the router, or plug it in: a USB-C Ethernet adapter on an iPhone 15 or later, or Personal Hotspot over a USB cable ([Getting started](getting-started.md)).
- Quality first: a warm phone keeps every size and rate. Only when iOS calls it critical does it pause until it cools, before iOS would stop the camera itself. For long runs, keep the phone in the open air, out of a case, away from the sun.
- TouchDesigner does not see the phone? Type the phone's address (DESTINATIONS › THIS PHONE) in the NDI In TOP's Extra Search IPs.
- The phone's screen stays on while a source is on: the lock would take the camera.
