// Change this include to switch node type per device
#include "nodes/ActuatorNode.h"
// #include "nodes/SensorNode.h"

ActuatorNode node;
// SensorNode node;

void setup() { node.begin(); }
void loop()  { node.update(); }
