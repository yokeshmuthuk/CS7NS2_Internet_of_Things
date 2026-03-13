#pragma once
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <functional>
#include "GossipManager.h"

// ── AWS IoT Core credentials — fill these in ──────────
#define AWS_ENDPOINT   "your-endpoint.iot.eu-west-1.amazonaws.com"
#define AWS_PORT       8883
#define THING_NAME     "gossip-leader"
#define TOPIC_STATE    "gossip/state"
#define TOPIC_HEARTBEAT "gossip/heartbeat"
#define TOPIC_COMMAND  "gossip/cmd"
#define TOPIC_REELECT  "gossip/reelect"
#define HEARTBEAT_MS   1000
#define ELECTION_TIMEOUT_MS 2000

// Paste your AWS certs here
extern const char AWS_CERT_CA[];
extern const char AWS_CERT_CRT[];
extern const char AWS_CERT_KEY[];

class CloudManager {
public:
    using CommandCallback = std::function<void(const String& targetIP,
                                                const String& action,
                                                uint32_t cmdId)>;

    void begin(const String& myIP, GossipManager* gossip);
    void update();

    bool isLeader()     { return _isLeader; }
    void publishState();
    void publishConfirmation(uint32_t cmdId, const String& status);

    void onCommand(CommandCallback cb) { _onCommand = cb; }

    // Called by NodeBase when re-election is triggered via gossip
    void startElection();

private:
    WiFiClientSecure _wifiClient;
    PubSubClient     _mqtt;
    GossipManager*   _gossip    = nullptr;
    String           _myIP;
    bool             _isLeader  = false;
    bool             _leaderConfirmed = false;
    uint32_t         _lastHeartbeat   = 0;
    uint32_t         _electionTimer   = 0;
    bool             _electing        = false;
    CommandCallback  _onCommand;

    void connectMQTT();
    void sendHeartbeat();
    void sendLeaderBid();
    int  computeBidDelay();
    static void mqttCallback(char* topic, byte* payload, unsigned int length);
    static CloudManager* _instance;
    void handleMQTTMessage(const String& topic, const String& payload);
};
