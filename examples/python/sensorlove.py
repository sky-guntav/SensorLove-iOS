# SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

"""SensorLove in Python: shows the phone's ACCEL as it arrives.

    pip install python-osc
    python sensorlove.py
"""
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer

accel = {'x': 0.0, 'y': 0.0, 'z': 0.0}


def on_accel(address, value):   # /sensorlove/accel/x and so on, one float in G
    accel[address[-1]] = value
    print('\rACCEL  x %+.2f  y %+.2f  z %+.2f' % (accel['x'], accel['y'], accel['z']), end='', flush=True)


dispatcher = Dispatcher()
for axis in 'xyz':
    dispatcher.map('/sensorlove/accel/' + axis, on_accel)
print('Listening on UDP port 9000. Start ACCEL in SensorLove. Ctrl+C stops.')
BlockingOSCUDPServer(('0.0.0.0', 9000), dispatcher).serve_forever()
