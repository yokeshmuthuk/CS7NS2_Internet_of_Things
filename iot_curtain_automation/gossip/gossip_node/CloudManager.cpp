#include "CloudManager.h"
extern const char AWS_CERT_CA[] = "";
extern const char AWS_CERT_CRT[] = "";
extern const char AWS_CERT_KEY[] = "";
CloudManager* CloudManager::_instance = nullptr;

void CloudManager::begin(const String& myIP, GossipManager* gossip) {
    _myIP     = myIP;
    _gossip   = gossip;
    _instance = this;

    if (strlen(AWS_CERT_CA) > 0) {
        _wifiClient.setCACert(AWS_CERT_CA);
        _wifiClient.setCertificate(AWS_CERT_CRT);
        _wifiClient.setPrivateKey(AWS_CERT_KEY);
        _mqtt.setClient(_wifiClient);
        _mqtt.setServer(AWS_ENDPOINT, AWS_PORT);
        _mqtt.setCallback(mqttCallback);
    } else {
        Serial.println("[Cloud] No certs — cloud disabled");
    }
}


int CloudManager::computeBidDelay() {
    // Priority-score election delay from paper:
    // d = Dmax - (200*H + 100*S + 50*IP)
    float H  = ESP.getFreeHeap()  / (512.0f * 1024.0f);
    float S  = abs(WiFi.RSSI())   / 100.0f;
    float IP = WiFi.localIP()[3]  / 255.0f;
    int d    = 500 - (int)(200*H) - (int)(100*S) - (int)(50*IP);
    return constrain(d, 100, 500);
}

void CloudManager::connectMQTT() {
    if (_mqtt.connected()) return;
    Serial.print("[Cloud] Connecting to AWS IoT...");
    while (!_mqtt.connected()) {
        if (_mqtt.connect(THING_NAME)) {
            Serial.println(" connected ✓");
            _mqtt.subscribe(TOPIC_COMMAND);
            _mqtt.subscribe(TOPIC_REELECT);
        } else {
            Serial.printf(" failed (rc=%d), retry in 2s\n", _mqtt.state());
            delay(2000);
        }
    }
}

void CloudManager::sendHeartbeat() {
    StaticJsonDocument<128> doc;
    doc["ip"]  = _myIP;
    doc["ts"]  = millis();
    String msg; serializeJson(doc, msg);
    _mqtt.publish(TOPIC_HEARTBEAT, msg.c_str());
}

void CloudManager::publishState() {
    if (!_isLeader || !_mqtt.connected()) return;
    auto& table = _gossip->getTable();
    StaticJsonDocument<2048> doc;
    for (auto& [key, e] : table) {
        JsonObject o = doc.createNestedObject(key);
        o["val"] = e.value;
        o["v"]   = e.version;
    }
    String msg; serializeJson(doc, msg);
    _mqtt.publish(TOPIC_STATE, msg.c_str());
    Serial.println("[Cloud] State published to AWS");
}

void CloudManager::publishConfirmation(uint32_t cmdId, const String& status) {
    if (!_isLeader || !_mqtt.connected()) return;
    StaticJsonDocument<128> doc;
    doc["cmdId"]  = cmdId;
    doc["status"] = status;
    doc["from"]   = _myIP;
    String msg; serializeJson(doc, msg);
    _mqtt.publish("gossip/cmdack", msg.c_str());
}

void CloudManager::startElection() {
    if (_electing) return;
    _electing        = true;
    _leaderConfirmed = false;
    _electionTimer   = millis() + computeBidDelay();
    Serial.printf("[Cloud] Election started, bid delay=%dms\n",
                  (int)(_electionTimer - millis()));
}

void CloudManager::sendLeaderBid() {
    if (!_mqtt.connected()) return;
    StaticJsonDocument<128> doc;
    doc["type"] = "BID";
    doc["ip"]   = _myIP;
    doc["heap"] = ESP.getFreeHeap();
    doc["rssi"] = WiFi.RSSI();
    String msg; serializeJson(doc, msg);
    _mqtt.publish("gossip/election", msg.c_str());
    Serial.printf("[Cloud] Leader bid sent from %s\n", _myIP.c_str());
}

void CloudManager::mqttCallback(char* topic, byte* payload, unsigned int length) {
    if (_instance) {
        String t(topic);
        String p((char*)payload, length);
        _instance->handleMQTTMessage(t, p);
    }
}

void CloudManager::handleMQTTMessage(const String& topic, const String& payload) {
    StaticJsonDocument<512> doc;
    if (deserializeJson(doc, payload) != DeserializationError::Ok) return;

    if (topic == TOPIC_REELECT) {
        Serial.println("[Cloud] RE-ELECT received");
        _isLeader = false;
        startElection();

    } else if (topic == "gossip/election") {
        String type = doc["type"].as<String>();
        if (type == "CONFIRMED") {
            String leader = doc["ip"].as<String>();
            _isLeader        = (leader == _myIP);
            _leaderConfirmed = true;
            _electing        = false;
            Serial.printf("[Cloud] Leader confirmed: %s %s\n",
                          leader.c_str(), _isLeader ? "(ME)" : "");
            if (_isLeader) connectMQTT();
        }

    } else if (topic == TOPIC_COMMAND) {
        // Leader receives command, dispatches via UDP unicast in NodeBase
        String targetIP = doc["target"].as<String>();
        String action   = doc["action"].as<String>();
        uint32_t cmdId  = doc["cmdId"].as<uint32_t>();

        // Mark PENDING in gossip table (write-ahead log)
        if (_gossip) {
            StateEntry e;
            e.value     = action;
            e.version  += 1;
            e.cmdId     = cmdId;
            e.cmdStatus = "PENDING";
            _gossip->setState("cmd:" + targetIP, e);
        }

        Serial.printf("[Cloud] CMD → %s: %s (id=%d)\n",
                      targetIP.c_str(), action.c_str(), cmdId);
        if (_onCommand) _onCommand(targetIP, action, cmdId);
    }
}

void CloudManager::update() {
    if (_isLeader) {
        if (!_mqtt.connected()) connectMQTT();
        _mqtt.loop();
        if (millis() - _lastHeartbeat > HEARTBEAT_MS) {
            _lastHeartbeat = millis();
            sendHeartbeat();
        }
    }

    // Election timer fire
    if (_electing && !_leaderConfirmed && millis() >= _electionTimer) {
        sendLeaderBid();
        _electing = false;
    }
}
