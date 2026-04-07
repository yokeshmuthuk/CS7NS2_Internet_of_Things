#pragma once
#include <WiFi.h>
#include <WiFiUdp.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <map>
#include <vector>
#include <cmath>

// ── Per-device config ────────────────────────────────────────────────────────
#define TEST_MODE  false
#define NODE_ID    2

// ── Network ──────────────────────────────────────────────────────────────────
#define GOSSIP_PORT    4200
#define DISCOVERY_PORT 4201
#define ADMISSION_KEY  "cs7ns2-psk-2026"

// ── Cloud ────────────────────────────────────────────────────────────────────
#define CLOUD_BASE                "https://9lr86473n6.execute-api.eu-west-1.amazonaws.com"
#define HEARTBEAT_INTERVAL        1000
#define CLOUD_PUSH_INTERVAL       20000
#define CLOUD_CMD_INTERVAL        7000
#define CLOUD_THRESHOLD_INTERVAL  60000

// ── Priority classes ────────────────────────────────────────────────────────
enum class MsgPriority : uint8_t {
    ALARM     = 1,
    ROUTINE   = 2,
    TELEMETRY = 3
};

// ── State table entry ────────────────────────────────────────────────────────
struct StateEntry {
    String   value;
    uint32_t version   = 0;
    uint8_t  priority  = (uint8_t)MsgPriority::TELEMETRY;
    uint32_t cmdId     = 0;
    String   cmdStatus;   // PENDING | DISPATCHED | CONFIRMED | FAILED
};

class NodeBase {
public:
    NodeBase() {}
    virtual ~NodeBase() {}

    void begin();
    void update();

    // ── Overrides for child nodes ────────────────────────────────────────────
    virtual void onMessage(const String& key, const StateEntry& entry) {}
    virtual void onPeerJoined(IPAddress peer) {}
    virtual void onCommand(const String& action, uint32_t cmdId) {}

    // ── Simple gossip API ────────────────────────────────────────────────────
    void reportState(const String& key, const String& value,
                     MsgPriority priority = MsgPriority::TELEMETRY);

    void gossipJSON(const String& json,
                    MsgPriority priority = MsgPriority::TELEMETRY);

    void gossipDoc(JsonObjectConst obj,
                   MsgPriority priority = MsgPriority::TELEMETRY);

    // ── Query helpers ────────────────────────────────────────────────────────
    String getState(const String& key);
    bool   hasState(const String& key);
    String getMyIP() { return _myIP; }
    int    peerCount() { return (int)_peers.size(); }

    // ── Debug / diagnostics ──────────────────────────────────────────────────
    void printPeerTable();
    void printStateTable();

protected:
    String                         _myIP;
    bool                           _discoveryComplete = false;
    std::map<String, StateEntry>   _stateTable;
    std::vector<IPAddress>         _peers;

private:
    WiFiUDP   _gossipUDP;
    WiFiUDP   _discoveryUDP;
    IPAddress _broadcastIP;

    // Timers
    uint32_t _lastHello      = 0;
    uint32_t _lastGossip     = 0;
    uint32_t _lastHeartbeat  = 0;
    uint32_t _lastCloudPush  = 0;
    uint32_t _lastCmdPoll    = 0;
    uint32_t _lastThreshold  = (uint32_t)(0UL - CLOUD_THRESHOLD_INTERVAL);

    // ── WiFi ─────────────────────────────────────────────────────────────────
    void connectWiFi();

    // ── Discovery ────────────────────────────────────────────────────────────
    void sendHello();
    void handleDiscovery();
    bool addPeer(IPAddress ip);

    // ── Gossip ───────────────────────────────────────────────────────────────
    void   handleGossip();
    void   gossipTo(MsgPriority priority, bool silent = false);
    void   pushStateTo(IPAddress target, bool silent = false);
    void   mergeState(const String& remoteJson, bool silent = false);
    String stateToJson();

    // ── Cloud ────────────────────────────────────────────────────────────────
    void cloudHeartbeat();
    void cloudPushState();
    void cloudPollCommands();
    void cloudPollThresholds();
    bool httpPOST(const String& path, const String& body, String& response);
    bool httpGET(const String& path, String& response);
};