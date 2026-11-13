# SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

# SensorLove in TouchDesigner: paste all of it into the Textport and press Enter. It builds /project1/sensorlove, which takes
# SensorLove's OSC on UDP port 9000: the phone on screen turns as yours does (ATTITUDE) and the ball grows as you open your
# mouth (FACE TRACK's jawOpen). One-line statements only, so the Textport can run it line by line. See README.md.

s = op('/project1').create(containerCOMP, 'sensorlove')
s.par.w, s.par.h = 1280, 720
s.viewer = True

# Each address comes in as a channel named like it, without the first slash: /sensorlove/attitude/pitch is sensorlove/attitude/pitch
osc = s.create(oscinCHOP, 'oscin1')
osc.par.port = 9000

att = s.create(selectCHOP, 'attitude')
att.par.chop = 'oscin1'
att.par.channames = 'sensorlove/attitude/*'
att.par.renamefrom, att.par.renameto = 'sensorlove/attitude/*', '*'

face = s.create(selectCHOP, 'face')
face.par.chop = 'oscin1'
face.par.channames = 'sensorlove/face/jawOpen'
face.par.renamefrom, face.par.renameto = 'sensorlove/face/*', '*'

# The phone lies flat, its top away from you. iOS turns it by roll, then pitch, then yaw: TouchDesigner's z, x, then y.
# "or 0" until the first values arrive. A new Geometry COMP comes with a torus inside: out it goes
phone = s.create(geometryCOMP, 'phone')
_ = [c.destroy() for c in phone.children]
body = phone.create(boxSOP, 'body')
body.par.sizex, body.par.sizey, body.par.sizez = 0.7, 0.08, 1.45
body.render = body.display = True
phone.par.rord = 'zxy'
phone.par.rx.expr = "math.degrees(op('attitude')['pitch'] or 0)"
phone.par.ry.expr = "math.degrees(op('attitude')['yaw'] or 0)"
phone.par.rz.expr = "-math.degrees(op('attitude')['roll'] or 0)"

ball = s.create(geometryCOMP, 'ball')
_ = [c.destroy() for c in ball.children]
sphere = ball.create(sphereSOP, 'sphere1')
sphere.render = sphere.display = True
ball.par.tx = 1.4
ball.par.scale.expr = "0.15 + 0.45 * (op('face')['jawOpen'] or 0)"

bone = s.create(phongMAT, 'bone')
bone.par.diffr, bone.par.diffg, bone.par.diffb = 0.84, 0.81, 0.74
red = s.create(phongMAT, 'red')
red.par.diffr, red.par.diffg, red.par.diffb = 0.88, 0.33, 0.23
phone.par.material, ball.par.material = 'bone', 'red'

cam = s.create(cameraCOMP, 'cam1')
cam.par.tx, cam.par.ty, cam.par.tz, cam.par.rx = 0.5, 2.4, 3.4, -35
light = s.create(lightCOMP, 'light1')
light.par.tx, light.par.ty, light.par.tz = 2, 4, 3
render = s.create(renderTOP, 'render1')
render.par.outputresolution = 'custom'
render.par.resolutionw, render.par.resolutionh = 1280, 720
render.par.bgcolorr, render.par.bgcolorg, render.par.bgcolorb, render.par.bgcolora = 0.07, 0.07, 0.06, 1
render.viewer = True
s.par.top = './render1'   # the component shows the picture; ./ is inside it

# Tidy the network inside: the data on the left, the picture on the right
osc.nodeX, osc.nodeY = 0, 0
att.nodeX, att.nodeY = 200, 100
face.nodeX, face.nodeY = 200, -100
phone.nodeX, phone.nodeY = 400, 100
ball.nodeX, ball.nodeY = 400, -100
bone.nodeX, bone.nodeY = 600, 100
red.nodeX, red.nodeY = 600, -100
cam.nodeX, cam.nodeY = 600, 250
light.nodeX, light.nodeY = 600, -250
render.nodeX, render.nodeY = 800, 0
print('SensorLove: ' + s.path + ' takes OSC on UDP port 9000')
