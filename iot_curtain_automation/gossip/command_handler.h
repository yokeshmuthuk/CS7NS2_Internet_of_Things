#pragma once
#include <Arduino.h>
#include <WiFiUdp.h>

class CommandHandler {
public:
    void begin();
    void loop();

    // Called by leader's MQTT callback when command arrives
    void onCommandReceived(const std::String& target, const std::String& action,
                           uint32_t cmdId);

private:
    WiFiUDP  _udp;
    uint32_t _seenCmdId = 0;   // dedup — last executed cmdId

    void _dispatchToTarget(const String& targetIP, const String& action,
                           uint32_t cmdId);
    void _executeAction(const String& action);
    void _sendConfirmation(IPAddress leaderIP, uint32_t cmdId);
};
