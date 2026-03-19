#pragma once
#include <WiFi.h>
#include <WiFiUdp.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <map>
#include <vector>
#include <cmath>

#define TEST_MODE  false
#define NODE_ID    3

#define GOSSIP_PORT    4200
#define DISCOVERY_PORT 4201
#define ADMISSION_KEY  "cs7ns2-psk-2026"

#define CLOUD_BASE               "https://9lr86473n6.execute-api.eu-west-1.amazonaws.com"
#define HEARTBEAT_INTERVAL       1000    // H = 1000ms
#define CLOUD_PUSH_INTERVAL      20000
#define CLOUD_CMD_INTERVAL       7000
#define CLOUD_THRESHOLD_INTERVAL 60000

enum class MsgPriority : uint8_t {
    ALARM     = 1,   // fanout = N/2,    T = 500ms
    ROUTINE   = 2,   // fanout = log2(N), T = 3000ms
    TELEMETRY = 3    // fanout = 1,       T = 3000ms
};

struct StateEntry {
    String   value;
    uint32_t version   = 0;
    uint8_t  priority  = (uint8_t)MsgPriority::TELEMETRY;
    uint32_t cmdId     = 0;
    String   cmdStatus;  // PENDING | DISPATCHED | CONFIRMED | FAILED
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
    String getMyIP()    { return _myIP; }
    bool   isLeader()   { return _isLeader; }
    String getLeaderIP(){ return _stateTable.count("leader") ? _stateTable["leader"].value : ""; }

protected:
    String                       _myIP;
    bool                         _discoveryComplete = false;
    bool                         _isLeader          = false;
    std::map<String, StateEntry> _stateTable;
    std::vector<IPAddress>       _peers;

private:
    WiFiUDP   _gossipUDP;
    WiFiUDP   _discoveryUDP;
    IPAddress _broadcastIP;

    // Timers
    uint32_t _lastHello     = 0;
    uint32_t _lastGossip    = 0;
    uint32_t _lastHeartbeat = 0;
    uint32_t _lastCloudPush = 0;
    uint32_t _lastCmdPoll   = 0;
    uint32_t _lastThreshold = 0;

    // Leader election state
    bool     _electionPending = false;
    uint32_t _electionBidAt   = 0;

    // ── Discovery ────────────────────────────────────
    void connectWiFi();
    void sendHello();
    void handleDiscovery();
    bool addPeer(IPAddress ip);

    // ── Gossip ───────────────────────────────────────
    void handleGossip();
    void gossipTo(MsgPriority priority);
    void pushStateTo(IPAddress target);
    void mergeState(const String& remoteJson);
    String stateToJson();

    // ── Leader election ──────────────────────────────
    void runLeaderElection();
    int  computeBidDelay();

    // ── Cloud ────────────────────────────────────────
    void cloudHeartbeat();
    void cloudPushState();
    void cloudPollCommands();
    void cloudPollThresholds();
    bool httpPOST(const String& path, const String& body, String& response);
    bool httpGET(const String& path, String& response);
};
