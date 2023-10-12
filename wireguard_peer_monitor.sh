#!/bin/bash

# Ensure peer_pub_key is passed as an argument
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <peer_pub_key>"
    exit 1
fi

peer_pub_key="$1"
peer_was_active=false
inactive_timer=0

# Time (in seconds) to consider the peer as inactive before sending an event
inactive_threshold=70  # example: 5 minutes
# Interval (in seconds) to check the peer status
check_interval=10  # example: 10 seconds

# Function to check if peer is active based on handshake time
is_peer_active() {
    local handshake="$1"
    echo "$handshake"

    if echo "$handshake" | grep -Eq "hour|day|year"; then
        return 1 # Peer is not active
    elif echo "$handshake" | grep -q "second" && ! echo "$handshake" | grep -q "minute"; then
        return 0 # Peer is active
    elif echo "$handshake" | grep -q "minute,"; then
        local minute=$(echo "$handshake" | awk '{print $1}')
        local second=$(echo "$handshake" | awk '{print $3}')

        if [[ "$minute" -eq 1 && "$second" -le 59 ]]; then
            return 0 # Peer is active
        fi
    fi

    return 1 # Peer is not active
}

while true; do
    # Fetch the latest handshake time for the given peer
    handshake_time=$(wg show wg0 | grep -A 3 "$peer_pub_key" | grep "latest handshake:" | awk -F': ' '{print $2}')

    # Check if peer is active
    is_peer_active "$handshake_time"
    peer_is_active=$?
    #echo "$is_peer_active"
    # Check for activity transition from inactive to active
    if [ "$peer_is_active" -eq 0 ] && [ "$peer_was_active" = false ]; then
        echo "Peer has become active. Triggering event..."
        #aws events put-events --entries '[{"Source":"vpn.monitoring","DetailType":"VPN Usage","Detail":"{\"status\":\"active\"}","EventBusName":"default"}]'
        peer_was_active=true
        inactive_timer=0
    fi

    # If peer is inactive
    if [ "$peer_is_active" -eq 1 ]; then
        ((inactive_timer+=check_interval))

        # If peer was previously active and has been inactive for the threshold duration
        if [ "$peer_was_active" = true ] && [ "$inactive_timer" -ge "$inactive_threshold" ]; then
            echo "Peer has been inactive for $inactive_timer seconds. Triggering event..."
            #aws events put-events --entries '[{"Source":"vpn.monitoring","DetailType":"VPN Usage","Detail":"{\"status\":\"inactive\"}","EventBusName":"default"}]'
            peer_was_active=false
            inactive_timer=0
        fi
    else
        inactive_timer=0
    fi

    # Wait for check_interval seconds before checking again
    sleep $check_interval
done
