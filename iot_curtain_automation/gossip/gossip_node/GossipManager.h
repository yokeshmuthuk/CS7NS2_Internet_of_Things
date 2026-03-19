#pragma once
#include <WiFi.h>
#include <WiFiUdp.h>
#include <ArduinoJson.h>
#include <map>
#include <vector>
#include <functional>

#define GOSSIP_PORT 4200

// Priority classes — matches your paper exactly
enum class MsgPriority : uint8_t {
    ALARM     = 1,   // fanout = N/2, T = 500ms
    ROUTINE   = 2,   // fanout = log2(N), T = 3000ms
    TELEMETRY = 3    // fanout = 1,    T = 3000ms
};

struct StateEntry {
    String   value;
    uint32_t version  = 0;
    uint8_t  priority = (uint8_t)MsgPriority::TELEMETRY;
    uint32_t cmdId    = 0;
    String   cmdStatus;   // "PENDING" | "DISPATCHED" | "CONFIRMED" | "FAILED"
};

class GossipManager {
public:
    using MergeCallback = std::function<void(const String&, const StateEntry&)>;

    void begin(const String& myIP, std::vector<IPAddress>* peers);
    void update();

    // Called by node on sensor change — triggers adaptive fanout immediately
    void triggerGossip(const String& key, const String& value,
                       MsgPriority priority = MsgPriority::TELEMETRY);

    void setState(const String& key, const StateEntry& entry);
    StateEntry getState(const String& key);
    String stateToJson();

    void onMerge(MergeCallback cb) { _onMerge = cb; }

    std::map<String, StateEntry>& getTable() { return _table; }

private:
    WiFiUDP   _udp;
    String    _myIP;
    std::vector<IPAddress>* _peers = nullptr;
    std::map<String, StateEntry> _table;
    MergeCallback _onMerge;

    uint32_t _lastGossip = 0;
    MsgPriority _pendingPriority = MsgPriority::TELEMETRY;

    int  computeFanout(MsgPriority p);
    int  computeInterval(MsgPriority p);
    void sendTo(IPAddress target, const String& type);
    void mergeState(const String& remoteJson);
    void handlePacket(const char* buf, int len, IPAddress from);
};
