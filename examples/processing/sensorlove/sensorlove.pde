// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

// SensorLove in Processing: the box turns as your phone does (ATTITUDE).
// Needs the oscP5 library: Sketch › Import Library › Manage Libraries, search oscP5.
import oscP5.*;

OscP5 osc;
float pitch, roll, yaw;   // radians

void setup() {
  size(800, 600, P3D);
  osc = new OscP5(this, 9000);   // listens on UDP port 9000
}

void oscEvent(OscMessage m) {   // once for every message, also each one in a bundle
  if (m.checkAddrPattern("/sensorlove/attitude/pitch")) pitch = m.get(0).floatValue();
  if (m.checkAddrPattern("/sensorlove/attitude/roll")) roll = m.get(0).floatValue();
  if (m.checkAddrPattern("/sensorlove/attitude/yaw")) yaw = m.get(0).floatValue();
}

void draw() {
  background(19, 18, 16);
  lights();
  translate(width / 2, height / 2);
  rotateX(-0.5);   // look down at the table a little
  // The phone lies flat, its top away from you. iOS turns it by roll, then pitch, then yaw; Processing's y points down
  rotateY(yaw);
  rotateX(-pitch);
  rotateZ(roll);
  noStroke();
  fill(214, 206, 189);
  box(140, 16, 290);
}
