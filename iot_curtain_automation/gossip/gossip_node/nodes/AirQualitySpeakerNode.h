// AirQualitySpeakerNode.h
// Sensor : MQ-135 air quality (GPIO 1, ADC)
// Actuator: Speaker via NPN transistor (GPIO 5)
// Gossips : "co2_ppm" = raw ADC  -> TELEMETRY (background)
//           "aqi"     = label    -> ALARM when poor/unhealthy, ROUTINE otherwise
// Reacts  : "light_lux" high     -> speaker ON
// NOTE: 30 s MQ-135 warm-up in begin() is intentional -- never move to loop().
#pragma once
#include "../NodeBase.h"

class AirQualitySpeakerNode : public NodeBase {
public:
    void begin() {
        NodeBase::begin();
        pinMode(SPEAKER_PIN, OUTPUT);
        digitalWrite(SPEAKER_PIN, LOW);

        reportState("room:" + getMyIP(), "kitchen", MsgPriority::ROUTINE);
        gossipJSON(
            "{\"cap:" + getMyIP() + "\":\"co2_ppm:analog:0-5000,aqi:trigger,speaker:binary\"}",
            MsgPriority::ROUTINE
        );

        Serial.println("[AirQualitySpeakerNode] MQ-135 warming up (30 s)...");
        delay(30000);   // heater warm-up -- acceptable in begin() only
        Serial.println("[AirQualitySpeakerNode] Ready");
    }

    void update() {
        NodeBase::update();
        readAirQuality();
    }

private:
    static const int MQ135_PIN   = 1;
    static const int SPEAKER_PIN = 5;

    int    _co2Threshold   = 550;     // raw ADC -- overridden by thresh:co2_alert
    float  _lightThreshold = 2500.0f; // lux     -- overridden by thresh:light_threshold
    bool   _speakerOn      = false;
    bool   _aqiTriggered   = false;
    bool   _lightTriggered = false;

    // 5-band AQI classifier -- calibrate _co2Threshold via PUT /thresholds
    String classifyAQI(int raw) {
        if (raw < 300)                  return "excellent";
        if (raw < 400)                  return "good";
        if (raw < _co2Threshold)        return "moderate";
        if (raw < _co2Threshold + 150)  return "poor";
        return "unhealthy";
    }

    void readAirQuality() {
        static uint32_t last    = 0;
        static String   lastAQI = "";
        static int      lastRaw = -1;
        if (millis() - last < 2000) return;
        last = millis();

        int    raw = analogRead(MQ135_PIN);
        String aqi = classifyAQI(raw);
        Serial.printf("[AirQualitySpeakerNode] raw=%d  AQI=%s\n", raw, aqi.c_str());

        // Background telemetry -- fanout=1, only when value shifts
        if (abs(raw - lastRaw) > 10) {
            lastRaw = raw;
            reportState("co2_ppm", String(raw), MsgPriority::TELEMETRY);
        }

        // AQI label -- gossip only on transition
        if (aqi != lastAQI) {
            lastAQI = aqi;
            MsgPriority p = (aqi == "poor" || aqi == "unhealthy")
                            ? MsgPriority::ALARM    // Class 1 -- flood mesh
                            : MsgPriority::ROUTINE; // Class 2 -- normal
            reportState("aqi", aqi, p);
        }

        if (aqi == "poor" || aqi == "unhealthy") {
            _aqiTriggered = true;
            setSpeaker(true);
        } else {
            _aqiTriggered = false;
            if (!_lightTriggered) setSpeaker(false);
        }
    }

    void setSpeaker(bool on) {
        if (_speakerOn == on) return;
        _speakerOn = on;
        digitalWrite(SPEAKER_PIN, on ? HIGH : LOW);
        reportState("speaker", on ? "on" : "off", MsgPriority::ROUTINE);
        Serial.printf("[AirQualitySpeakerNode] Speaker: %s\n", on ? "ON" : "OFF");
    }

    void onMessage(const String& key, const StateEntry& e) override {
        if (key == "light_lux") {
            float lux = e.value.toFloat();
            if (lux > _lightThreshold) {
                Serial.println("[AirQualitySpeakerNode] Sun detected -> speaker ON");
                _lightTriggered = true;
                setSpeaker(true);
            } else {
                _lightTriggered = false;
                if (!_aqiTriggered) setSpeaker(false);
            }
        }
        if (key == "thresh:co2_alert") {
            _co2Threshold = e.value.toInt();
            Serial.printf("[AirQualitySpeakerNode] CO2 threshold: %d\n", _co2Threshold);
        }
        if (key == "thresh:light_threshold") {
            _lightThreshold = e.value.toFloat();
        }
    }

    void onCommand(const String& action, uint32_t cmdId) override {
        Serial.printf("[AirQualitySpeakerNode] CMD: %s (id=%lu)\n",
                      action.c_str(), (unsigned long)cmdId);
        if (action == "speaker_on"  || action == "speaker:1") { _lightTriggered = true;  setSpeaker(true);  }
        if (action == "speaker_off" || action == "speaker:0") { _lightTriggered = false; _aqiTriggered = false; setSpeaker(false); }
    }

    void onLeaderChange(bool isLeader) override {
        Serial.printf("[AirQualitySpeakerNode] Leader: %s\n", isLeader ? "YES" : "NO");
    }
};
