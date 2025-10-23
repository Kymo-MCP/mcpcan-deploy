#!/bin/bash

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
IMAGES_DIR="$PROJECT_DIR/images"
VALUES_FILE="$PROJECT_DIR/helm/values.yaml"

# Create images directory if not exists
mkdir -p "$IMAGES_DIR"

# Extract images from values.yaml
extract_images() {
    local images=()
    
    # Extract MySQL image
    local mysql_image=$(grep -A 5 "mysql:" "$VALUES_FILE" | grep "image:" | awk '{print $2}' | tr -d '"')
    if [ -n "$mysql_image" ]; then
        images+=("$mysql_image")
    fi
    
    # Extract Redis image  
    local redis_image=$(grep -A 5 "redis:" "$VALUES_FILE" | grep "image:" | awk '{print $2}' | tr -d '"')
    if [ -n "$redis_image" ]; then
        images+=("$redis_image")
    fi
    
    # Extract Ingress Controller image
    local ingress_image=$(grep -A 10 "ingressController:" "$VALUES_FILE" | grep "image:" | awk '{print $2}' | tr -d '"')
    if [ -n "$ingress_image" ]; then
        images+=("$ingress_image")
    fi
    
    # Extract application images based on global registry
    local registry=$(grep "registry:" "$VALUES_FILE" | head -1 | awk '{print $2}' | tr -d '"')
    local tag=$(grep "tag:" "$VALUES_FILE" | head -1 | awk '{print $2}' | tr -d '"')
    
    if [ -n "$registry" ] && [ -n "$tag" ]; then
        # Add common application images
        images+=("${registry}/mcp-authz:${tag}")
        images+=("${registry}/mcp-gateway:${tag}")
        images+=("${registry}/mcp-web:${tag}")
        images+=("${registry}/mcp-api:${tag}")
    fi
    
    # Print unique images
    printf '%s\n' "${images[@]}" | sort -u
}

# Export single image to tar file
export_image() {
    local image="$1"
    local image_name=$(echo "$image" | sed 's/[\/:]/_/g')
    local tar_file="$IMAGES_DIR/${image_name}.tar"
    
    echo "Exporting image: $image"
    
    # Pull image if not exists locally
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo "Pulling image: $image"
        docker pull "$image"
    fi
    
    # Save image to tar file
    echo "Saving to: $tar_file"
    docker save "$image" -o "$tar_file"
    
    # Compress tar file to save space
    echo "Compressing: ${tar_file}.gz"
    gzip -f "$tar_file"
    
    echo "Exported: ${tar_file}.gz"
}

# Main execution
main() {
    echo "=== Helm Images Export Tool ==="
    echo "Project: $PROJECT_DIR"
    echo "Images Directory: $IMAGES_DIR"
    echo "Values File: $VALUES_FILE"
    echo ""
    
    # Check if values.yaml exists
    if [ ! -f "$VALUES_FILE" ]; then
        echo "Error: values.yaml not found at $VALUES_FILE"
        exit 1
    fi
    
    # Check if docker is available
    if ! command -v docker >/dev/null 2>&1; then
        echo "Error: Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Extract images from values.yaml
    echo "Extracting images from values.yaml..."
    local images=($(extract_images))
    
    if [ ${#images[@]} -eq 0 ]; then
        echo "No images found in values.yaml"
        exit 1
    fi
    
    echo "Found ${#images[@]} images:"
    printf '  - %s\n' "${images[@]}"
    echo ""
    
    # Export each image
    for image in "${images[@]}"; do
        export_image "$image"
        echo ""
    done
    
    echo "=== Export Complete ==="
    echo "All images exported to: $IMAGES_DIR"
    echo "Files:"
    ls -lh "$IMAGES_DIR"/*.tar.gz 2>/dev/null || echo "No tar.gz files found"
}

# Run main function
main "$@"