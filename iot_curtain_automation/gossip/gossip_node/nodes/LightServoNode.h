// LightServoNode.h
// Sensor : BH1750 light (I2C: SDA=GPIO8, SCL=GPIO9)
// Actuator: Servo window motor (GPIO 5)
// Gossips : "light_lux" = float string -> ROUTINE
// Reacts  : "rain" = "true"            -> close window (ALARM path)
//           "aqi"  = "poor"/"unhealthy" -> close window (ROUTINE path)
//           both cleared               -> reopen window
#pragma once
#include "../NodeBase.h"
#include <Wire.h>
#include <BH1750.h>
#include <ESP32Servo.h>

class LightServoNode : public NodeBase {
public:
    void begin() {
        NodeBase::begin();

        Wire.begin(SDA_PIN, SCL_PIN);
        if (_lightMeter.begin(BH1750::CONTINUOUS_HIGH_RES_MODE, 0x23))
            Serial.println("[LightServoNode] BH1750 Ready");
        else
            Serial.println("[LightServoNode] BH1750 not found -- check wiring");

        _servo.attach(SERVO_PIN);
        _servo.write(CLOSED_ANGLE);
        _windowOpen = false;

        reportState("room:" + getMyIP(), "living_room", MsgPriority::ROUTINE);
        gossipJSON(
            "{\"cap:" + getMyIP() + "\":\"light_lux:analog:0-100000,window:binary\"}",
            MsgPriority::ROUTINE
        );
        Serial.println("[LightServoNode] Ready -- window CLOSED");
    }

    void update() {
        NodeBase::update();
        readLight();
    }

private:
    static const int SDA_PIN      = 8;
    static const int SCL_PIN      = 9;
    static const int SERVO_PIN    = 5;
    static const int OPEN_ANGLE   = 90;
    static const int CLOSED_ANGLE = 0;

    BH1750 _lightMeter;
    Servo  _servo;
    bool   _windowOpen  = false;
    float  _lastLux     = -1.0f;
    bool   _rainClose   = false;  // rain is demanding window closed
    bool   _aqiClose    = false;  // poor AQI is demanding window closed

    void readLight() {
        static uint32_t last = 0;
        if (millis() - last < 1000) return;
        last = millis();

        float lux = _lightMeter.readLightLevel();
        if (lux < 0) return;

        Serial.printf("[LightServoNode] Light: %.1f lx\n", lux);

        // Event-driven: only gossip when lux shifts >5
        if (abs(lux - _lastLux) > 5.0f) {
            _lastLux = lux;
            reportState("light_lux", String(lux, 1), MsgPriority::ROUTINE);
        }
    }

    void openWindow() {
        if (_windowOpen) return;
        _servo.write(OPEN_ANGLE);
        _windowOpen = true;
        reportState("window", "open", MsgPriority::ROUTINE);
        Serial.println("[LightServoNode] Window -> OPEN (90 deg)");
    }

    void closeWindow(const char* reason) {
        if (!_windowOpen) return;
        _servo.write(CLOSED_ANGLE);
        _windowOpen = false;
        reportState("window", "closed", MsgPriority::ALARM);
        Serial.printf("[LightServoNode] Window -> CLOSED  reason=%s\n", reason);
    }

    // Only reopen when BOTH rain and AQI demands are cleared
    void reconsiderOpen() {
        if (!_rainClose && !_aqiClose) openWindow();
    }

    void onMessage(const String& key, const StateEntry& e) override {
        if (key == "rain") {
            if (e.value == "true") {
                Serial.println("[LightServoNode] Rain via gossip -> closing window");
                _rainClose = true;
                closeWindow("rain");
            } else {
                _rainClose = false;
                reconsiderOpen();
            }
        }

        if (key == "aqi") {
            if (e.value == "poor" || e.value == "unhealthy") {
                Serial.println("[LightServoNode] Poor AQI via gossip -> closing window");
                _aqiClose = true;
                closeWindow("aqi");
            } else if (e.value == "good" || e.value == "excellent") {
                _aqiClose = false;
                reconsiderOpen();
            }
            // "moderate" -- no change
        }

        if (key == "thresh:co2_alert")
            Serial.printf("[LightServoNode] CO2 threshold updated: %s\n", e.value.c_str());
    }

    void onCommand(const String& action, uint32_t cmdId) override {
        Serial.printf("[LightServoNode] CMD: %s (id=%lu)\n",
                      action.c_str(), (unsigned long)cmdId);
        if (action == "open_windows"  || action == "window:1") {
            _rainClose = false; _aqiClose = false;  // manual override
            openWindow();
        }
        if (action == "close_windows" || action == "window:0")
            closeWindow("cloud_cmd");
    }

    void onLeaderChange(bool isLeader) override {
        Serial.printf("[LightServoNode] Leader: %s\n", isLeader ? "YES" : "NO");
    }
};
