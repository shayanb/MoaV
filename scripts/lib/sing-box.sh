#!/bin/bash
# sing-box specific functions

# Add a new user to sing-box configuration
singbox_add_user() {
    local user_id="$1"
    local user_uuid="$2"
    local user_password="$3"
    local config_file="/configs/sing-box/config.json"

    if [[ ! -f "$config_file" ]]; then
        log_error "sing-box config not found at $config_file"
        return 1
    fi

    # Add to Reality/VLESS users
    jq --arg name "$user_id" --arg uuid "$user_uuid" \
        '.inbounds[] | select(.tag == "vless-reality-in") | .users += [{"name": $name, "uuid": $uuid, "flow": "xtls-rprx-vision"}]' \
        "$config_file" > /tmp/config.tmp && mv /tmp/config.tmp "$config_file"

    # Add to Trojan users
    jq --arg name "$user_id" --arg password "$user_password" \
        '.inbounds[] | select(.tag == "trojan-tls-in") | .users += [{"name": $name, "password": $password}]' \
        "$config_file" > /tmp/config.tmp && mv /tmp/config.tmp "$config_file"

    # Add to Hysteria2 users
    jq --arg name "$user_id" --arg password "$user_password" \
        '.inbounds[] | select(.tag == "hysteria2-in") | .users += [{"name": $name, "password": $password}]' \
        "$config_file" > /tmp/config.tmp && mv /tmp/config.tmp "$config_file"

    log_info "Added user $user_id to sing-box configuration"
}

# Remove a user from sing-box configuration
singbox_remove_user() {
    local user_id="$1"
    local config_file="/configs/sing-box/config.json"

    if [[ ! -f "$config_file" ]]; then
        log_error "sing-box config not found at $config_file"
        return 1
    fi

    # Remove from all inbounds
    jq --arg name "$user_id" \
        '(.inbounds[].users // []) |= map(select(.name != $name))' \
        "$config_file" > /tmp/config.tmp && mv /tmp/config.tmp "$config_file"

    log_info "Removed user $user_id from sing-box configuration"
}

# Reload sing-box configuration
singbox_reload() {
    # sing-box supports hot reload via SIGHUP
    docker kill --signal=SIGHUP moav-sing-box 2>/dev/null || true
    log_info "Sent reload signal to sing-box"
}
