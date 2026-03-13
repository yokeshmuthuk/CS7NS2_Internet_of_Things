#pragma once
#include "../NodeBase.h"
#include <ESP32Servo.h>

class ActuatorNode : public NodeBase {
public:
    void begin() {
        NodeBase::begin();
        pinMode(LED_PIN, OUTPUT);
        _servo.attach(SERVO_PIN);
        Serial.println("[ActuatorNode] Ready");
    }

    void update() {
        NodeBase::update();
        // Check for pending commands in gossip table
        checkPendingCommands();
    }

private:
    static const int LED_PIN   = 2;
    static const int SERVO_PIN = 13;
    Servo _servo;

    // Triggered by gossip merge of alarm state
    void onMessage(const String& key, const StateEntry& e) override {
        if (key == "motion" && e.value == "detected") {
            // Class 1 alarm received — immediate response
            digitalWrite(LED_PIN, HIGH);
            reportState("led", "on", MsgPriority::ALARM);
        }
        if (key == "motion" && e.value == "clear") {
            digitalWrite(LED_PIN, LOW);
            reportState("led", "off", MsgPriority::ROUTINE);
        }
    }

    // Triggered by cloud command delivered via UDP unicast
    void onCommand(const String& action, uint32_t cmdId) override {
        Serial.printf("[ActuatorNode] CMD: %s (id=%d)\n",
                      action.c_str(), cmdId);
        if (action == "servo_open")  _servo.write(90);
        if (action == "servo_close") _servo.write(0);
        if (action == "led_on")      digitalWrite(LED_PIN, HIGH);
        if (action == "led_off")     digitalWrite(LED_PIN, LOW);

        // Confirm back to leader → cloud
        StateEntry e = _gossip.getState("cmd:" + _myIP);
        e.cmdStatus  = "CONFIRMED";
        _gossip.setState("cmd:" + _myIP, e);
        _cloud.publishConfirmation(cmdId, "CONFIRMED");
    }

    void onLeaderChange(bool isLeader) override {
        Serial.printf("[ActuatorNode] Leader: %s\n", isLeader ? "YES" : "NO");
    }

    void checkPendingCommands() {
        String cmdKey = "cmd:" + _myIP;
        StateEntry e  = _gossip.getState(cmdKey);
        if (e.cmdStatus == "PENDING") {
            onCommand(e.value, e.cmdId);
        }
    }
};
