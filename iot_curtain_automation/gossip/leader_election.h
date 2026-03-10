#pragma once
#include <Arduino.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>

class LeaderElection {
public:
    void begin();
    void loop();

    bool isLeader()          const { return _isLeader; }
    IPAddress leaderIP()     const { return _leaderIP; }
    void onReElectReceived();       // called by MQTT callback

private:
    bool      _isLeader      = false;
    bool      _leaderConfirmed = false;
    IPAddress _leaderIP;
    uint32_t  _lastHeartbeat = 0;
    uint32_t  _electionDelay = 0;
    uint32_t  _electionStart = 0;
    bool      _electing      = false;

    WiFiClientSecure _wifiClient;
    PubSubClient     _mqtt;

    void _connectMQTT();
    void _sendHeartbeat();
    void _sendBid();
    int  _computeDelay();

    static void _mqttCallback(char* topic, byte* payload, unsigned int len);
};
