// #include "nodes/SimpleNode.h"
// #include "nodes/SensorNode.h"
// #include "nodes/ActuatorNode.h"

// #include "nodes/RainBuzzer.h"
// RainBuzzerNode* node = nullptr;
// void setup() { node = new RainBuzzerNode(); node->begin(); }
// void loop()  { node->update(); }

#include "nodes/LightServoNode.h"
LightServoNode* node = nullptr;
void setup() { node = new LightServoNode(); node->begin(); }
void loop()  { node->update(); }

// #include "nodes/AirQualitySpeakerNode.h"
// AirQualitySpeakerNode* node = nullptr;
// void setup() { node = new AirQualitySpeakerNode(); node->begin(); }
// void loop()  { node->update(); }