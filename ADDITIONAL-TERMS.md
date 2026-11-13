# Additional terms

Copyright © 2026 Göktuğ Güntav.

SensorLove is free software: you can share it and change it under the terms of the GNU General Public License, version 3 ([LICENSE](LICENSE)). As its section 7 allows, two terms and one permission are added to it. They apply to SensorLove and to every work based on it.

## 1. Keep the credit (section 7b)

Every copy of SensorLove, changed or not, and every work based on it, must keep this credit:

> Based on SensorLove by Göktuğ Güntav (sensor.love)

- in its source, beside its copyright notices;
- in the Appropriate Legal Notices it shows, for example on an About screen.

## 2. The name and the logo are not licensed (section 7e)

The GPL gives no rights to the name SensorLove, its logo (the peeking frog and its heart), its app icon or the sensor.love domain. A changed version must:

- have a name of its own, not SensorLove and not a name easily mistaken for it;
- have its own icon and logo;
- not suggest that Göktuğ Güntav makes, checks or supports it.

Saying truthfully that it is based on SensorLove is fine: term 1 asks for it.

## 3. Linking with NDI (section 7, an additional permission)

If you modify SensorLove, or any work based on it, by linking or combining it with the NDI® SDK of Vizrt NDI AB (or a modified version of that library), containing parts covered by the terms of the NDI SDK License Agreement, the licensors of SensorLove grant you additional permission to convey the resulting work.

This lets a build of SensorLove include NDI, which is not free software, for VIDEO and DEPTH. The NDI SDK is not part of SensorLove and is not in this repository: it has its own licence, from [ndi.video](https://ndi.video/), and a build fetches it only where that licence was accepted (`ci_scripts/ci_post_clone.sh`). Without it, SensorLove builds and runs without NDI.

## Not ours

- Departure Mono (`WebUI/fonts`) is by Helena Zhang, under the SIL Open Font License 1.1. Its licence is beside it.
- GSAP (`site/gsap.min.js`, the website's garden) is by GreenSock, under its own Standard "No Charge" License ([gsap.com/standard-license](https://gsap.com/standard-license)), not the GPL.
- The weather data comes from [Open-Meteo.com](https://open-meteo.com/), under CC BY 4.0.
- NDI® is a registered trademark of Vizrt NDI AB. The NDI SDK, and the open-source libraries inside it, come with their own licences: a build with NDI shows them in ABOUT.
