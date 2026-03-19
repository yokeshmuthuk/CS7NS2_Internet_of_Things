import socket
import json
import time
import threading
import random

# ══════════════════════════════════════════════════════
#  CONFIGURATION — change these per run
# ══════════════════════════════════════════════════════
TEST_MODE = False   # True = static IP + unicast
                   # False = DHCP + broadcast
NODE_ID   = 1      # always 1 for laptop/python node
# ══════════════════════════════════════════════════════

UDP_PORT_GOSSIP    = 4200
UDP_PORT_DISCOVERY = 4201
ADMISSION_KEY      = "cs7ns2-psk-2026"

STATIC_IPS = {
    1: "192.168.43.100",   # laptop / python node
    2: "192.168.43.101",   # ESP32 Node 1
    3: "192.168.43.102",   # ESP32 Node 2
}

BROADCAST = "192.168.43.255"   # only used when TEST_MODE = False

MY_IP      = ""
peers      = {}    # ip -> last_seen
state_table = {}
discovery_complete = False
lock = threading.Lock()

# ── Helpers ────────────────────────────────────────────
def get_my_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(("8.8.8.8", 80))
    ip = s.getsockname()[0]
    s.close()
    return ip

def state_to_json():
    with lock:
        return json.dumps(state_table)

def merge_state(remote_str):
    try:
        remote = json.loads(remote_str)
        with lock:
            for key, entry in remote.items():
                if key not in state_table or entry["v"] > state_table[key]["v"]:
                    state_table[key] = entry
                    print(f"  [Merge] {key} = {entry['val']} (v{entry['v']})")
    except Exception as e:
        print(f"  [Merge] Error: {e}")

def add_peer(ip):
    if ip == MY_IP:
        return False
    with lock:
        if ip in peers:
            return False
        peers[ip] = time.time()
    print(f"[Discovery] + New peer: {ip}  (total: {len(peers)})")
    return True

def peer_list():
    with lock:
        return list(peers.keys())

def send_udp(ip, port, msg):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.sendto(json.dumps(msg).encode(), (ip, port))
        s.close()
    except Exception as e:
        print(f"  [UDP] Send error to {ip}: {e}")

def push_state_to(target_ip):
    msg = {
        "type":  "SYN",
        "from":  MY_IP,
        "state": state_to_json()
    }
    send_udp(target_ip, UDP_PORT_GOSSIP, msg)
    print(f"[Gossip] Pushed state → {target_ip}")

def print_state():
    print(f"\n── State Table ──────────────────")
    with lock:
        for key, e in state_table.items():
            print(f"  {key:<25} = {e['val']} (v{e['v']})")
    print(f"── Peers ────────────────────────")
    for p in peer_list():
        print(f"  {p}")
    print(f"─────────────────────────────────\n")

# ── Discovery Send ─────────────────────────────────────
def send_hello():
    msg = {
        "type": "HELLO",
        "ip":   MY_IP,
        "key":  ADMISSION_KEY
    }

    if TEST_MODE:
        # Unicast to every known static IP except self
        for nid, ip in STATIC_IPS.items():
            if ip == MY_IP:
                continue
            send_udp(ip, UDP_PORT_DISCOVERY, msg)
            print(f"[Discovery] HELLO → {ip} (unicast)")
    else:
        # Broadcast
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        s.sendto(json.dumps(msg).encode(), (BROADCAST, UDP_PORT_DISCOVERY))
        s.close()
        print(f"[Discovery] HELLO → {BROADCAST} (broadcast)")

