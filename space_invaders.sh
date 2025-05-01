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

SAUCER_ROW=0; SAUCER_COL=-1; SAUCER_VISIBLE=0

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

countdown() {
  for ((i=3; i>0; i--)); do  # Countdown for 3 seconds
    tput cup $((ROWS / 2)) $((COLS / 2 - 10))
    echo -n "Starting level $LEVEL in $i seconds..."
    sleep 1
  done
  tput cup $((ROWS / 2)) $((COLS / 2 - 10))
  echo -n "                              "  # Clear the countdown message
}

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
  if (( SAUCER_VISIBLE )); then
    screen[$SAUCER_ROW]="${screen[$SAUCER_ROW]:0:$SAUCER_COL}~~~O~~~${screen[$SAUCER_ROW]:$((SAUCER_COL+7))}"
  fi
  tput cup 0 0
  printf "%s\n" "${screen[@]}"
  echo -n "Enemies:${#ENEMY_ROWS[@]} Score:$SCORE Level:$LEVEL (i/p move, a fire, SPACE to pause)"
}

read_input() {
  IFS= read -rsn1 -t 0.1 k  # Increased timeout for better input detection
  if (( PAUSED == 0 )); then
    case "$k" in
      i) ((PLAYER_COL > 0)) && ((PLAYER_COL--)) ;;  # Move left
      p) ((PLAYER_COL < COLS - 1)) && ((PLAYER_COL++)) ;;  # Move right
      a)  # Fire a bullet
        BULLET_ROWS+=($((PLAYER_ROW - 1)))  # Add new bullet row
        BULLET_COLS+=($PLAYER_COL)         # Add new bullet column
        ;;
      q) exit ;;  # Quit the game
      " ") PAUSED=1 ;;  # Pause the game
    esac
  else
    [[ $k == " " ]] && PAUSED=0  # Unpause the game
  fi
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
    r=${BULLET_ROWS[i]}
    c=${BULLET_COLS[i]}
    ((r--))  # Move the bullet up

    # Remove the bullet if it goes out of bounds
    if ((r < 1)); then
      continue
    fi

    # Check for collisions with enemies
    local hit=0
    for j in "${!ENEMY_ROWS[@]}"; do
      if ((r == ENEMY_ROWS[j] && c == ENEMY_COLS[j])); then
        # Remove the enemy and mark the bullet as hit
        unset 'ENEMY_ROWS[j]' 'ENEMY_COLS[j]'
        SCORE=$((SCORE + 10))
        hit=1
        break
      fi
    done

    # Add the bullet to the new array if it didn't hit anything
    if ((hit == 0)); then
      nr+=($r)
      nc+=($c)
    fi
  done

  # Update the bullet arrays
  BULLET_ROWS=("${nr[@]}")
  BULLET_COLS=("${nc[@]}")
}

move_enemy_bullets() {
  local nr=() nc=()
  for i in "${!EBULLET_ROWS[@]}"; do
    r=${EBULLET_ROWS[i]}
    c=${EBULLET_COLS[i]}
    ((r++))  # Move the bullet down

    # Check for collisions with the player
    if ((r == PLAYER_ROW && c == PLAYER_COL)); then
      game_over
      return
    fi

    # Check for collisions with bunkers
    if [[ ${BUNKER_MAP["$r,$c"]+x} ]]; then
      unset BUNKER_MAP["$r,$c"]
      continue
    fi

    # Add the bullet to the new array if it hasn't hit anything
    if ((r < ROWS - 1)); then
      nr+=($r)
      nc+=($c)
    fi
  done

  # Update the enemy bullet arrays
  EBULLET_ROWS=("${nr[@]}")
  EBULLET_COLS=("${nc[@]}")
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

check_level_completion() {
  if (( ${#ENEMY_ROWS[@]} == 0 )); then
    # Display level complete message
    tput cup $((ROWS / 2)) $((COLS / 2 - 7))
    echo -n "LEVEL COMPLETE!"
    sleep 2

    # Progress to next level
    LEVEL=$((LEVEL + 1))
    countdown  # Countdown before the next level
    reset_level
  fi
}

reset_level() {
  # Reset player and enemies for the new level
  PLAYER_COL=$((COLS / 2))
  ENEMY_ROWS=()
  ENEMY_COLS=()
  for r in {2..4}; do
    for c in {5..35..5}; do
      ENEMY_ROWS+=($r)
      ENEMY_COLS+=($c)
    done
  done
  BULLET_ROWS=()
  BULLET_COLS=()
  EBULLET_ROWS=()
  EBULLET_COLS=()
  update_bunker_positions
  set_level_params
}

game_over() {
  for _ in {1..5}; do
    tput cup $((ROWS / 2)) $((COLS / 2 - 7))
    echo -n "GAME OVER"
    sleep 0.4
    tput cup $((ROWS / 2)) $((COLS / 2 - 7))
    echo -n "         "
    sleep 0.4
  done
  tput cup $((ROWS / 2 + 1)) $((COLS / 2 - 10))
  echo -n "Press R to restart or Q to quit"
  while :; do
    IFS= read -rsn1 k
    case "$k" in
      r|R) reset_game; countdown; return ;;  # Restart the game
      q|Q) exit ;;  # Quit the game
    esac
  done
}

reset_game() {
  PLAYER_COL=$((COLS / 2))
  ENEMY_DIR=1
  SCORE=0
  LEVEL=1
  BULLET_ROWS=()
  BULLET_COLS=()
  EBULLET_ROWS=()
  EBULLET_COLS=()
  ENEMY_ROWS=()
  ENEMY_COLS=()
  for r in {2..4}; do
    for c in {5..35..5}; do
      ENEMY_ROWS+=($r)
      ENEMY_COLS+=($c)
    done
  done
  set_level_params
  update_bunker_positions
}

# Main loop
set_level_params
update_bunker_positions  # Initialize bunkers for the first run
countdown  # Countdown before the first level

while :; do
  read_input
  if ((PAUSED)); then
    pause_game
  fi
  draw
  move_bullets
  move_enemy_bullets
  ((TICK++))
  ((TICK % ENEMY_SPEED == 0)) && move_enemies  # Move enemies at intervals
  check_level_completion  # Check if level is complete
  sleep 0.03
done
