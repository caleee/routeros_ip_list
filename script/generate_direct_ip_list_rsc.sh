#!/bin/sh
#
# Filename: generate_direct_ip_list_rsc.sh
# Author: Cao Lei <caolei@mail.com>
# Version:  \  Date:
#   1.0.0   -    2025/01/02
# Description: This script is used to extract IPv4 and IPv6 addresses from a specified IP list and generate an RSC file for SmartDNS direct IP lists.
# Usage: Run this script: `chmod +x generate_direct_ip_list_rsc.sh && ./generate_direct_ip_list_rsc.sh` (root privileges may be required depending on the output directory and usage in crontab)
# Note: Ensure that you understand every command's behaviour. Be aware that processing extremely large files might lead to memory issues.
#
# For crontab(root): 0 0 7 * * /bin/sh /path/to/your/script/generate_direct_ip_list_rsc.sh >/dev/null 2>&1
#
# # !!! Necessary services or software: 'sh', 'curl', 'awk', 'systemd or openrc' (for service management if applicable)
#

# Function switch: Rotate logs
rotatelogs="true"

# Script-level Variables
log_file="/var/log/$(basename "$0").log"
raw_list_url="https://cdn.jsdelivr.net/gh/jiange1236/smartdns-rules@release/Loyalsoldier/ipset/cn+private.txt"

# Function: Generate session ID
generate_session_id() {
    echo "$(date +%Y%m%d%H%M%S)$RANDOM"
}

# Function: Log messages in JSON format
log() {
    log_level="$1"
    message="$2"
    command="$3"
    line_number="$4"
    session_id=$(generate_session_id)

    printf '{"timestamp":"%s","log_level":"%s","message":"%s","host_name":"%s","user_name":"%s",' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" "$log_level" "$message" "$(hostname)" "$USER" >>"$log_file"
    printf '"logger_name":"%s","command":"%s","line":"%s","session_id":"%s"}\n' \
        "$(basename "$0")" "$command" "$line_number" "$session_id" >>"$log_file"
}

# Function: Rotate log files
rotate_logs() {
    if [ ! -f "$log_file" ]; then
        return
    fi

    current_size=$(wc -c <"$log_file")
    max_size="$((1 * 1024 * 1024))"

    if [ "$current_size" -lt "$max_size" ]; then
        return
    fi

    log "INFO" "Rotate logs" "tar" "$LINENO"

    if tar -czf "${log_file}_$(date +%Y%m%d-%H%M%S).tar.gz" "$log_file" >/dev/null 2>&1; then
        : >"$log_file"
        log "INFO" "Rotate log completed" "tar" "$LINENO"
    else
        log "ERROR" "Rotate log failed" "tar" "$LINENO"
        return 1
    fi

    log_dir="$(dirname "$log_file")"
    log_base="$(basename "$log_file")"
    file_count="$(find "$log_dir" -maxdepth 1 -name "${log_base}*tar.gz" | wc -l)"
    max_num="5"

    if [ "$file_count" -gt "$max_num" ]; then
        ls -tr "$log_dir"/${log_base}*tar.gz 2>/dev/null | head -n "$((file_count - max_num))" | xargs rm -f
        log "INFO" "Rotate log completed, cleaned $((file_count - max_num)) old files" "rm" "$LINENO"
    fi
}

# Function: Generate file name
file_name() {
    echo "/tmp/direct_ip$1.$2"
}

# Function: Download raw IP list
download_raw_list() {
    raw_list_file="$(file_name "" "list")"

    log "INFO" "Starting to download raw list file" "curl" "$LINENO"

    if ! curl -s "$raw_list_url" -o "$raw_list_file"; then
        log "ERROR" "Download failed" "curl" "$LINENO"
        exit 1
    fi

    log "INFO" "Successfully downloaded raw list file" "curl" "$LINENO"
    echo "$raw_list_file"
}

# Function: Process IP list and generate RSC file
process_ip_list() {
    raw_list_file="$1"

    for i in "v4" "v6"; do
        list_file="$(file_name "$i" "list")"
        rsc_file="$(file_name "$i" "rsc")"
        list_name="direct_list_ip$i"

        log "INFO" "Starting to process IPv$i addresses" "awk" "$LINENO"

        if ! awk -v i="$i" '\
            $0 ~ "::/127" { \
                if (i == "v6") { \
                    found=1 \
                } else { \
                    exit \
                } \
            } \
            { \
                if ((i == "v6" && found) || (i == "v4" && !found)) { \
                    print \
                } \
            }' "$raw_list_file" >"$list_file"; then
            log "ERROR" "Error processing IPv$i addresses" "awk" "$LINENO"
            exit 1
        fi

        log "INFO" "Successfully processed IPv$i addresses" "awk" "$LINENO"

        echo "/ip firewall address-list" >"$rsc_file"
        awk -v list_name="$list_name" '{
            printf "add address=%s list=%s comment=\"defconf: direct ip address\"\n", $0, list_name
        }' "$list_file" >>"$rsc_file"
        rm -f "$list_file"
        rm -f "$raw_list_file"

        log "INFO" "Successfully generated rsc file for IPv$i" "awk" "$LINENO"
    done
}

# Main execution
main() {
    log "INFO" "Starting script" "$0" "$LINENO"

    raw_list_file=$(download_raw_list)
    process_ip_list "$raw_list_file"

    if [ "$rotatelogs" = "true" ]; then
        rotate_logs
    fi

    log "INFO" "Script finished" "$0" "$LINENO"
    echo "done."
}

# Run main function
main
