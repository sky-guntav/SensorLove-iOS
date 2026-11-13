# Python

`sensorlove.py` prints ACCEL as it arrives, with [python-osc](https://pypi.org/project/python-osc/).

## Play

1. Install python-osc: `pip install python-osc`.
2. Run the script: `python sensorlove.py`.
3. In SensorLove, add your computer in DESTINATIONS (IP, PORT 9000) and switch it on. Start ACCEL.

For another value, map its address from [Sensors](../../docs/sensors.md): `dispatcher.map('/sensorlove/gyro/x', handler)`.

## Tried

python-osc 1.10.2 on Python 3.14 (Windows), with packets built like the app's sent from the same computer: bundles with the time tag 1, several to a send, a text address among them. Not yet with a phone.
