#include "NodeBase.h"

// ── WiFi credentials & static IP table ───────────────────────────────────────
const char* WIFI_SSID = "SwiftHall38";
const char* WIFI_PASS = "Swifthall38@d3n1t1";

static IPAddress STATIC_IPS[] = {
    IPAddress(192, 168, 43, 100),   // NODE_ID 1 — Python / laptop
    IPAddress(192, 168, 43, 101),   // NODE_ID 2 — ESP32 #1
    IPAddress(192, 168, 43, 102),   // NODE_ID 3 — ESP32 #2
};
static IPAddress GATEWAY(192, 168, 43, 1);
static IPAddress SUBNET(255, 255, 255, 0);
static const int KNOWN_COUNT = 3;

// ═══════════════════════════════════════════════════════════════════════════════
//  WiFi
// ═══════════════════════════════════════════════════════════════════════════════

void NodeBase::connectWiFi() {
    if (TEST_MODE) {
        WiFi.mode(WIFI_STA);
        WiFi.config(STATIC_IPS[NODE_ID - 1], GATEWAY, SUBNET);
    }
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    Serial.print("[WiFi] Connecting");
    while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }

    _myIP = WiFi.localIP().toString();
    Serial.printf("\n[WiFi] Connected: %s  RSSI: %d dBm\n", _myIP.c_str(), WiFi.RSSI());

    IPAddress ip = WiFi.localIP(), mask = WiFi.subnetMask();
    for (int i = 0; i < 4; i++) _broadcastIP[i] = ip[i] | (~mask[i] & 0xFF);
    Serial.printf("[WiFi] Broadcast: %s\n\n", _broadcastIP.toString().c_str());
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Boot
// ═══════════════════════════════════════════════════════════════════════════════

