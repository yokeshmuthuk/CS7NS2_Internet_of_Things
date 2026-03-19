#include "nodes/SimpleNode.h"
// #include "nodes/SensorNode.h"
// #include "nodes/ActuatorNode.h"

SimpleNode* node = nullptr;

void setup() {
    node = new SimpleNode();
    node->begin();
}

void loop() {
    node->update();
}