# ── Discovery Listener ─────────────────────────────────
def discovery_listener():
    global discovery_complete
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("", UDP_PORT_DISCOVERY))
    print(f"[Discovery] Listening on port {UDP_PORT_DISCOVERY}")

    while True:
        try:
            data, addr = sock.recvfrom(2048)
            msg      = json.loads(data.decode())
            if msg.get("key") != ADMISSION_KEY:
                continue

            from_ip  = addr[0]
            msg_type = msg.get("type")

            # ── HELLO ──────────────────────────────────
            if msg_type == "HELLO":
                print(f"\n[Discovery] HELLO from {from_ip}")
                add_peer(from_ip)

                # Reply with HELLO_ACK + full state + peer list
                ack = {
                    "type":  "HELLO_ACK",
                    "ip":    MY_IP,
                    "key":   ADMISSION_KEY,
                    "state": state_to_json(),
                    "peers": peer_list()
                }
                send_udp(from_ip, UDP_PORT_DISCOVERY, ack)
                print(f"[Discovery] HELLO_ACK → {from_ip} "
                      f"(sharing {len(peer_list())} peers)")

                # Notify all existing peers about the new node
                for p in peer_list():
                    if p == from_ip:
                        continue
                    notify = {
                        "type": "NEW_PEER",
                        "ip":   from_ip,
                        "key":  ADMISSION_KEY
                    }
                    send_udp(p, UDP_PORT_DISCOVERY, notify)
                    print(f"[Discovery] NEW_PEER → {p} about {from_ip}")

                print_state()

            # ── HELLO_ACK ──────────────────────────────
            elif msg_type == "HELLO_ACK":
                print(f"\n[Discovery] HELLO_ACK from {from_ip}")
                add_peer(from_ip)

                if "state" in msg:
                    merge_state(msg["state"])

                # Bootstrap from peer list
                if "peers" in msg:
                    for p in msg["peers"]:
                        add_peer(p)

                discovery_complete = True
                print("[Discovery] Complete ✓")
                print_state()

            # ── NEW_PEER ───────────────────────────────
            elif msg_type == "NEW_PEER":
                new_ip = msg.get("ip")
                print(f"\n[Discovery] NEW_PEER notified: {new_ip}")
                if add_peer(new_ip):
                    push_state_to(new_ip)
                    print_state()

        except Exception as e:
            print(f"[Discovery] Error: {e}")

# ── Gossip Listener ────────────────────────────────────
def gossip_listener():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("", UDP_PORT_GOSSIP))
    print(f"[Gossip] Listening on port {UDP_PORT_GOSSIP}")

    while True:
        try:
            data, addr = sock.recvfrom(2048)
            msg      = json.loads(data.decode())
            from_ip  = addr[0]
            msg_type = msg.get("type")

            if msg_type == "SYN":
                print(f"\n[Gossip] SYN from {from_ip}")
                if "state" in msg:
                    merge_state(msg["state"])

                ack = {
                    "type":  "ACK",
                    "from":  MY_IP,
                    "state": state_to_json()
                }
                send_udp(from_ip, UDP_PORT_GOSSIP, ack)
                print(f"[Gossip] ACK → {from_ip}")
                print_state()

            elif msg_type == "ACK":
                print(f"\n[Gossip] ACK from {from_ip}")
                if "state" in msg:
                    merge_state(msg["state"])
                print_state()

        except Exception as e:
            print(f"[Gossip] Error: {e}")

# ── Gossip Sender ──────────────────────────────────────
def gossip_sender():
    time.sleep(5)
    while True:
        pl = peer_list()
        if pl:
            peer = random.choice(pl)
            msg  = {
                "type":  "SYN",
                "from":  MY_IP,
                "state": state_to_json()
            }
            send_udp(peer, UDP_PORT_GOSSIP, msg)
            print(f"[Gossip] SYN → {peer}")
        time.sleep(3)

# ── Hello Broadcaster ──────────────────────────────────
def hello_broadcaster():
    while not discovery_complete:
        send_hello()
        time.sleep(5)
    print("[Discovery] Broadcast stopped — all peers found")

# ── Main ───────────────────────────────────────────────
if __name__ == "__main__":
    MY_IP = STATIC_IPS[NODE_ID] if TEST_MODE else get_my_ip()

    state_table[MY_IP] = {"val": "online", "v": 1}

    print(f"[Boot] Python node  NODE_ID={NODE_ID}  TEST_MODE={TEST_MODE}")
    print(f"[Boot] My IP        : {MY_IP}")
    if TEST_MODE:
        print(f"[Boot] Known nodes  : {list(STATIC_IPS.values())}")
    else:
        print(f"[Boot] Broadcast    : {BROADCAST}")
    print()

    threading.Thread(target=discovery_listener, daemon=True).start()
    threading.Thread(target=gossip_listener,    daemon=True).start()
    threading.Thread(target=hello_broadcaster,  daemon=True).start()
    threading.Thread(target=gossip_sender,      daemon=True).start()

    while True:
        time.sleep(15)
        print(f"\n{'='*50}")
        print(f"[Status] Peers : {peer_list()}")
        print(f"[Status] State :")
        with lock:
            print(json.dumps(state_table, indent=2))
        print(f"{'='*50}\n")
