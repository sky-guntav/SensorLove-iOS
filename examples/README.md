# Examples

Receivers for SensorLove's OSC, ready to open. Each one listens on UDP port 9000, SensorLove's default.

On the phone: open DESTINATIONS, tap + ADD, type your computer's IP (PORT stays 9000) and switch it on with its LED. [Getting started](../docs/getting-started.md) has the details. The first time a program listens, your computer may ask to let it through the firewall: allow it.

| Example | What it does |
| --- | --- |
| [TouchDesigner](touchdesigner/) | A script that builds the network: ATTITUDE turns a phone on screen, FACE TRACK's jawOpen grows a ball. Save it as .toe and .tox. |
| [Max](max/) | Tilting plays a sine wave: ACCEL's x is the pitch, y the volume. |
| [Pure Data](puredata/) | The same sine wave, in vanilla Pd. |
| [Processing](processing/) | ATTITUDE turns a box, with oscP5. |
| [Python](python/) | Prints ACCEL, with python-osc. |

Each README says how far its example has been tried. Every address and what it carries: [Sensors](../docs/sensors.md). How they travel: [OSC](../docs/osc.md).
