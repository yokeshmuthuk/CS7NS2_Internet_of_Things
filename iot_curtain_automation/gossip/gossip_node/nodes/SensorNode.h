#pragma once
#include "../NodeBase.h"

class SensorNode : public NodeBase {
public:
    void begin() {
        NodeBase::begin();
        pinMode(PIR_PIN, INPUT);
        Serial.println("[SensorNode] Ready");
    }

    void update() {
        NodeBase::update();
        readPIR();
        readTemperature();
    }

private:
    static const int PIR_PIN = 4;
    static const int TEMP_PIN = 34;
    bool _lastMotion = false;

    void readPIR() {
        bool motion = digitalRead(PIR_PIN);
        if (motion != _lastMotion) {
            _lastMotion = motion;
            // Class 1 alarm — max fanout, T=500ms
            reportState("motion", motion ? "detected" : "clear",
                        MsgPriority::ALARM);
        }
    }

    void readTemperature() {
        static uint32_t last = 0;
        if (millis() - last < 5000) return;
        last = millis();
        // Simulated read — replace with real sensor driver
        float temp = analogRead(TEMP_PIN) * 0.1f;
        // Class 2 routine update
        reportState("temperature", String(temp, 1), MsgPriority::ROUTINE);
    }

    // React to peer state changes if needed
    void onMessage(const String& key, const StateEntry& e) override {
        Serial.printf("[SensorNode] Received: %s = %s\n",
                      key.c_str(), e.value.c_str());
    }
};
