#include "NodeBase.h"

// ── WiFi credentials & static IP table ───────────────────────────────────────
const char* WIFI_SSID = "NTGR_29CE_2.4GHz";
const char* WIFI_PASS = "vu5YQQtq";

static IPAddress STATIC_IPS[] = {
    IPAddress(192, 168, 43, 100),   // NODE_ID 1 — Python / laptop
    IPAddress(192, 168, 43, 101),   // NODE_ID 2 — ESP32 #1
    IPAddress(192, 168, 43, 102),   // NODE_ID 3 — ESP32 #2
};
static IPAddress GATEWAY(192, 168, 43, 1);
static IPAddress SUBNET(255, 255, 255, 0);
static const int KNOWN_COUNT = 3;

// ═══════════════════════════════════════════════════════════════════════════════
//  Pretty-print helpers
// ═══════════════════════════════════════════════════════════════════════════════

static void printRule(char c = '-', int w = 60) {
    for (int i = 0; i < w; i++) Serial.print(c);
    Serial.println();
}

static String pad(String s, int width) {
    while ((int)s.length() < width) s += ' ';
    if ((int)s.length() > width)    s  = s.substring(0, width);
    return s;
}

void NodeBase::printPeerTable() {
    printRule('=');
    Serial.printf("  PEER TABLE  —  node %s  (%d peers)\n",
                  _myIP.c_str(), (int)_peers.size());
    printRule('=');
    Serial.println("  #   IP Address        Status");
    printRule('-');
    for (int i = 0; i < (int)_peers.size(); i++) {
        String ip = _peers[i].toString();
        Serial.printf("  %-3d %-16s  online\n", i + 1, ip.c_str());
    }
    printRule('=');
    Serial.println();
}

void NodeBase::printStateTable() {
    printRule('=', 72);
    Serial.printf("  STATE TABLE  —  node %s  (%d entries)\n",
                  _myIP.c_str(), (int)_stateTable.size());
    printRule('=', 72);
    Serial.println("  Key                          Value                   Ver  CmdSt");
    printRule('-', 72);
    for (auto& kv : _stateTable) {
        String key = pad(kv.first, 28);
        String val = pad(kv.second.value, 22);
        String cmdSt = kv.second.cmdStatus.length() ? kv.second.cmdStatus : "-";
        Serial.printf("  %s %s v%-4lu %s\n",
                      key.c_str(),
                      val.c_str(),
                      (unsigned long)kv.second.version,
                      cmdSt.c_str());
    }
    printRule('=', 72);
    Serial.println();
}

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
    self.value = "online";
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

    if (millis() - _lastGossip > 3000) {
        _lastGossip = millis();
        gossipTo(MsgPriority::TELEMETRY, true);
    }

    // Leaderless cloud sync: every node does this
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

// ═══════════════════════════════════════════════════════════════════════════════
//  Simple gossip API (public)
// ═══════════════════════════════════════════════════════════════════════════════

void NodeBase::reportState(const String& key, const String& value,
                           MsgPriority priority) {
    if (!_discoveryComplete) return;
    if (_stateTable.count(key) && _stateTable[key].value == value) return;

    StateEntry e;
    e.value = value;
    e.version = _stateTable.count(key) ? _stateTable[key].version + 1 : 1;
    e.priority = (uint8_t)priority;
    _stateTable[key] = e;

    gossipTo(priority);
}

void NodeBase::gossipJSON(const String& json, MsgPriority priority) {
    if (!_discoveryComplete) return;

    DynamicJsonDocument doc(512);
    if (deserializeJson(doc, json) != DeserializationError::Ok) {
        Serial.println("[gossipJSON] Invalid JSON — ignored");
        return;
    }
    gossipDoc(doc.as<JsonObjectConst>(), priority);
}

void NodeBase::gossipDoc(JsonObjectConst obj, MsgPriority priority) {
    if (!_discoveryComplete) return;

    bool anyChanged = false;
    for (JsonPairConst kv : obj) {
        String key = kv.key().c_str();
        String value = kv.value().as<String>();

        if (_stateTable.count(key) && _stateTable[key].value == value) continue;

        StateEntry e;
        e.value = value;
        e.version = _stateTable.count(key) ? _stateTable[key].version + 1 : 1;
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
        }
        Serial.printf("[Discovery] HELLO → %d unicast targets\n", KNOWN_COUNT - 1);
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
    String type = doc["type"].as<String>();

    if (type == "HELLO") {
        Serial.printf("[Discovery] ← HELLO from %s\n", from.toString().c_str());
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
        Serial.printf("[Discovery] ← HELLO_ACK from %s\n", from.toString().c_str());
        addPeer(from);

        if (doc.containsKey("state")) mergeState(doc["state"].as<String>(), true);
        if (doc.containsKey("peers")) {
            for (JsonVariant p : doc["peers"].as<JsonArray>()) {
                IPAddress newPeer;
                newPeer.fromString(p.as<String>());
                addPeer(newPeer);
            }
        }
        _discoveryComplete = true;
        Serial.println("[Discovery] Complete ✓");
        printPeerTable();

    } else if (type == "NEW_PEER") {
        IPAddress newPeer;
        newPeer.fromString(doc["ip"].as<String>());
        if (addPeer(newPeer)) pushStateTo(newPeer, true);
    }
}

