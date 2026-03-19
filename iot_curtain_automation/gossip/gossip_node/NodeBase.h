#pragma once
#include <WiFi.h>
#include <WiFiUdp.h>
#include <ArduinoJson.h>
#include <map>
#include <vector>

// ── Per-device config ────────────────────────────────
#define TEST_MODE  false
#define NODE_ID    3

// ── Ports & keys ────────────────────────────────────
#define GOSSIP_PORT    4200
#define DISCOVERY_PORT 4201
#define ADMISSION_KEY  "cs7ns2-psk-2026"

// ── Priority (kept for child node API compat) ────────
enum class MsgPriority : uint8_t {
    ALARM     = 1,
    ROUTINE   = 2,
    TELEMETRY = 3
};

struct StateEntry {
    String   value;
    uint32_t version   = 0;
    uint8_t  priority  = (uint8_t)MsgPriority::TELEMETRY;
    uint32_t cmdId     = 0;
    String   cmdStatus;
};

class NodeBase {
public:
    NodeBase() {}
    virtual ~NodeBase() {}

    void begin();
    void update();

    // ── Override in child nodes ──────────────────────
    virtual void onMessage(const String& key, const StateEntry& entry) {}
    virtual void onPeerJoined(IPAddress peer) {}
    virtual void onLeaderChange(bool isLeader) {}
    virtual void onCommand(const String& action, uint32_t cmdId) {}

    // ── Helpers for child nodes ──────────────────────
    void   reportState(const String& key, const String& value,
                       MsgPriority priority = MsgPriority::TELEMETRY);
    String getMyIP()  { return _myIP; }
    bool   isLeader() { return _isLeader; }

protected:
    String                   _myIP;
    bool                     _discoveryComplete = false;
    bool                     _isLeader          = false;
    std::map<String, StateEntry> _stateTable;
    std::vector<IPAddress>   _peers;

private:
    WiFiUDP  _gossipUDP;
    WiFiUDP  _discoveryUDP;
    IPAddress _broadcastIP;

    uint32_t _lastHello  = 0;
    uint32_t _lastGossip = 0;
    uint32_t _lastPrint  = 0;

    void connectWiFi();
    void sendHello();

    bool   addPeer(IPAddress ip);
    String stateToJson();
    void   mergeState(const String& remoteJson);
    void   pushStateTo(IPAddress target);

    void handleDiscovery();
    void handleGossip();
};
