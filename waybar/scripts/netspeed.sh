#!/bin/bash
#
# Live download/upload speed for waybar's custom/netspeed module.
# Samples the default-route interface's byte counters over 1 second and
# prints one line of JSON (return-type: json). Helpers return through
# $REPLY and files are read with `read`, so a run only forks `ip` and `sleep`.

DOWN_COLOR="#8ec07c" # gruvbox aqua
UP_COLOR="#fe8019"   # gruvbox orange
ICON_DOWN="󰇚"
ICON_UP="󰕒"

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

# Bytes/s -> "123.4 KB/s"; with "pad", fixed width so the bar doesn't jitter.
fmt_speed() {
    local b=$1 n u
    if ((b >= 1048576)); then
        n=$((b * 10 / 1048576)) u="MB/s"
        n="$((n / 10)).$((n % 10))"
    elif ((b >= 1024)); then
        n=$((b * 10 / 1024)) u="KB/s"
        n="$((n / 10)).$((n % 10))"
    else
        n=$b u="B/s "
    fi
    if [[ $2 == pad ]]; then
        printf -v REPLY '%5s %s' "$n" "$u"
    else
        REPLY="$n ${u% }"
    fi
}

# Byte total -> "1.2 GB", for the tooltip.
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

# Unavailable: dimmed placeholder, reason in the tooltip.
offline() {
    printf '{"text": "%s -- %s --", "tooltip": "%s", "class": "disconnected"}\n' \
        "$ICON_DOWN" "$ICON_UP" "$1"
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

class=active
((down == 0 && up == 0)) && class=idle

kind=Ethernet
[[ -d $dir/wireless ]] && kind=Wi-Fi
[[ $state == unknown ]] && kind=Virtual

addr=""
if command -v ip >/dev/null; then
    read -r _ _ _ addr _ < <(ip -4 -o addr show dev "$iface" 2>/dev/null || true)
fi

fmt_speed "$down" pad
text="<span color='$DOWN_COLOR'>$ICON_DOWN $REPLY</span>"
fmt_speed "$up" pad
text+="  <span color='$UP_COLOR'>$ICON_UP $REPLY</span>"

tooltip="$iface ($kind)${addr:+ · $addr}"
fmt_speed "$down"; dl=$REPLY
fmt_total "$rx2"; dl_total=$REPLY
fmt_speed "$up"; ul=$REPLY
fmt_total "$tx2"; ul_total=$REPLY
tooltip+="\\n$ICON_DOWN $dl   (received $dl_total)"
tooltip+="\\n$ICON_UP $ul   (sent $ul_total)"

printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$text" "$tooltip" "$class"
