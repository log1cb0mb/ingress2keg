#!/bin/bash
# Helper script to apply YAML files with environment variable substitution
# Usage: source apply-config.sh && apply_yaml <file_or_directory>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

# Load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "❌ Configuration file not found: $CONFIG_FILE"
        echo ""
        echo "Please create config.env from the example:"
        echo "  cp config.env.example config.env"
        echo "  # Edit config.env with your environment values"
        exit 1
    fi
    
    # Source the config file
    set -a  # automatically export all variables
    source "$CONFIG_FILE"
    set +a
    
    # Validate required variables
    if [[ -z "$DOMAIN" || "$DOMAIN" == "your-cluster.your-domain.com" ]]; then
        echo "❌ DOMAIN not configured in config.env"
        exit 1
    fi
    
    if [[ -z "$CLUSTER_ISSUER" ]]; then
        echo "❌ CLUSTER_ISSUER not configured in config.env"
        exit 1
    fi
    
    echo "✅ Configuration loaded:"
    echo "   DOMAIN: $DOMAIN"
    echo "   CLUSTER_ISSUER: $CLUSTER_ISSUER"
    echo ""
}

# Apply a single YAML file with variable substitution
apply_yaml() {
    local file="$1"
    local action="${2:-apply}"  # apply or delete
    
    if [[ ! -f "$file" ]]; then
        echo "❌ File not found: $file"
        return 1
    fi
    
    # Substitute environment variables and apply
    envsubst '${DOMAIN} ${CLUSTER_ISSUER}' < "$file" | kubectl "$action" -f -
}

# Apply all YAML files in a directory
apply_dir() {
    local dir="$1"
    local action="${2:-apply}"
    
    if [[ ! -d "$dir" ]]; then
        echo "❌ Directory not found: $dir"
        return 1
    fi
    
    for file in "$dir"/*.yaml "$dir"/*.yml; do
        [[ -f "$file" ]] || continue
        echo "📄 ${action^}ing: $(basename "$file")"
        apply_yaml "$file" "$action"
    done
}

# Delete using YAML file with variable substitution
delete_yaml() {
    apply_yaml "$1" "delete"
}

# Delete all YAML files in a directory
delete_dir() {
    apply_dir "$1" "delete"
}

# Export functions for use in other scripts
export -f apply_yaml apply_dir delete_yaml delete_dir
