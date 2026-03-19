#include "NodeBase.h"

const char* WIFI_SSID = "SwiftHall38";
const char* WIFI_PASS = "Swifthall38@d3n1t1";

IPAddress STATIC_IPS[] = {
    IPAddress(192, 168, 43, 100),  // NODE_ID 1
    IPAddress(192, 168, 43, 101),  // NODE_ID 2
    IPAddress(192, 168, 43, 102),  // NODE_ID 3
};
IPAddress GATEWAY(192, 168, 43, 1);
IPAddress SUBNET(255, 255, 255, 0);
const int KNOWN_COUNT = 3;

// ── WiFi ─────────────────────────────────────────────────────────────────────

void NodeBase::connectWiFi() {
    if (TEST_MODE)
        WiFi.config(STATIC_IPS[NODE_ID - 1], GATEWAY, SUBNET);

    WiFi.begin(WIFI_SSID, WIFI_PASS);
    Serial.print("[WiFi] Connecting");
    while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }

    _myIP = WiFi.localIP().toString();
    Serial.printf("\n[WiFi] Connected: %s  RSSI: %d dBm\n",
                  _myIP.c_str(), WiFi.RSSI());

    IPAddress ip = WiFi.localIP(), mask = WiFi.subnetMask();
    for (int i = 0; i < 4; i++)
        _broadcastIP[i] = ip[i] | (~mask[i] & 0xFF);
    Serial.printf("[WiFi] Broadcast: %s\n\n", _broadcastIP.toString().c_str());
}

// ── Boot ──────────────────────────────────────────────────────────────────────

void NodeBase::begin() {
    Serial.begin(115200);
    delay(2000);
    Serial.printf("[Boot] NODE_ID=%d  TEST_MODE=%s\n",
                  NODE_ID, TEST_MODE ? "ON" : "OFF");

    connectWiFi();

    _stateTable[_myIP] = {"online", 1};

    _gossipUDP.begin(GOSSIP_PORT);
    _discoveryUDP.begin(DISCOVERY_PORT);

    sendHello();
}

// ── Loop ──────────────────────────────────────────────────────────────────────

void NodeBase::update() {
    handleDiscovery();
    handleGossip();

    if (!_discoveryComplete && millis() - _lastHello > 5000) {
        _lastHello = millis();
        sendHello();
    }

    if (_discoveryComplete && millis() - _lastGossip > 3000) {
        _lastGossip = millis();
        // pick random peer and gossip
        if (!_peers.empty()) {
            IPAddress peer = _peers[random(0, _peers.size())];
            pushStateTo(peer);
        }
    }
}

// ── Discovery ─────────────────────────────────────────────────────────────────

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
    String type    = doc["type"].as<String>();

    if (type == "HELLO") {
        Serial.printf("[Discovery] HELLO from %s\n", from.toString().c_str());
        addPeer(from);

        // ACK with our state + peer list
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

        // Propagate new peer to everyone else
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

        if (doc.containsKey("state"))
            mergeState(doc["state"].as<String>());

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
        if (addPeer(newPeer))
            pushStateTo(newPeer);
    }
}

