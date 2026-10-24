#!/bin/bash
#
# Network speed for waybar's custom/netspeed module. The bar shows only an
# icon; download/upload speeds live in the tooltip. Samples the default-route
# interface's byte counters over 1 second and prints one line of JSON
# (return-type: json). Helpers return through $REPLY and files are read with
# `read`, so a run only forks `ip` and `sleep`.

ICON="󰛳"
ICON_DOWN="󰇚"
ICON_UP="󰕒"
DOWN_COLOR="#8ec07c" # gruvbox aqua
UP_COLOR="#fe8019"   # gruvbox orange

# Interface carrying the default route (lowest metric first). Falls back to
# the kernel's IPv4 routing table if `ip` is unavailable.
default_iface() {
    REPLY=""
    if command -v ip >/dev/null; then
        local -a f
        read -ra f < <(ip route show default 2>/dev/null || true)
        ((${#f[@]})) || read -ra f < <(ip -6 route show default 2>/dev/null || true)
        local i
        for ((i = 0; i < ${#f[@]} - 1; i++)); do
            [[ ${f[i]} == dev ]] && { REPLY=${f[i + 1]}; return; }
        done
    fi
    local iface dest _
    while read -r iface dest _; do
        [[ $dest == 00000000 ]] && { REPLY=$iface; return; }
    done </proc/net/route 2>/dev/null
}

# Bytes/s -> "123.4 KB/s".
fmt_speed() {
    local b=$1 n
    if ((b >= 1048576)); then
        n=$((b * 10 / 1048576))
        REPLY="$((n / 10)).$((n % 10)) MB/s"
    elif ((b >= 1024)); then
        n=$((b * 10 / 1024))
        REPLY="$((n / 10)).$((n % 10)) KB/s"
    else
        REPLY="$b B/s"
    fi
}

# Byte total -> "1.2 GB".
fmt_total() {
    local b=$1 t=$(($1 * 10)) i=0
    local -a units=(B KB MB GB TB)
    while ((t >= 10240 && i < 4)); do
        t=$((t / 1024))
        ((i++))
    done
    if ((i == 0)); then
        REPLY="$b B"
    else
        REPLY="$((t / 10)).$((t % 10)) ${units[i]}"
    fi
}

# Unavailable: same icon, dimmed via the class, reason under "Disconnected".
offline() {
    printf '{"text": "%s", "tooltip": "Disconnected\\n%s", "class": "disconnected"}\n' \
        "$ICON" "$1"
    exit 0
}

default_iface
iface=$REPLY
[[ -z $iface ]] && offline "No active network interface"

dir=/sys/class/net/$iface
read -r state 2>/dev/null <"$dir/operstate" || offline "$iface: not found"
# virtual links (wireguard, ppp, tun) report "unknown" while working
[[ $state == up || $state == unknown ]] || offline "$iface is $state"

read -r rx1 2>/dev/null <"$dir/statistics/rx_bytes" || offline "$iface: no statistics"
read -r tx1 2>/dev/null <"$dir/statistics/tx_bytes" || offline "$iface: no statistics"
sleep 1
# the interface can vanish mid-sample (wifi drop, VPN teardown)
read -r rx2 2>/dev/null <"$dir/statistics/rx_bytes" || offline "$iface went away"
read -r tx2 2>/dev/null <"$dir/statistics/tx_bytes" || offline "$iface went away"

# counters restart when a link is re-created; never show a negative speed
down=$((rx2 - rx1)) up=$((tx2 - tx1))
((down < 0)) && down=0
((up < 0)) && up=0

kind=Ethernet
[[ -d $dir/wireless ]] && kind=Wi-Fi
[[ $state == unknown ]] && kind=Virtual

addr=""
if command -v ip >/dev/null; then
    read -r _ _ _ addr _ < <(ip -4 -o addr show dev "$iface" 2>/dev/null || true)
fi

fmt_speed "$down"; dl=$REPLY
fmt_speed "$up"; ul=$REPLY
fmt_total "$rx2"; dl_total=$REPLY
fmt_total "$tx2"; ul_total=$REPLY

tooltip="<span color='$DOWN_COLOR'>$ICON_DOWN $dl</span>"
tooltip+="\\n<span color='$UP_COLOR'>$ICON_UP $ul</span>"
tooltip+="\\n\\n$iface ($kind)${addr:+ · $addr}"
tooltip+="\\nreceived $dl_total · sent $ul_total"

printf '{"text": "%s", "tooltip": "%s", "class": "connected"}\n' "$ICON" "$tooltip"