void NodeBase::begin() {
    Serial.begin(115200);
    delay(2000);
    Serial.printf("[Boot] NODE_ID=%d  TEST_MODE=%s\n",
                  NODE_ID, TEST_MODE ? "ON" : "OFF");
    connectWiFi();

    StateEntry self;
    self.value   = "online";
    self.version = 1;
    _stateTable[_myIP] = self;

    _gossipUDP.begin(GOSSIP_PORT);
    _discoveryUDP.begin(DISCOVERY_PORT);
    sendHello();
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Loop
// ═══════════════════════════════════════════════════════════════════════════════

void NodeBase::update() {
    handleDiscovery();

    if (!_discoveryComplete) {
        if (millis() - _lastHello > 5000) {
            _lastHello = millis();
            sendHello();
        }
        return;
    }

    handleGossip();

    // Background periodic gossip — Class 3 baseline
    if (millis() - _lastGossip > 3000) {
        _lastGossip = millis();
        gossipTo(MsgPriority::TELEMETRY);
    }

    runLeaderElection();

    if (_isLeader) {
        if (millis() - _lastHeartbeat > HEARTBEAT_INTERVAL) {
            _lastHeartbeat = millis();
            cloudHeartbeat();
        }
        if (millis() - _lastCloudPush > CLOUD_PUSH_INTERVAL) {
            _lastCloudPush = millis();
            cloudPushState();
        }
        if (millis() - _lastCmdPoll > CLOUD_CMD_INTERVAL) {
            _lastCmdPoll = millis();
            cloudPollCommands();
        }
        if (millis() - _lastThreshold > CLOUD_THRESHOLD_INTERVAL) {
            _lastThreshold = millis();
            cloudPollThresholds();
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Simple gossip API (public)
// ═══════════════════════════════════════════════════════════════════════════════

void NodeBase::reportState(const String& key, const String& value,
                            MsgPriority priority) {
    if (!_discoveryComplete) return;
    if (_stateTable.count(key) && _stateTable[key].value == value) return;

    StateEntry e;
    e.value    = value;
    e.version  = _stateTable.count(key) ? _stateTable[key].version + 1 : 1;
    e.priority = (uint8_t)priority;
    _stateTable[key] = e;

    gossipTo(priority);
}

// Accepts a flat JSON string — each key/value pair gossiped at given priority.
// Example: gossipJSON("{\"temperature\":22.5,\"humidity\":60}", MsgPriority::ROUTINE)
void NodeBase::gossipJSON(const String& json, MsgPriority priority) {
    if (!_discoveryComplete) return;

    DynamicJsonDocument doc(512);
    if (deserializeJson(doc, json) != DeserializationError::Ok) {
        Serial.println("[gossipJSON] Invalid JSON — ignored");
        return;
    }
    gossipDoc(doc.as<JsonObjectConst>(), priority);
}

// Accepts a pre-built JsonObject — inserts each field into state table and gossips.
// Example:
//   StaticJsonDocument<128> doc;
//   doc["co2_ppm"] = 810;
//   gossipDoc(doc.as<JsonObject>(), MsgPriority::ROUTINE);
void NodeBase::gossipDoc(JsonObjectConst obj, MsgPriority priority) {
    if (!_discoveryComplete) return;

    bool anyChanged = false;
    for (JsonPairConst kv : obj) {
        String key   = kv.key().c_str();
        String value = kv.value().as<String>();

        if (_stateTable.count(key) && _stateTable[key].value == value) continue;

        StateEntry e;
        e.value    = value;
        e.version  = _stateTable.count(key) ? _stateTable[key].version + 1 : 1;
        e.priority = (uint8_t)priority;
        _stateTable[key] = e;
        anyChanged = true;
    }

    if (anyChanged) gossipTo(priority);
}

// ── Query helpers ─────────────────────────────────────────────────────────────

String NodeBase::getState(const String& key) {
    return _stateTable.count(key) ? _stateTable[key].value : "";
}

bool NodeBase::hasState(const String& key) {
    return _stateTable.count(key) > 0;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Discovery
// ═══════════════════════════════════════════════════════════════════════════════

void NodeBase::sendHello() {
    DynamicJsonDocument doc(256);
    doc["type"] = "HELLO";
    doc["ip"]   = _myIP;
    doc["key"]  = ADMISSION_KEY;
    String msg; serializeJson(doc, msg);

    if (TEST_MODE) {
        for (int i = 0; i < KNOWN_COUNT; i++) {
            if (STATIC_IPS[i] == WiFi.localIP()) continue;
            _discoveryUDP.beginPacket(STATIC_IPS[i], DISCOVERY_PORT);
            _discoveryUDP.print(msg);
            _discoveryUDP.endPacket();
            Serial.printf("[Discovery] HELLO → %s (unicast)\n",
                          STATIC_IPS[i].toString().c_str());
        }
    } else {
        _discoveryUDP.beginPacket(_broadcastIP, DISCOVERY_PORT);
        _discoveryUDP.print(msg);
        _discoveryUDP.endPacket();
        Serial.printf("[Discovery] HELLO → %s (broadcast)\n",
                      _broadcastIP.toString().c_str());
    }
}

void NodeBase::handleDiscovery() {
    int len = _discoveryUDP.parsePacket();
    if (!len) return;

    char buf[512];
    len = min(len, (int)sizeof(buf) - 1);
    _discoveryUDP.read(buf, len);
    buf[len] = '\0';

    DynamicJsonDocument doc(1024);
    if (deserializeJson(doc, buf) != DeserializationError::Ok) return;
    if (String(doc["key"].as<const char*>()) != ADMISSION_KEY) return;

    IPAddress from = _discoveryUDP.remoteIP();
    String    type = doc["type"].as<String>();

    if (type == "HELLO") {
        Serial.printf("[Discovery] HELLO from %s\n", from.toString().c_str());
        addPeer(from);

        DynamicJsonDocument ack(1024);
        ack["type"]  = "HELLO_ACK";
        ack["ip"]    = _myIP;
        ack["key"]   = ADMISSION_KEY;
        ack["state"] = stateToJson();
        JsonArray arr = ack.createNestedArray("peers");
        for (auto& p : _peers) arr.add(p.toString());

        String ackMsg; serializeJson(ack, ackMsg);
        _discoveryUDP.beginPacket(from, DISCOVERY_PORT);
        _discoveryUDP.print(ackMsg);
        _discoveryUDP.endPacket();
        Serial.printf("[Discovery] HELLO_ACK → %s (%d peers)\n",
                      from.toString().c_str(), (int)_peers.size());

        DynamicJsonDocument notify(128);
        notify["type"] = "NEW_PEER";
        notify["ip"]   = from.toString();
        notify["key"]  = ADMISSION_KEY;
        String notifyMsg; serializeJson(notify, notifyMsg);
        for (auto& p : _peers) {
            if (p == from) continue;
            _discoveryUDP.beginPacket(p, DISCOVERY_PORT);
            _discoveryUDP.print(notifyMsg);
            _discoveryUDP.endPacket();
        }

    } else if (type == "HELLO_ACK") {
        Serial.printf("[Discovery] HELLO_ACK from %s\n", from.toString().c_str());
        addPeer(from);

        if (doc.containsKey("state")) mergeState(doc["state"].as<String>());
        if (doc.containsKey("peers")) {
            for (JsonVariant p : doc["peers"].as<JsonArray>()) {
                IPAddress newPeer;
                newPeer.fromString(p.as<String>());
                addPeer(newPeer);
            }
        }
        _discoveryComplete = true;
        Serial.println("[Discovery] Complete ✓");

    } else if (type == "NEW_PEER") {
        IPAddress newPeer;
        newPeer.fromString(doc["ip"].as<String>());
        if (addPeer(newPeer)) pushStateTo(newPeer);
    }
}

bool NodeBase::addPeer(IPAddress ip) {
    if (ip == WiFi.localIP()) return false;
    for (auto& p : _peers) if (p == ip) return false;
    _peers.push_back(ip);
    Serial.printf("[Discovery] + Peer: %s (total: %d)\n",
                  ip.toString().c_str(), (int)_peers.size());
    onPeerJoined(ip);
    return true;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Gossip
// ═══════════════════════════════════════════════════════════════════════════════

// Equation (3) — adaptive fanout per priority class
void NodeBase::gossipTo(MsgPriority priority) {
    if (_peers.empty()) return;

    int N      = (int)_peers.size();
    int fanout = 1;
    switch (priority) {
        case MsgPriority::ALARM:    fanout = max(1, N / 2);             break;
        case MsgPriority::ROUTINE:  fanout = max(1, (int)log2((double)N)); break;
        case MsgPriority::TELEMETRY:
        default:                    fanout = 1;                          break;
    }

    std::vector<IPAddress> shuffled = _peers;
    for (int i = (int)shuffled.size() - 1; i > 0; i--) {
        int j = random(0, i + 1);
        std::swap(shuffled[i], shuffled[j]);
    }
    int count = min(fanout, (int)shuffled.size());
    for (int i = 0; i < count; i++) pushStateTo(shuffled[i]);
}

void NodeBase::pushStateTo(IPAddress target) {
    DynamicJsonDocument doc(1024);
    doc["type"]  = "SYN";
    doc["from"]  = _myIP;
    doc["state"] = stateToJson();
    String msg; serializeJson(doc, msg);

    _gossipUDP.beginPacket(target, GOSSIP_PORT);
    _gossipUDP.print(msg);
    _gossipUDP.endPacket();
    Serial.printf("[Gossip] SYN → %s\n", target.toString().c_str());
}

void NodeBase::handleGossip() {
    int len = _gossipUDP.parsePacket();
    if (!len) return;

    char buf[512];
    len = min(len, (int)sizeof(buf) - 1);
    _gossipUDP.read(buf, len);
    buf[len] = '\0';

    DynamicJsonDocument doc(1024);
    if (deserializeJson(doc, buf) != DeserializationError::Ok) return;

    IPAddress from = _gossipUDP.remoteIP();
    String    type = doc["type"].as<String>();

    if (type == "SYN") {
        Serial.printf("[Gossip] SYN from %s\n", from.toString().c_str());
        if (doc.containsKey("state")) mergeState(doc["state"].as<String>());

        // Push-pull — reply with our own state
        DynamicJsonDocument ack(1024);
        ack["type"]  = "ACK";
        ack["from"]  = _myIP;
        ack["state"] = stateToJson();
        String ackMsg; serializeJson(ack, ackMsg);
        _gossipUDP.beginPacket(from, GOSSIP_PORT);
        _gossipUDP.print(ackMsg);
        _gossipUDP.endPacket();
        Serial.printf("[Gossip] ACK → %s\n", from.toString().c_str());

    } else if (type == "ACK") {
        Serial.printf("[Gossip] ACK from %s\n", from.toString().c_str());
        if (doc.containsKey("state")) mergeState(doc["state"].as<String>());

    } else if (type == "CMD") {
        // Direct UDP unicast from leader — execute and confirm
        String   action = doc["action"] | "";
        uint32_t cmdId  = doc["cmdId"]  | 0;
        Serial.printf("[Gossip] CMD: %s (id=%lu)\n",
                      action.c_str(), (unsigned long)cmdId);

        // Dedup — ignore already-confirmed cmdIds
        String cmdKey = "cmd:" + _myIP;
        if (_stateTable.count(cmdKey) &&
            _stateTable[cmdKey].cmdId     == cmdId &&
            _stateTable[cmdKey].cmdStatus == "CONFIRMED") {
            Serial.println("[Gossip] CMD duplicate — ignored");
            return;
        }

        onCommand(action, cmdId);

        // Write CONFIRMED and gossip back so leader (and new leader) can see it
        StateEntry e;
        e.value     = action;
        e.cmdId     = cmdId;
        e.cmdStatus = "CONFIRMED";
        e.version   = _stateTable.count(cmdKey) ? _stateTable[cmdKey].version + 1 : 1;
        _stateTable[cmdKey] = e;
        gossipTo(MsgPriority::ROUTINE);
    }
}

// Equation (7) — last-write-wins on scalar version
void NodeBase::mergeState(const String& remoteJson) {
    DynamicJsonDocument doc(1024);
    if (deserializeJson(doc, remoteJson) != DeserializationError::Ok) return;

    for (JsonPair kv : doc.as<JsonObject>()) {
        String   key    = kv.key().c_str();
        uint32_t remVer = kv.value()["v"].as<uint32_t>();

        if (!_stateTable.count(key) || remVer > _stateTable[key].version) {
            StateEntry e;
            e.value     = kv.value()["val"]   | "";
            e.version   = remVer;
            e.cmdId     = kv.value()["cmdId"] | 0;
            e.cmdStatus = kv.value()["cmdSt"] | "";
            _stateTable[key] = e;
            Serial.printf("  [Merge] %s = %s (v%u)\n",
                          key.c_str(), e.value.c_str(), remVer);
            onMessage(key, e);
        }
    }
}

String NodeBase::stateToJson() {
    DynamicJsonDocument doc(1024);
    for (auto& kv : _stateTable) {
        JsonObject o = doc.createNestedObject(kv.first);
        o["val"]   = kv.second.value;
        o["v"]     = kv.second.version;
        o["cmdId"] = kv.second.cmdId;
        o["cmdSt"] = kv.second.cmdStatus;
    }
    String out; serializeJson(doc, out); return out;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Leader Election
// ═══════════════════════════════════════════════════════════════════════════════

// Equation (5) — priority score delay.
// IP last octet carries weight 150 (larger than heap range 200 only if very similar)
// ensuring nodes with any IP difference get meaningfully separated delays.
int NodeBase::computeBidDelay() {
    float H  = ESP.getFreeHeap()       / (512.0f * 1024.0f);  // 0–1
    float S  = abs(WiFi.RSSI())        / 100.0f;               // 0–1
    float IP = (255 - WiFi.localIP()[3]) / 255.0f;             // 0–1, lower IP = higher

    int d = 500 - (int)(200 * H) - (int)(100 * S) - (int)(150 * IP);
    return constrain(d, 50, 500);
}

void NodeBase::runLeaderElection() {
    // Leader already confirmed in gossip table — accept and settle
    if (_stateTable.count("leader") && _stateTable["leader"].value.length() > 0) {
        bool wasLeader = _isLeader;
        _isLeader      = (_stateTable["leader"].value == _myIP);

        if (_isLeader != wasLeader) {
            Serial.printf("[Leader] %s\n", _isLeader ? "I am leader" : "Stepped down");
            onLeaderChange(_isLeader);
            _leaderAnnounced = false;
        }

        // One-shot cloud announcement when we win
        if (_isLeader && !_leaderAnnounced) {
            _leaderAnnounced = true;
            cloudAnnounceLeader();
        }

        _electionPending = false;
        return;
    }

    // No leader — start countdown
    if (!_electionPending) {
        _electionPending = true;
        int d = computeBidDelay();
        _electionBidAt = millis() + d;
        Serial.printf("[Election] No leader — bidding in %dms\n", d);
        return;
    }

    // Still counting down
    if ((int32_t)(millis() - _electionBidAt) < 0) return;

    // Claim leadership — write into state table and flood all peers
    Serial.printf("[Election] Claiming: %s\n", _myIP.c_str());
    StateEntry e;
    e.value   = _myIP;
    e.version = 1;
    _stateTable["leader"] = e;
    _isLeader             = true;

    for (auto& p : _peers) pushStateTo(p);
    onLeaderChange(true);
    // _leaderAnnounced will trigger cloudAnnounceLeader() next tick
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Cloud
// ═══════════════════════════════════════════════════════════════════════════════

void NodeBase::cloudAnnounceLeader() {
    DynamicJsonDocument doc(128);
    doc["room_id"] = "hub";
    doc["leader"]  = _myIP;
    doc["node_id"] = NODE_ID;
    String body, response;
    serializeJson(doc, body);
    if (httpPOST("/state", body, response))
        Serial.printf("[Cloud] Leader announced: %s\n", _myIP.c_str());
}

void NodeBase::cloudHeartbeat() {
    DynamicJsonDocument doc(128);
    doc["room_id"]   = "hub";
    doc["heartbeat"] = true;
    String body, response;
    serializeJson(doc, body);
    httpPOST("/state", body, response);
}

// Maps gossip state keys to cloud schema fields for POST /state
void NodeBase::cloudPushState() {
    DynamicJsonDocument doc(512);
    doc["room_id"] = "living_room";

    auto get = [&](const String& k) {
        return _stateTable.count(k) ? _stateTable[k].value : String("");
    };
    if (get("temperature").length()) doc["temperature"]   = get("temperature").toFloat();
    if (get("humidity").length())    doc["humidity"]      = get("humidity").toFloat();
    if (get("light_lux").length())   doc["light_lux"]     = get("light_lux").toFloat();
    if (get("co2_ppm").length())     doc["co2_ppm"]       = get("co2_ppm").toFloat();
    if (get("aqi").length())         doc["aqi"]           = get("aqi");
    if (get("rain").length())        doc["rain_detected"] = (get("rain") == "true");

    String body, response;
    serializeJson(doc, body);
    if (httpPOST("/state", body, response))
        Serial.println("[Cloud] State pushed OK");
}

// GET /commands — leader polls, writes WAL, unicasts to target peer
void NodeBase::cloudPollCommands() {
    String response;
    if (!httpGET("/commands", response)) return;

    DynamicJsonDocument doc(1024);
    if (deserializeJson(doc, response) != DeserializationError::Ok) return;
    if ((doc["count"] | 0) == 0) return;

    for (JsonVariant cmd : doc["commands"].as<JsonArray>()) {
        String   command = cmd["command"].as<String>();
        String   room    = cmd["room_id"] | "";
        uint32_t cmdId   = (uint32_t)millis();

        // RE-ELECT signal — cloud detected heartbeat timeout
        if (command == "RE-ELECT") {
            Serial.println("[Election] RE-ELECT from cloud");
            _stateTable.erase("leader");
            _isLeader        = false;
            _leaderAnnounced = false;
            _electionPending = false;
            for (auto& p : _peers) pushStateTo(p);   // flood erasure
            onLeaderChange(false);
            return;
        }

        // Step 1: WAL — PENDING before any dispatch
        String cmdKey = "cmd:" + room;
        StateEntry e;
        e.value     = command;
        e.version   = _stateTable.count(cmdKey) ? _stateTable[cmdKey].version + 1 : 1;
        e.cmdId     = cmdId;
        e.cmdStatus = "PENDING";
        _stateTable[cmdKey] = e;

        // Step 2: Replicate PENDING across mesh before dispatch
        gossipTo(MsgPriority::ROUTINE);

        // Step 3: Find target peer by room and UDP unicast
        bool dispatched = false;
        for (auto& peer : _peers) {
            String roomKey = "room:" + peer.toString();
            if (_stateTable.count(roomKey) && _stateTable[roomKey].value == room) {
                DynamicJsonDocument cmdDoc(256);
                cmdDoc["type"]   = "CMD";
                cmdDoc["action"] = command;
                cmdDoc["cmdId"]  = cmdId;
                cmdDoc["room"]   = room;
                cmdDoc["from"]   = _myIP;
                String cmdMsg; serializeJson(cmdDoc, cmdMsg);

                _gossipUDP.beginPacket(peer, GOSSIP_PORT);
                _gossipUDP.print(cmdMsg);
                _gossipUDP.endPacket();
                Serial.printf("[Cloud] CMD unicast → %s: %s\n",
                              peer.toString().c_str(), command.c_str());

                _stateTable[cmdKey].cmdStatus = "DISPATCHED";
                gossipTo(MsgPriority::ROUTINE);
                dispatched = true;
                break;
            }
        }

        if (!dispatched) {
            // Command is for this node, or room not yet mapped
            Serial.printf("[Cloud] CMD local: %s\n", command.c_str());
            onCommand(command, cmdId);
            _stateTable[cmdKey].cmdStatus = "DISPATCHED";
        }
    }
}

// GET /thresholds — sync into state table and distribute to mesh
void NodeBase::cloudPollThresholds() {
    String response;
    if (!httpGET("/thresholds", response)) return;

    DynamicJsonDocument doc(1024);
    if (deserializeJson(doc, response) != DeserializationError::Ok) return;

    bool anyNew = false;
    for (JsonVariant t : doc["thresholds"].as<JsonArray>()) {
        String key = "thresh:" + t["threshold_id"].as<String>();
        String val = t["value"] | "";
        if (_stateTable.count(key) && _stateTable[key].value == val) continue;

        StateEntry e;
        e.value   = val;
        e.version = _stateTable.count(key) ? _stateTable[key].version + 1 : 1;
        _stateTable[key] = e;
        onMessage(key, e);   // notify child node
        anyNew = true;
    }

    if (anyNew) gossipTo(MsgPriority::ROUTINE);
    Serial.println("[Cloud] Thresholds synced");
}

// ── HTTP ──────────────────────────────────────────────────────────────────────

bool NodeBase::httpPOST(const String& path, const String& body, String& response) {
    WiFiClientSecure client;
    client.setInsecure();
    HTTPClient http;
    if (!http.begin(client, String(CLOUD_BASE) + path)) return false;
    http.addHeader("Content-Type", "application/json");
    int code = http.POST(body);
    bool ok  = (code >= 200 && code < 300);
    if (ok)  response = http.getString();
    else     Serial.printf("[HTTP] POST %s → %d\n", path.c_str(), code);
    http.end();
    return ok;
}

bool NodeBase::httpGET(const String& path, String& response) {
    WiFiClientSecure client;
    client.setInsecure();
    HTTPClient http;
    if (!http.begin(client, String(CLOUD_BASE) + path)) return false;
    int code = http.GET();
    bool ok  = (code >= 200 && code < 300);
    if (ok)  response = http.getString();
    else     Serial.printf("[HTTP] GET %s → %d\n", path.c_str(), code);
    http.end();
    return ok;
}