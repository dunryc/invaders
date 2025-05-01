#!/bin/bash

ROWS=20
COLS=40
PLAYER_ROW=$((ROWS - 2))
PLAYER_COL=$((COLS / 2))
ENEMY_DIR=1
SCORE=0
LEVEL=1
PAUSED=0  # Pause state

BULLET_ROWS=(); BULLET_COLS=()
EBULLET_ROWS=(); EBULLET_COLS=()
declare -A BUNKER_MAP

SAUCER_ROW=0
SAUCER_COL=-1  # -1 means the saucer is not visible
SAUCER_DIR=1  # Direction of the saucer (1 = right, -1 = left)
SAUCER_SPIN=0  # Current spin state (0 to 3)

ENEMY_ROWS=(); ENEMY_COLS=()
for r in {2..4}; do
  for c in {5..35..5}; do
    ENEMY_ROWS+=($r); ENEMY_COLS+=($c)
  done
done

# Terminal Configuration
tput civis
stty -echo -icanon time 0 min 0
trap "stty echo; tput cnorm; clear; exit" EXIT

# Functions

set_level_params() {
  ENEMY_SPEED=$((11 - LEVEL)); ((ENEMY_SPEED < 2)) && ENEMY_SPEED=2
  PLAYER_FIRE_COOLDOWN=$((11 - LEVEL)); ((PLAYER_FIRE_COOLDOWN < 2)) && PLAYER_FIRE_COOLDOWN=2
}

update_bunker_positions() {
  BUNKER_MAP=()
  local width=2 height=3 cols=(8 16 24 32)
  (( LEVEL >= 2 )) && cols=(6 14 22 30)
  (( LEVEL >= 3 )) && width=4
  for ((h=0; h<height; h++)); do
    for base in "${cols[@]}"; do
      for ((w=0; w<width; w++)); do
        r=$((17 - h)); c=$((base + w))
        BUNKER_MAP["$r,$c"]=1
      done
    done
  done
}

draw() {
  local screen=()
  for ((i=0;i<ROWS;i++)); do screen[i]=$(printf "%${COLS}s" " "); done
  screen[$PLAYER_ROW]="${screen[$PLAYER_ROW]:0:$PLAYER_COL}^${screen[$PLAYER_ROW]:$((PLAYER_COL+1))}"
  for key in "${!BUNKER_MAP[@]}"; do
    IFS=, read r c <<<"$key"
    screen[$r]="${screen[$r]:0:$c}#${screen[$r]:$((c+1))}"
  done
  for i in "${!ENEMY_ROWS[@]}"; do
    r=${ENEMY_ROWS[i]}; c=${ENEMY_COLS[i]}
    screen[$r]="${screen[$r]:0:$c}W${screen[$r]:$((c+1))}"
  done
  for i in "${!BULLET_ROWS[@]}"; do
    r=${BULLET_ROWS[i]}; c=${BULLET_COLS[i]}
    (( r>=0&&r<ROWS )) && screen[$r]="${screen[$r]:0:$c}|${screen[$r]:$((c+1))}"
  done
  for i in "${!EBULLET_ROWS[@]}"; do
    r=${EBULLET_ROWS[i]}; c=${EBULLET_COLS[i]}
    (( r>=0&&r<ROWS )) && screen[$r]="${screen[$r]:0:$c}v${screen[$r]:$((c+1))}"
  done

  # Draw the spinning saucer (if visible)
  if (( SAUCER_COL >= 0 )); then
    local spin_chars=("/" "-" "\\" "|")  # Spinning animation characters
    local spin_char=${spin_chars[$SAUCER_SPIN]}
    screen[$SAUCER_ROW]="${screen[$SAUCER_ROW]:0:$SAUCER_COL}$spin_char${screen[$SAUCER_ROW]:$((SAUCER_COL + 1))}"
  fi

  tput cup 0 0
  printf "%s\n" "${screen[@]}"
  echo -n "Enemies:${#ENEMY_ROWS[@]} Score:$SCORE Level:$LEVEL (i/p move, a fire, SPACE to pause)"
}

countdown() {
  for ((i=10; i>0; i--)); do
    tput cup $((ROWS / 2)) $((COLS / 2 - 5))
    echo -n "Starting in $i..."
    sleep 1
  done
  tput cup $((ROWS / 2)) $((COLS / 2 - 5))
  echo -n "               "  # Clear the countdown message
}

read_input() {
  IFS= read -rsn1 -t 0.05 key
  case "$key" in
    i) ((PLAYER_COL > 0)) && ((PLAYER_COL--)) ;;  # Move left
    p) ((PLAYER_COL < COLS - 1)) && ((PLAYER_COL++)) ;;  # Move right
    a) if (( FIRE_TICK == 0 )); then  # Fire a bullet
         BULLET_ROWS+=($((PLAYER_ROW - 1)))
         BULLET_COLS+=($PLAYER_COL)
         FIRE_TICK=$PLAYER_FIRE_COOLDOWN
       fi ;;
    q) exit ;;  # Quit the game
    " ") PAUSED=$((1 - PAUSED)) ;;  # Toggle pause state
  esac
}

pause_game() {
  tput cup $((ROWS / 2)) $((COLS / 2 - 12))
  echo -n "GAME PAUSED - Press SPACE to Resume"
  while (( PAUSED == 1 )); do
    read_input
  done
  tput clear
}

