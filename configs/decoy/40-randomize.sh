#!/bin/sh
# Generates a randomized index.html from template on each container start.
# This prevents fingerprinting across MoaV deployments.

TEMPLATE="/template/index.html.template"
OUTPUT="/usr/share/nginx/html/index.html"

if [ ! -f "$TEMPLATE" ]; then
    echo "40-randomize: template not found, skipping"
    exit 0
fi

# Seed random from /dev/urandom
SEED=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')

# --- Pick random values ---

# Titles
set -- \
    "Backgammon" \
    "Backgammon Online" \
    "Classic Backgammon" \
    "Board Game" \
    "Nard Game" \
    "Tavla" \
    "Tawla Online" \
    "Backgammon Board" \
    "Play Backgammon" \
    "BG Game"
shift $(( SEED % $# ))
TITLE="$1"

# Headings
SEED=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
set -- \
    "BACKGAMMON" \
    "CLASSIC BACKGAMMON" \
    "BOARD GAME" \
    "NARD" \
    "TAVLA" \
    "PLAY BACKGAMMON" \
    "BACKGAMMON ONLINE" \
    "TABLE GAME"
shift $(( SEED % $# ))
HEADING="$1"

# Footers
SEED=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
set -- \
    "Click a piece to select, then click destination to move" \
    "Select a checker and click where to move it" \
    "Tap a piece, then tap the target point" \
    "Pick up a piece and place it on a valid point" \
    "Click to select, click again to move" \
    "Choose your piece, then choose your destination"
shift $(( SEED % $# ))
FOOTER="$1"

# Color themes - each is a coherent set
SEED=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
THEME=$(( SEED % 8 ))

case $THEME in
    0) # Classic green
        BG_COLOR="#1a1a2e"; ACCENT="#c8a96e"; FRAME="#2d1810"; BORDER="#5a3a1a"
        FELT="#2e6b45"; TRI_D="#1a3d28"; TRI_L="#c8a96e" ;;
    1) # Midnight blue
        BG_COLOR="#151928"; ACCENT="#d4a855"; FRAME="#1c1412"; BORDER="#4a3520"
        FELT="#1e4a6e"; TRI_D="#12304a"; TRI_L="#d4a855" ;;
    2) # Dark mahogany
        BG_COLOR="#1e1a1a"; ACCENT="#b8955a"; FRAME="#3a1c10"; BORDER="#6b3a1a"
        FELT="#2a5e3e"; TRI_D="#1a3828"; TRI_L="#b8955a" ;;
    3) # Forest
        BG_COLOR="#161e1a"; ACCENT="#cba260"; FRAME="#281a0e"; BORDER="#523818"
        FELT="#2a6840"; TRI_D="#18402a"; TRI_L="#cba260" ;;
    4) # Warm charcoal
        BG_COLOR="#1c1a20"; ACCENT="#d9b068"; FRAME="#2a1810"; BORDER="#5e3e1e"
        FELT="#326e48"; TRI_D="#1e4230"; TRI_L="#d9b068" ;;
    5) # Slate
        BG_COLOR="#181c22"; ACCENT="#c0a058"; FRAME="#221614"; BORDER="#4e3418"
        FELT="#286040"; TRI_D="#183a26"; TRI_L="#c0a058" ;;
    6) # Deep purple
        BG_COLOR="#1a1826"; ACCENT="#d0a860"; FRAME="#2c1a14"; BORDER="#583a1c"
        FELT="#2c6842"; TRI_D="#1c3e2c"; TRI_L="#d0a860" ;;
    7) # Navy
        BG_COLOR="#141a24"; ACCENT="#ccaa5e"; FRAME="#261810"; BORDER="#54381a"
        FELT="#2a6644"; TRI_D="#1a3c2a"; TRI_L="#ccaa5e" ;;
esac

# Random comment (changes file hash)
RAND_COMMENT=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')

# --- Generate output ---
sed \
    -e "s|%%TITLE%%|${TITLE}|g" \
    -e "s|%%HEADING%%|${HEADING}|g" \
    -e "s|%%FOOTER%%|${FOOTER}|g" \
    -e "s|%%BG_COLOR%%|${BG_COLOR}|g" \
    -e "s|%%ACCENT_COLOR%%|${ACCENT}|g" \
    -e "s|%%BOARD_FRAME%%|${FRAME}|g" \
    -e "s|%%BOARD_BORDER%%|${BORDER}|g" \
    -e "s|%%FELT_COLOR%%|${FELT}|g" \
    -e "s|%%TRI_DARK%%|${TRI_D}|g" \
    -e "s|%%TRI_LIGHT%%|${TRI_L}|g" \
    -e "s|%%RANDOM_COMMENT%%|${RAND_COMMENT}|g" \
    "$TEMPLATE" > "$OUTPUT"

echo "40-randomize: generated decoy site (theme=$THEME, title='$TITLE')"
