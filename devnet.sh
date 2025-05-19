#!/bin/bash

# Read the total number of validators from the user or use a default value of 4
read -p "Enter the total number of validators (default: 4): " total_validators
total_validators=${total_validators:-4}

# Read the total number of clients from the user or use a default value of 2
read -p "Enter the total number of clients (default: 2): " total_clients
total_clients=${total_clients:-2}

# Read the network ID from user or use a default value of 1
read -p "Enter the network ID (mainnet = 0, testnet = 1, canary = 2) (default: 1): " network_id
network_id=${network_id:-1}

# Ask the user if they want to run 'cargo install --locked --path .' or use a pre-installed binary
read -p "Do you want to run 'cargo install --locked --path .' to build the binary? (y/n, default: y): " build_binary
build_binary=${build_binary:-y}

# Ask the user whether to clear the existing ledger history
read -p "Do you want to clear the existing ledger history? (y/n, default: n): " clear_ledger
clear_ledger=${clear_ledger:-n}

if [[ $build_binary == "y" ]]; then
  # Ask the user if they want to enable validator telemetry
  read -p "Do you want to enable validator telemetry? (y/n, default: y): " enable_telemetry
  enable_telemetry=${enable_telemetry:-y}

  # Ask the user for additional crate features (comma-separated)
  read -p "Enter crate features to enable (comma separated, default: none): " crate_features
  crate_features=${crate_features:-}

  # Build command
  build_cmd="cargo install --locked --path ."

  # Add the telemetry feature if requested
  if [[ $enable_telemetry == "y" ]]; then
    build_cmd+=" --features telemetry"
  fi

  # Add any extra features if provided
  if [[ -n $crate_features ]]; then
    # If telemetry was also enabled, append with a comma separator
    if [[ $enable_telemetry == "y" ]]; then
      build_cmd+=",${crate_features}"
    else
      build_cmd+=" --features ${crate_features}"
    fi
  fi

  # Run it
  echo "Running build command: \"$build_cmd\""
  eval "$build_cmd" || exit 1
fi

# Clear the ledger logs for each validator if the user chooses to clear ledger
if [[ $clear_ledger == "y" ]]; then
  clean_processes=()
  for ((index = 0; index < $((total_validators + total_clients)); index++)); do
    snarkos clean --network $network_id --dev $index &
    clean_processes+=($!)
  done
  for process_id in "${clean_processes[@]}"; do
    wait "$process_id"
  done
fi

# Create a timestamp-based directory for log files
log_dir=".logs-$(date +"%Y%m%d%H%M%S")"
mkdir -p "$log_dir"

# Create a new tmux session named "devnet"
tmux new-session -d -s "devnet" -n "window0"

# Get the tmux's base-index for windows
index_offset="$(tmux show-option -gv base-index)"
index_offset=${index_offset:-0}

# Generate validator indices and spawn windows
validator_indices=($(seq 0 $((total_validators - 1))))
for validator_index in "${validator_indices[@]}"; do
  log_file="$log_dir/validator-$validator_index.log"
  if [ "$validator_index" -eq 0 ]; then
    tmux send-keys -t "devnet:window$validator_index" \
      "snarkos start --nodisplay --network $network_id --dev $validator_index --allow-external-peers --dev-num-validators $total_validators --validator --logfile $log_file --metrics" C-m
  else
    window_index=$((validator_index + index_offset))
    tmux new-window -t "devnet:$window_index" -n "window$validator_index"
    tmux send-keys -t "devnet:window$validator_index" \
      "snarkos start --nodisplay --network $network_id --dev $validator_index --allow-external-peers --dev-num-validators $total_validators --validator --logfile $log_file" C-m
  fi
done

# Spawn client windows if needed
if [ "$total_clients" -ne 0 ]; then
  client_indices=($(seq 0 $((total_clients - 1))))
  for client_index in "${client_indices[@]}"; do
    log_file="$log_dir/client-$client_index.log"
    window_index=$((client_index + total_validators + index_offset))
    tmux new-window -t "devnet:$window_index" -n "window-$window_index"
    tmux send-keys -t "devnet:window-$window_index" \
      "snarkos start --nodisplay --network $network_id --dev $window_index --dev-num-validators $total_validators --client --logfile $log_file" C-m
  done
fi

# Attach to the tmux session
tmux attach-session -t "devnet"
