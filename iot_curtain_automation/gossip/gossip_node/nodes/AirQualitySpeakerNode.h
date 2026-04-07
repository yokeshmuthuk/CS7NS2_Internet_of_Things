// AirQualitySpeakerNode.h
// Sensor : MQ-135 air quality (GPIO 1, ADC)
// Actuator: Speaker via NPN transistor (GPIO 5)
// Gossips : "co2_ppm"       = raw ADC     -> TELEMETRY (background, on change >10)
//           "aqi"           = label       -> ALARM when poor/unhealthy, ROUTINE otherwise
//           "speaker"       = "on"/"off"  -> ROUTINE (on state change only)
//           "speaker_alert" = "active"    -> ALARM (broadcast when speaker turns ON)
// Reacts  : "light_lux" high              -> speaker ON
// Cloud   : No leader logic. This node simply maintains gossip state locally;
//           NodeBase uploads the node's known state table to cloud directly.
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
            "{\"cap:" + getMyIP() + "\":\"co2_ppm:analog:0-5000,aqi:trigger,speaker:binary,speaker_alert:trigger\"}",
            MsgPriority::ROUTINE
        );

        // Serial.println("[AirQualitySpeakerNode] MQ-135 warming up (30 s)...");
        // delay(30000);   // heater warm-up -- acceptable in begin() only
        // Serial.println("[AirQualitySpeakerNode] Ready (leaderless cloud sync)");
    }

    void update() {
        NodeBase::update();
        readAirQuality();
    }

private:
    static const int MQ135_PIN   = 1;
    static const int SPEAKER_PIN = 5;

    int    _co2Threshold   = 300;     // raw ADC -- overridden by thresh:co2_alert
    float  _lightThreshold = 2500.0f; // lux     -- overridden by thresh:light_threshold
    bool   _speakerOn      = false;
    bool   _aqiTriggered   = false;
    bool   _lightTriggered = false;

    // Last-reported shadow values -- used to suppress redundant gossip
    String _lastReportedAQI = "";
    int    _lastReportedRaw = -1;

    String classifyAQI(int raw) {
        if (raw < 100)                 return "excellent";
        if (raw < 200)                 return "good";
        if (raw < _co2Threshold)       return "moderate";
        if (raw < _co2Threshold + 100) return "poor";
        return "unhealthy";
    }

    void readAirQuality() {
        static uint32_t last = 0;
        if (millis() - last < 2000) return;
        last = millis();

        int raw = analogRead(MQ135_PIN);
        String aqi = classifyAQI(raw);
        Serial.printf("[AirQualitySpeakerNode] raw=%d  AQI=%s\n", raw, aqi.c_str());

        // Background telemetry -- only when value shifts meaningfully
        if (_lastReportedRaw < 0 || abs(raw - _lastReportedRaw) > 10) {
            _lastReportedRaw = raw;
            reportState("co2_ppm", String(raw), MsgPriority::TELEMETRY);
        }

        // AQI label -- gossip only on label transition
        if (aqi != _lastReportedAQI) {
            _lastReportedAQI = aqi;
            MsgPriority p = (aqi == "poor" || aqi == "unhealthy")
                            ? MsgPriority::ALARM
                            : MsgPriority::ROUTINE;
            reportState("aqi", aqi, p);
        }

        if (aqi == "poor" || aqi == "unhealthy") {
            _aqiTriggered = true;
            setSpeaker(true, "aqi");
        } else {
            _aqiTriggered = false;
            if (!_lightTriggered) setSpeaker(false, "aqi_clear");
        }
    }

    void setSpeaker(bool on, const char* reason) {
        if (_speakerOn == on) return;

        _speakerOn = on;
        digitalWrite(SPEAKER_PIN, on ? HIGH : LOW);

        reportState("speaker", on ? "on" : "off", MsgPriority::ROUTINE);
        Serial.printf("[AirQualitySpeakerNode] Speaker: %s  reason=%s\n",
                      on ? "ON" : "OFF", reason);

        if (on) {
            reportState("speaker_alert", "active", MsgPriority::ALARM);
            Serial.println("[AirQualitySpeakerNode] >> speaker_alert:active broadcasted");
        } else {
            reportState("speaker_alert", "inactive", MsgPriority::ROUTINE);
        }
    }

    void onMessage(const String& key, const StateEntry& e) override {
        if (key == "light_lux") {
            float lux = e.value.toFloat();
            if (lux > _lightThreshold) {
                Serial.println("[AirQualitySpeakerNode] Sun detected -> speaker ON");
                _lightTriggered = true;
                setSpeaker(true, "light_lux");
            } else {
                _lightTriggered = false;
                if (!_aqiTriggered) setSpeaker(false, "lux_clear");
            }
        }

        if (key == "speaker_alert") {
            if (e.value == "active") {
                Serial.println("[AirQualitySpeakerNode] speaker_alert active -> speaker ON");
                _lightTriggered = true;
                setSpeaker(true, "speaker_alert");
            } else if (e.value == "inactive") {
                _lightTriggered = false;
                if (!_aqiTriggered) setSpeaker(false, "speaker_alert_clear");
            }
        }

        if (key == "thresh:co2_alert") {
            _co2Threshold = e.value.toInt();
            Serial.printf("[AirQualitySpeakerNode] CO2 threshold: %d\n", _co2Threshold);
        }

        if (key == "thresh:light_threshold") {
            _lightThreshold = e.value.toFloat();
            Serial.printf("[AirQualitySpeakerNode] Light threshold: %.1f\n", _lightThreshold);
        }
    }

    void onCommand(const String& action, uint32_t cmdId) override {
        Serial.printf("[AirQualitySpeakerNode] CMD: %s (id=%lu)\n",
                      action.c_str(), (unsigned long)cmdId);

        if (action == "speaker_on" || action == "speaker:1") {
            _lightTriggered = true;
            setSpeaker(true, "cloud_cmd");
        }

        if (action == "speaker_off" || action == "speaker:0") {
            _lightTriggered = false;
            _aqiTriggered = false;
            setSpeaker(false, "cloud_cmd");
        }
    }
};