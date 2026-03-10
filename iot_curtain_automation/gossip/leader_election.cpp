#include "leader_election.h"
#include "config.h"
#include "gossip.h"
#include <ArduinoJson.h>

extern GossipEngine  gGossip;
static LeaderElection* _instance = nullptr;

void LeaderElection::begin() {
    _instance = this;
    _wifiClient.setCACert(MQTT_CA_CERT);
    _wifiClient.setCertificate(MQTT_CLIENT_CERT);
    _wifiClient.setPrivateKey(MQTT_CLIENT_KEY);
    _mqtt.setClient(_wifiClient);
    _mqtt.setServer(MQTT_BROKER, MQTT_PORT);
    _mqtt.setCallback(_mqttCallback);
}

void LeaderElection::loop() {
    if (!_mqtt.connected()) _connectMQTT();
    _mqtt.loop();

    if (_isLeader) {
        if (millis() - _lastHeartbeat >= HEARTBEAT_INTERVAL_MS) {
            _sendHeartbeat();
            _lastHeartbeat = millis();
        }
    }

    // Election timer countdown
    if (_electing && !_leaderConfirmed) {
        if (millis() - _electionStart >= (uint32_t)_electionDelay) {
            _sendBid();
            _electing = false;
        }
    }
}

void LeaderElection::onReElectReceived() {
    Serial.println("[Election] RE-ELECT received — computing delay");
    _leaderConfirmed = false;
    _isLeader        = false;
    _electionDelay   = _computeDelay();
    _electionStart   = millis();
    _electing        = true;
    Serial.printf("[Election] Bid delay = %dms\n", _electionDelay);
}

int LeaderElection::_computeDelay() {
    float H  = ESP.getFreeHeap()  / (512.0f * 1024.0f);
    float S  = abs(WiFi.RSSI())   / 100.0f;
    float IP = WiFi.localIP()[3]  / 255.0f;
    int d = ELECTION_DELAY_MAX_MS
            - (int)(ELECTION_ALPHA * H)
            - (int)(ELECTION_BETA  * S)
            + (int)(ELECTION_GAMMA * IP);
    return constrain(d, ELECTION_DELAY_MIN_MS, ELECTION_DELAY_MAX_MS);
}

void LeaderElection::_sendBid() {
    StaticJsonDocument<128> doc;
    doc["type"] = "BID";
    doc["ip"]   = WiFi.localIP().toString();
    String msg;
    serializeJson(doc, msg);
    _mqtt.publish(MQTT_TOPIC_ELECT, msg.c_str());
    Serial.println("[Election] Bid sent");
}

void LeaderElection::_sendHeartbeat() {
    StaticJsonDocument<64> doc;
    doc["ip"] = WiFi.localIP().toString();
    String msg;
    serializeJson(doc, msg);
    _mqtt.publish(MQTT_TOPIC_HB, msg.c_str());
}

void LeaderElection::_connectMQTT() {
    while (!_mqtt.connected()) {
        Serial.print("[MQTT] Connecting...");
        if (_mqtt.connect(WiFi.localIP().toString().c_str())) {
            Serial.println(" connected");
            _mqtt.subscribe(MQTT_TOPIC_ELECT);
            _mqtt.subscribe(MQTT_TOPIC_CMD);
        } else {
            Serial.printf(" failed rc=%d — retry 2s\n", _mqtt.state());
            delay(2000);
        }
    }
}

void LeaderElection::_mqttCallback(char* topic, byte* payload, unsigned int len) {
    if (!_instance) return;
    String t(topic);
    String msg((char*)payload, len);

    StaticJsonDocument<256> doc;
    if (deserializeJson(doc, msg) != DeserializationError::Ok) return;

    if (t == MQTT_TOPIC_ELECT) {
        String type = doc["type"].as<String>();
        if (type == "REELECT") {
            _instance->onReElectReceived();
        } else if (type == "CONFIRM") {
            String winner = doc["ip"].as<String>();
            _instance->_leaderConfirmed = true;
            _instance->_electing        = false;
            if (winner == WiFi.localIP().toString()) {
                _instance->_isLeader = true;
                Serial.println("[Election] I am the new leader");
            } else {
                Serial.printf("[Election] Leader is %s\n", winner.c_str());
            }
            // Gossip the new leader identity to all local peers
            gGossip.onStateChange("leader", winner,
                                  UpdateClass::CLASS1_ALARM);
        }
    }
}
