#include "NodeBase.h"

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
