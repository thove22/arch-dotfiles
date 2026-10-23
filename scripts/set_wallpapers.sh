#!/bin/bash

WALLPAPER_DIR="$HOME/Pictures/Wallpapers/"
SLEEP_TIME=180

TRANSITIONS=(
    "wipe --transition-angle 30 --transition-bezier .7,0,.3,1"
    "wave --transition-wave 20,20 --transition-bezier .54,0,.34,.99"
    "grow --transition-pos 0.5,1.0 --transition-bezier .68,-.55,.27,1.55"
    "center --transition-bezier .25,.1,.25,1"
    "outer --transition-pos center --transition-bezier .54,0,.34,.99"
    "fade --transition-bezier .7,0,.3,1"
)

# Collect all images from directory instead of hardcoding paths
mapfile -t WALLPAPERS < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.webp" \))

if [ ${#WALLPAPERS[@]} -eq 0 ]; then
    echo "No wallpapers found in $WALLPAPER_DIR"
    exit 1
fi

# Shuffle array
shuffle() {
    local i j tmp
    for ((i = ${#WALLPAPERS[@]} - 1; i > 0; i--)); do
        j=$((RANDOM % (i + 1)))
        tmp="${WALLPAPERS[$i]}"
        WALLPAPERS[$i]="${WALLPAPERS[$j]}"
        WALLPAPERS[$j]="$tmp"
    done
}

while true; do
    shuffle
    for WALLPAPER in "${WALLPAPERS[@]}"; do
        # Pick a random transition
        TRANSITION="${TRANSITIONS[RANDOM % ${#TRANSITIONS[@]}]}"

        awww img "$WALLPAPER" \
            --transition-type $TRANSITION \
            --transition-step 90 \
            --transition-fps 60 \
            --transition-duration 1.5 
        sleep "$SLEEP_TIME"
    done
done