// ── Gossip ────────────────────────────────────────────────────────────────────

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
    String type    = doc["type"].as<String>();

    if (type == "SYN") {
        Serial.printf("[Gossip] SYN from %s\n", from.toString().c_str());
        if (doc.containsKey("state"))
            mergeState(doc["state"].as<String>());

        // Push-pull: reply with our state
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
        if (doc.containsKey("state"))
            mergeState(doc["state"].as<String>());
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

bool NodeBase::addPeer(IPAddress ip) {
    if (ip == WiFi.localIP()) return false;
    for (auto& p : _peers) if (p == ip) return false;
    _peers.push_back(ip);
    Serial.printf("[Discovery] + Peer: %s (total: %d)\n",
                  ip.toString().c_str(), (int)_peers.size());
    onPeerJoined(ip);
    return true;
}

String NodeBase::stateToJson() {
    DynamicJsonDocument doc(1024);
    for (auto& [key, e] : _stateTable) {
        JsonObject o = doc.createNestedObject(key);
        o["val"] = e.value;
        o["v"]   = e.version;
    }
    String out; serializeJson(doc, out); return out;
}

void NodeBase::mergeState(const String& remoteJson) {
    DynamicJsonDocument doc(1024);
    if (deserializeJson(doc, remoteJson) != DeserializationError::Ok) return;
    for (JsonPair kv : doc.as<JsonObject>()) {
        String   key    = kv.key().c_str();
        uint32_t remVer = kv.value()["v"].as<uint32_t>();
        if (_stateTable.find(key) == _stateTable.end() ||
            remVer > _stateTable[key].version) {
            StateEntry e;
            e.value   = kv.value()["val"].as<String>();
            e.version = remVer;
            _stateTable[key] = e;
            Serial.printf("  [Merge] %s = %s (v%d)\n",
                          key.c_str(), e.value.c_str(), remVer);
            onMessage(key, e);  // ← notify child node
        }
    }
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

void NodeBase::reportState(const String& key, const String& value,
                            MsgPriority priority) {
    if (!_discoveryComplete) return;
    StateEntry e;
    e.value    = value;
    e.version  = _stateTable.count(key) ? _stateTable[key].version + 1 : 1;
    e.priority = (uint8_t)priority;
    _stateTable[key] = e;
    // immediately push to all peers on ALARM, random peer otherwise
    if (priority == MsgPriority::ALARM) {
        for (auto& p : _peers) pushStateTo(p);
    } else if (!_peers.empty()) {
        pushStateTo(_peers[random(0, _peers.size())]);
    }
=======
const char* WIFI_SSID = "YourSSID";
const char* WIFI_PASS = "YourPassword";

IPAddress STATIC_IPS[] = {
    IPAddress(192,168,43,100),
    IPAddress(192,168,43,101),
    IPAddress(192,168,43,102),
};
IPAddress STATIC_GATEWAY(192,168,43,1);
IPAddress STATIC_SUBNET(255,255,255,0);

void NodeBase::connectWiFi() {
    if (TEST_MODE)
        WiFi.config(STATIC_IPS[NODE_ID - 1], STATIC_GATEWAY, STATIC_SUBNET);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    Serial.print("[WiFi] Connecting");
    while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
    _myIP = WiFi.localIP().toString();
    Serial.printf("\n[WiFi] Connected: %s\n", _myIP.c_str());
}

void NodeBase::begin() {
    Serial.begin(115200);
    delay(1000);
    Serial.printf("[Boot] NODE_ID=%d  TEST_MODE=%s\n",
                  NODE_ID, TEST_MODE ? "ON" : "OFF");
    connectWiFi();

    // Wire gossip merge → onMessage virtual
    _gossip.onMerge([this](const String& key, const StateEntry& e) {
        this->onMessage(key, e);
    });

    // Wire discovery peer → onPeerJoined virtual
    _discovery.onPeerAdded([this](IPAddress peer) {
        this->onPeerJoined(peer);
    });

    // Wire cloud command → dispatch (unicast to target node)
    _cloud.onCommand([this](const String& targetIP,
                             const String& action, uint32_t cmdId) {
        this->dispatchCommand(targetIP, action, cmdId);
    });

    _discovery.begin(_myIP);
    _gossip.begin(_myIP, &_discovery.getPeers());
    _cloud.begin(_myIP, &_gossip);

    // Seed own IP into state table
    _gossip.triggerGossip(_myIP, "online", MsgPriority::ROUTINE);
    _discovery.sendHello();
}

void NodeBase::update() {
    _discovery.update();
    _gossip.update();
    _cloud.update();

    // Retry hello until discovery complete
    if (!_discovery.isComplete() && millis() - _lastHello > 5000) {
        _lastHello = millis();
        _discovery.sendHello();
    }

    // Detect leader change
    bool nowLeader = _cloud.isLeader();
    if (nowLeader != _prevLeader) {
        _prevLeader = nowLeader;
        onLeaderChange(nowLeader);
        if (nowLeader) _cloud.publishState();
    }
}

void NodeBase::reportState(const String& key, const String& value,
                            MsgPriority priority) {
    _gossip.triggerGossip(key, value, priority);
    if (_cloud.isLeader()) _cloud.publishState();
}

void NodeBase::dispatchCommand(const String& targetIP,
                                const String& action, uint32_t cmdId) {
    IPAddress target;
    if (!target.fromString(targetIP)) return;

    // If command is for this node, execute directly
    if (targetIP == _myIP) {
        onCommand(action, cmdId);
        return;
    }

    // Otherwise UDP unicast to target (Option 3 from paper)
    WiFiUDP udp;
    StaticJsonDocument<256> doc;
    doc["type"]   = "CMD";
    doc["action"] = action;
    doc["cmdId"]  = cmdId;
    doc["from"]   = _myIP;
    String msg; serializeJson(doc, msg);

    udp.beginPacket(target, GOSSIP_PORT);
    udp.print(msg);
    udp.endPacket();
    Serial.printf("[NodeBase] CMD unicast → %s: %s\n",
                  targetIP.c_str(), action.c_str());

    // Mark DISPATCHED in gossip write-ahead log
    StateEntry e = _gossip.getState("cmd:" + targetIP);
    e.cmdStatus  = "DISPATCHED";
    _gossip.setState("cmd:" + targetIP, e);
}