bool NodeBase::addPeer(IPAddress ip) {
    if (ip == WiFi.localIP()) return false;
    for (auto& p : _peers) if (p == ip) return false;
    _peers.push_back(ip);
    Serial.printf("[Discovery] + Peer: %s  (total: %d)\n",
                  ip.toString().c_str(), (int)_peers.size());
    onPeerJoined(ip);
    return true;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Gossip
// ═══════════════════════════════════════════════════════════════════════════════

void NodeBase::gossipTo(MsgPriority priority, bool silent) {
    if (_peers.empty()) return;

    int N = (int)_peers.size();
    int fanout = 1;
    switch (priority) {
        case MsgPriority::ALARM:     fanout = max(1, N / 2); break;
        case MsgPriority::ROUTINE:   fanout = max(1, (int)log2((double)N)); break;
        case MsgPriority::TELEMETRY:
        default:                     fanout = 1; break;
    }

    std::vector<IPAddress> shuffled = _peers;
    for (int i = (int)shuffled.size() - 1; i > 0; i--) {
        int j = random(0, i + 1);
        std::swap(shuffled[i], shuffled[j]);
    }

    int count = min(fanout, (int)shuffled.size());
    for (int i = 0; i < count; i++) pushStateTo(shuffled[i], silent);
}

void NodeBase::pushStateTo(IPAddress target, bool silent) {
    DynamicJsonDocument doc(1024);
    doc["type"]  = "SYN";
    doc["from"]  = _myIP;
    doc["state"] = stateToJson();
    String msg; serializeJson(doc, msg);

    _gossipUDP.beginPacket(target, GOSSIP_PORT);
    _gossipUDP.print(msg);
    _gossipUDP.endPacket();

    if (!silent)
        Serial.printf("[Gossip] → SYN %s\n", target.toString().c_str());
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
    String type = doc["type"].as<String>();

    if (type == "SYN") {
        if (doc.containsKey("state")) mergeState(doc["state"].as<String>(), true);

        DynamicJsonDocument ack(1024);
        ack["type"]  = "ACK";
        ack["from"]  = _myIP;
        ack["state"] = stateToJson();
        String ackMsg; serializeJson(ack, ackMsg);
        _gossipUDP.beginPacket(from, GOSSIP_PORT);
        _gossipUDP.print(ackMsg);
        _gossipUDP.endPacket();

    } else if (type == "ACK") {
        if (doc.containsKey("state")) mergeState(doc["state"].as<String>(), true);

    } else if (type == "CMD") {
        String action = doc["action"] | "";
        uint32_t cmdId = doc["cmdId"] | 0;
        String room = doc["room"] | "";

        printRule('*', 60);
        Serial.printf("  *** CMD RECEIVED from %s\n", from.toString().c_str());
        Serial.printf("      action : %s\n", action.c_str());
        Serial.printf("      cmdId  : %lu\n", (unsigned long)cmdId);
        Serial.printf("      room   : %s\n", room.c_str());
        printRule('*', 60);

        String cmdKey = "cmd:" + _myIP;
        if (_stateTable.count(cmdKey) &&
            _stateTable[cmdKey].cmdId == cmdId &&
            _stateTable[cmdKey].cmdStatus == "CONFIRMED") {
            Serial.println("  [CMD] Duplicate — ignored\n");
            return;
        }

        onCommand(action, cmdId);

        StateEntry e;
        e.value = action;
        e.cmdId = cmdId;
        e.cmdStatus = "CONFIRMED";
        e.version = _stateTable.count(cmdKey) ? _stateTable[cmdKey].version + 1 : 1;
        _stateTable[cmdKey] = e;
        gossipTo(MsgPriority::ROUTINE);

        Serial.println("  [CMD] CONFIRMED — state table:");
        printStateTable();
    }
}

void NodeBase::mergeState(const String& remoteJson, bool silent) {
    DynamicJsonDocument doc(1024);
    if (deserializeJson(doc, remoteJson) != DeserializationError::Ok) return;

    for (JsonPair kv : doc.as<JsonObject>()) {
        String key = kv.key().c_str();
        uint32_t remVer = kv.value()["v"].as<uint32_t>();

        if (!_stateTable.count(key) || remVer > _stateTable[key].version) {
            StateEntry e;
            e.value = kv.value()["val"] | "";
            e.version = remVer;
            e.cmdId = kv.value()["cmdId"] | 0;
            e.cmdStatus = kv.value()["cmdSt"] | "";
            _stateTable[key] = e;

            if (!silent)
                Serial.printf("  [Merge] %-28s = %s (v%u)\n",
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
    String out; serializeJson(doc, out); 
    Serial.printf("[stateToJson] %d entries → %s\n", (int)_stateTable.size(), out.c_str());
    return out;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Cloud
// ═══════════════════════════════════════════════════════════════════════════════

void NodeBase::cloudHeartbeat() {
    DynamicJsonDocument doc(128);
    doc["room_id"] = "hub";
    doc["heartbeat"] = true;
    doc["node_ip"] = _myIP;
    doc["node_id"] = NODE_ID;
    String body, response;
    serializeJson(doc, body);
    httpPOST("/state", body, response);
}

void NodeBase::cloudPushState() {
    DynamicJsonDocument doc(2048);
    doc["room_id"] = "living_room";
    doc["node_ip"] = _myIP;
    doc["node_id"] = NODE_ID;

    JsonObject table = doc.createNestedObject("state_table");
    for (auto& kv : _stateTable) {
        JsonObject o = table.createNestedObject(kv.first);
        o["val"]   = kv.second.value;
        o["v"]     = kv.second.version;
        o["cmdId"] = kv.second.cmdId;
        o["cmdSt"] = kv.second.cmdStatus;
    }

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
        Serial.println("[Cloud] State pushed ✓");
}

void NodeBase::cloudPollCommands() {
    String response;
    if (!httpGET("/commands", response)) return;

    DynamicJsonDocument doc(1024);
    if (deserializeJson(doc, response) != DeserializationError::Ok) return;
    if ((doc["count"] | 0) == 0) return;

    for (JsonVariant cmd : doc["commands"].as<JsonArray>()) {
        String command = cmd["command"].as<String>();
        String room    = cmd["room_id"] | "";
        uint32_t cmdId = cmd["cmd_id"] | (uint32_t)millis();

        String myRoomKey = "room:" + _myIP;
        bool isForMe = !_stateTable.count(myRoomKey) || _stateTable[myRoomKey].value == room;
        if (!isForMe) continue;

        String cmdKey = "cmd:" + _myIP;
        if (_stateTable.count(cmdKey) &&
            _stateTable[cmdKey].cmdId == cmdId &&
            _stateTable[cmdKey].cmdStatus == "CONFIRMED") {
            continue;
        }

        Serial.printf("[Cloud] CMD local: %s  room=%s\n", command.c_str(), room.c_str());
        onCommand(command, cmdId);

        StateEntry e;
        e.value = command;
        e.version = _stateTable.count(cmdKey) ? _stateTable[cmdKey].version + 1 : 1;
        e.cmdId = cmdId;
        e.cmdStatus = "CONFIRMED";
        _stateTable[cmdKey] = e;

        gossipTo(MsgPriority::ROUTINE);
    }
}

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
        e.value = val;
        e.version = _stateTable.count(key) ? _stateTable[key].version + 1 : 1;
        _stateTable[key] = e;
        onMessage(key, e);
        anyNew = true;
    }

    if (anyNew) {
        gossipTo(MsgPriority::ROUTINE);
        Serial.println("[Cloud] Thresholds synced — updated state:");
        printStateTable();
    }
}

// ── HTTP ──────────────────────────────────────────────────────────────────────

bool NodeBase::httpPOST(const String& path, const String& body, String& response) {
    WiFiClientSecure client;
    client.setInsecure();
    HTTPClient http;
    if (!http.begin(client, String(CLOUD_BASE) + path)) return false;
    http.addHeader("Content-Type", "application/json");
    int code = http.POST(body);
    bool ok = (code >= 200 && code < 300);
    if (ok) response = http.getString();
    else    Serial.printf("[HTTP] POST %s → %d\n", path.c_str(), code);
    http.end();
    return ok;
}

bool NodeBase::httpGET(const String& path, String& response) {
    WiFiClientSecure client;
    client.setInsecure();
    HTTPClient http;
    if (!http.begin(client, String(CLOUD_BASE) + path)) return false;
    int code = http.GET();
    bool ok = (code >= 200 && code < 300);
    if (ok) response = http.getString();
    else    Serial.printf("[HTTP] GET %s → %d\n", path.c_str(), code);
    http.end();
    return ok;
}