#!/bin/sh

# build-config.sh
# Script to generate configuration files for MCPCan Docker Compose deployment.

set -e

# 1. Load Environment Variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found."
    exit 1
fi

CONFIG_DIR="./config"
CONFIG_TPL_DIR="./config-template"

# Function to backup existing config
backup_config() {
    if [ -d "$CONFIG_DIR" ]; then
        TIMESTAMP=$(date +"%Y%m%d%H%M%S")
        BACKUP_PATH="${CONFIG_DIR}-${TIMESTAMP}"
        echo "Backing up existing config directory to ${BACKUP_PATH}..."
        mv "$CONFIG_DIR" "$BACKUP_PATH"
    fi
}

# Function to generate config from templates
generate_config() {
    echo "Generating new configuration from templates..."
    
    if [ ! -d "$CONFIG_TPL_DIR" ]; then
        echo "Error: Config template directory $CONFIG_TPL_DIR not found."
        exit 1
    fi
    
    mkdir -p "$CONFIG_DIR"
    
    # Use envsubst to substitute variables in all files
    # We iterate through files in config-tpl
    for tpl_file in "$CONFIG_TPL_DIR"/*; do
        if [ -f "$tpl_file" ]; then
            filename=$(basename "$tpl_file")
            output_file="$CONFIG_DIR/$filename"
            
            # Exclude script files if any
            if [[ "$filename" == *.sh ]]; then
                continue
            fi

            echo "Processing $filename..."
            # Construct a string of variables to substitute
            # We assume the user wants to substitute ALL vars defined in .env
            # Using a simplified envsubst approach (requires gettext package usually, but alpine/sh often has basic support or we rely on host)
            # If envsubst is not available, we might need a fallback, but assuming standard linux/mac env.
            
            # Note: We strictly substitute only variables defined in .env to avoid breaking other shell syntax if present, 
            # but typically envsubst with no args substitutes all exported vars.
            envsubst < "$tpl_file" > "$output_file"
        fi
    done
}

# Main Execution Flow
echo "Starting configuration build process..."

# 1. Backup
backup_config

# 2. Generate
generate_config

echo "Configuration build completed successfully."
echo "You can now run 'docker-compose up -d' to start the services."
