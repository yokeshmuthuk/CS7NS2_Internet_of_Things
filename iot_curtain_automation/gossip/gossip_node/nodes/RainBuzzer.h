// RainBuzzerNode.h
// Sensor : FC-37 rain (GPIO 4, LOW = wet)
// Actuator: Buzzer (GPIO 5)
// Gossips : "rain" = "true"/"false"  -> ALARM
// Reacts  : "light_lux" high (sun)   -> buzzer ON
#pragma once
#include "../NodeBase.h"

class RainBuzzerNode : public NodeBase {
public:
    void begin() {
        NodeBase::begin();
        pinMode(RAIN_PIN,   INPUT);
        pinMode(BUZZER_PIN, OUTPUT);
        digitalWrite(BUZZER_PIN, LOW);
        reportState("room:" + getMyIP(), "balcony", MsgPriority::ROUTINE);
        gossipJSON(
            "{\"cap:" + getMyIP() + "\":\"rain:binary,buzzer:binary\"}",
            MsgPriority::ROUTINE
        );
        Serial.println("[RainBuzzerNode] Ready");
    }

    void update() {
        NodeBase::update();
        readRain();
    }

private:
    static const int RAIN_PIN   = 4;
    static const int BUZZER_PIN = 5;

    bool  _lastRain       = false;
    bool  _buzzerOn       = false;
    bool  _rainTriggered  = false;
    bool  _sunTriggered   = false;
    float _lightThreshold = 2500.0f;  // overridden by thresh:light_threshold

    void readRain() {
        bool rain = (digitalRead(RAIN_PIN) == LOW);  // FC-37: LOW = wet
        if (rain == _lastRain) return;               // event-driven, no gossip spam
        _lastRain = rain;

        Serial.printf("[RainBuzzerNode] Rain: %s\n", rain ? "DETECTED" : "CLEAR");
        reportState("rain", rain ? "true" : "false", MsgPriority::ALARM);

        if (rain) {
            _rainTriggered = true;
            setBuzzer(true);
        } else {
            _rainTriggered = false;
            if (!_sunTriggered) setBuzzer(false);
        }
    }

    void setBuzzer(bool on) {
        if (_buzzerOn == on) return;
        _buzzerOn = on;
        digitalWrite(BUZZER_PIN, on ? HIGH : LOW);
        reportState("buzzer", on ? "on" : "off", MsgPriority::ROUTINE);
        Serial.printf("[RainBuzzerNode] Buzzer: %s\n", on ? "ON" : "OFF");
    }

    void onMessage(const String& key, const StateEntry& e) override {
        if (key == "light_lux") {
            float lux = e.value.toFloat();
            if (lux > _lightThreshold) {
                Serial.println("[RainBuzzerNode] Sun detected via gossip -> buzzer ON");
                _sunTriggered = true;
                setBuzzer(true);
            } else {
                _sunTriggered = false;
                if (!_rainTriggered) setBuzzer(false);
            }
        }
        if (key == "thresh:light_threshold") {
            _lightThreshold = e.value.toFloat();
            Serial.printf("[RainBuzzerNode] Light threshold: %.1f lux\n", _lightThreshold);
        }
    }

    void onCommand(const String& action, uint32_t cmdId) override {
        Serial.printf("[RainBuzzerNode] CMD: %s (id=%lu)\n",
                      action.c_str(), (unsigned long)cmdId);
        if (action == "buzzer_on"  || action == "buzzer:1") { _sunTriggered = true;  setBuzzer(true);  }
        if (action == "buzzer_off" || action == "buzzer:0") { _sunTriggered = false; _rainTriggered = false; setBuzzer(false); }
    }

    void onLeaderChange(bool isLeader) override {
        Serial.printf("[RainBuzzerNode] Leader: %s\n", isLeader ? "YES" : "NO");
    }
};
