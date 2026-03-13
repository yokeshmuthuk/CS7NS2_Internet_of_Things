#include "GossipManager.h"
#include <cmath>

void GossipManager::begin(const String& myIP, std::vector<IPAddress>* peers) {
    _myIP  = myIP;
    _peers = peers;
    _udp.begin(GOSSIP_PORT);
    Serial.printf("[Gossip] Listening on :%d\n", GOSSIP_PORT);
}

// ── Adaptive fanout formula from paper ────────────────
int GossipManager::computeFanout(MsgPriority p) {
    int N = _peers ? (int)_peers->size() : 1;
    if (N < 1) N = 1;
    switch (p) {
        case MsgPriority::ALARM:     return max(1, N / 2);
        case MsgPriority::ROUTINE:   return max(1, (int)ceil(log2(N)));
        case MsgPriority::TELEMETRY: return 1;
    }
    return 1;
}

int GossipManager::computeInterval(MsgPriority p) {
    return (p == MsgPriority::ALARM) ? 500 : 3000;
}

void GossipManager::triggerGossip(const String& key, const String& value,
                                   MsgPriority priority) {
    // Event-driven: only gossip if state actually changed
    if (_table.count(key) && _table[key].value == value) return;
    _table[key].value    = value;
    _table[key].version += 1;
    _table[key].priority = (uint8_t)priority;

    if (!_peers || _peers->empty()) return;

    int fanout = computeFanout(priority);
    Serial.printf("[Gossip] Event-driven trigger  key=%s  fanout=%d  class=%d\n",
                  key.c_str(), fanout, (int)priority);

    // Shuffle peers and pick 'fanout' of them
    std::vector<IPAddress> shuffled = *_peers;
    for (int i = (int)shuffled.size() - 1; i > 0; i--) {
        int j = random(0, i + 1);
        std::swap(shuffled[i], shuffled[j]);
    }
    int count = min(fanout, (int)shuffled.size());
    for (int i = 0; i < count; i++) sendTo(shuffled[i], "SYN");

    _pendingPriority = priority;
    _lastGossip      = millis();
}

void GossipManager::sendTo(IPAddress target, const String& type) {
    StaticJsonDocument<1024> doc;
    doc["type"]  = type;
    doc["from"]  = _myIP;
    doc["state"] = stateToJson();
    String msg; serializeJson(doc, msg);
    _udp.beginPacket(target, GOSSIP_PORT);
    _udp.print(msg);
    _udp.endPacket();
    Serial.printf("[Gossip] %s → %s\n", type.c_str(), target.toString().c_str());
}

String GossipManager::stateToJson() {
    StaticJsonDocument<2048> doc;
    for (auto& [key, e] : _table) {
        JsonObject o = doc.createNestedObject(key);
        o["val"]    = e.value;
        o["v"]      = e.version;
        o["pri"]    = e.priority;
        o["cmdId"]  = e.cmdId;
        o["cmdSt"]  = e.cmdStatus;
    }
    String out; serializeJson(doc, out); return out;
}

void GossipManager::mergeState(const String& remoteJson) {
    StaticJsonDocument<2048> doc;
    if (deserializeJson(doc, remoteJson) != DeserializationError::Ok) return;
    for (JsonPair kv : doc.as<JsonObject>()) {
        String key       = kv.key().c_str();
        uint32_t remVer  = kv.value()["v"].as<uint32_t>();
        if (!_table.count(key) || remVer > _table[key].version) {
            StateEntry e;
            e.value     = kv.value()["val"].as<String>();
            e.version   = remVer;
            e.priority  = kv.value()["pri"].as<uint8_t>();
            e.cmdId     = kv.value()["cmdId"].as<uint32_t>();
            e.cmdStatus = kv.value()["cmdSt"].as<String>();
            _table[key] = e;
            Serial.printf("  [Merge] %s = %s (v%d)\n",
                          key.c_str(), e.value.c_str(), e.version);
            if (_onMerge) _onMerge(key, e);
        }
    }
}

void GossipManager::handlePacket(const char* buf, int len, IPAddress from) {
    StaticJsonDocument<2048> doc;
    if (deserializeJson(doc, buf, len) != DeserializationError::Ok) return;
    String type = doc["type"].as<String>();

    if (type == "SYN") {
        if (doc.containsKey("state")) mergeState(doc["state"].as<String>());
        sendTo(from, "ACK");   // push-pull: reply with our state
    } else if (type == "ACK") {
        if (doc.containsKey("state")) mergeState(doc["state"].as<String>());
    }
}

void GossipManager::update() {
    int len = _udp.parsePacket();
    if (len) {
        char buf[2048];
        _udp.read(buf, sizeof(buf) - 1);
        buf[len] = '\0';
        handlePacket(buf, len, _udp.remoteIP());
    }

    // Periodic background gossip at T=3000ms (Class 3 baseline)
    if (_peers && !_peers->empty()) {
        int interval = computeInterval(_pendingPriority);
        if (millis() - _lastGossip > (uint32_t)interval) {
            _lastGossip      = millis();
            _pendingPriority = MsgPriority::TELEMETRY;
            IPAddress peer   = (*_peers)[random(0, _peers->size())];
            sendTo(peer, "SYN");
        }
    }
}

void GossipManager::setState(const String& key, const StateEntry& entry) {
    _table[key] = entry;
}

StateEntry GossipManager::getState(const String& key) {
    return _table.count(key) ? _table[key] : StateEntry{};
}