move_bullets() {
  local nr=() nc=()
  for i in "${!BULLET_ROWS[@]}"; do
    r=${BULLET_ROWS[i]}; c=${BULLET_COLS[i]}; ((r--))
    ((r<1)) && continue

    # Check if the bullet hits the saucer
    if (( r == SAUCER_ROW && c == SAUCER_COL )); then
      SCORE=$((SCORE + 10))  # Add 10 points
      SAUCER_COL=-1          # Remove the saucer
      continue
    fi

    for j in "${!ENEMY_ROWS[@]}"; do
      if ((r==ENEMY_ROWS[j]&&c==ENEMY_COLS[j])); then
        unset 'ENEMY_ROWS[j]' 'ENEMY_COLS[j]'; SCORE=$((SCORE+1)); r=-1
        break
      fi
    done
    ((r>=0)) && nr+=($r) && nc+=($c)
  done
  BULLET_ROWS=("${nr[@]}"); BULLET_COLS=("${nc[@]}")
}

move_enemy_bullets() {
  local nr=() nc=()
  for i in "${!EBULLET_ROWS[@]}"; do
    r=${EBULLET_ROWS[i]}; c=${EBULLET_COLS[i]}; ((r++))
    ((r==PLAYER_ROW&&c==PLAYER_COL)) && game_over && return
    if [[ ${BUNKER_MAP["$r,$c"]+x} ]]; then
      unset BUNKER_MAP["$r,$c"]; continue
    fi
    ((r<ROWS-1)) && nr+=($r) && nc+=($c)
  done
  EBULLET_ROWS=("${nr[@]}"); EBULLET_COLS=("${nc[@]}")
}

move_saucer() {
  if (( SAUCER_COL == -1 )); then
    # Randomly decide to show the saucer (1 in 200 chance per frame)
    (( RANDOM % 200 == 0 )) && SAUCER_COL=$((RANDOM % 2 == 0 ? 0 : COLS - 1)) && SAUCER_DIR=$((SAUCER_COL == 0 ? 1 : -1))
  else
    # Move the saucer
    SAUCER_COL=$((SAUCER_COL + SAUCER_DIR))
    (( SAUCER_COL < 0 || SAUCER_COL >= COLS )) && SAUCER_COL=-1  # Hide if it goes offscreen
    SAUCER_SPIN=$(((SAUCER_SPIN + 1) % 4))  # Update spin state
  fi
}

enemy_fire() {
  (( ${#ENEMY_ROWS[@]} == 0 )) && return  # No enemies, no fire

  for i in "${!ENEMY_ROWS[@]}"; do
    local diff=$(( ENEMY_COLS[i] - PLAYER_COL ))
    (( diff < 0 )) && diff=$(( -diff ))  # Absolute value

    if (( diff <= 5 )); then
      local fire_chance=$((20 - LEVEL)); ((fire_chance < 5)) && fire_chance=5
      if (( RANDOM % fire_chance == 0 )); then
        EBULLET_ROWS+=($((ENEMY_ROWS[i] + 1)))
        EBULLET_COLS+=($((ENEMY_COLS[i] + (RANDOM % 3 - 1))))  # Slight randomness in bullet column
      fi
    fi
  done
}

move_enemies() {
  local edge=0
  for c in "${ENEMY_COLS[@]}"; do
    ((c + ENEMY_DIR < 1 || c + ENEMY_DIR >= COLS - 1)) && edge=1 && break
  done
  for i in "${!ENEMY_COLS[@]}"; do
    if ((edge)); then
      ((ENEMY_ROWS[i]++))
      ((ENEMY_ROWS[i] >= PLAYER_ROW)) && game_over && return
    else
      ((ENEMY_COLS[i] += ENEMY_DIR))
    fi
  done
  ((edge)) && ENEMY_DIR=$((-ENEMY_DIR))
}

game_over() {
  for _ in {1..5}; do
    tput cup $((ROWS / 2)) $((COLS / 2 - 7))
    echo -n "GAME OVER"; sleep 0.4
    tput cup $((ROWS / 2)) $((COLS / 2 - 7))
    echo -n "         "; sleep 0.4
  done
  tput cup $((ROWS / 2 + 1)) $((COLS / 2 - 10))
  echo -n "Press R to restart or Q to quit"
  while :; do
    IFS= read -rsn1 k
    case "$k" in
      r|R) reset_game; return ;;  # Restart the game
      q|Q) exit ;;  # Quit the game
    esac
  done
}

reset_game() {
  PLAYER_COL=$((COLS / 2))
  ENEMY_DIR=1
  SCORE=0
  LEVEL=1
  BULLET_ROWS=(); BULLET_COLS=()
  EBULLET_ROWS=(); EBULLET_COLS=()
  ENEMY_ROWS=(); ENEMY_COLS=()
  for r in {2..4}; do
    for c in {5..35..5}; do
      ENEMY_ROWS+=($r); ENEMY_COLS+=($c)
    done
  done
  set_level_params
  update_bunker_positions
  FIRE_TICK=0
}

# Main loop
set_level_params
update_bunker_positions  # Initialize bunkers for the first run

countdown  # Add countdown before the game starts

while :; do
  read_input
  if (( PAUSED )); then
    pause_game
  fi
  draw
  move_bullets
  move_enemy_bullets
  move_saucer  # Move the saucer
  ((TICK++))
  ((TICK % ENEMY_SPEED == 0)) && move_enemies  # Move enemies at intervals
  ((TICK % 10 == 0)) && enemy_fire  # Enemies fire at regular intervals
  ((FIRE_TICK > 0)) && ((FIRE_TICK--))        # Decrement firing cooldown
  sleep 0.03  # Slightly slower loop for better input handling
done
