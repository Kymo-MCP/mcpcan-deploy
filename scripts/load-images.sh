#!/bin/bash

# Load images from images directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/../images"

# Check if images directory exists
if [ ! -d "$IMAGES_DIR" ]; then
    echo "Error: Images directory not found: $IMAGES_DIR"
    exit 1
fi

# Check available container runtime and set load command
if command -v docker >/dev/null 2>&1; then
    RUNTIME="docker"
    LOAD_CMD="docker load"
elif command -v crictl >/dev/null 2>&1; then
    RUNTIME="crictl"
    LOAD_CMD="crictl load"
elif command -v k3s >/dev/null 2>&1 && command -v ctr >/dev/null 2>&1; then
    RUNTIME="k3s"
    LOAD_CMD="k3s ctr images import"
elif command -v ctr >/dev/null 2>&1; then
    RUNTIME="containerd"
    LOAD_CMD="ctr -n k8s.io images import"
elif command -v nerdctl >/dev/null 2>&1; then
    RUNTIME="nerdctl"
    LOAD_CMD="nerdctl load"
elif command -v podman >/dev/null 2>&1; then
    RUNTIME="podman"
    LOAD_CMD="podman load"
elif command -v microk8s >/dev/null 2>&1; then
    RUNTIME="microk8s"
    LOAD_CMD="microk8s ctr image import"
elif command -v minikube >/dev/null 2>&1; then
    RUNTIME="minikube"
    LOAD_CMD="minikube image load"
else
    echo "Error: No supported container runtime found"
    echo "Supported runtimes: docker, crictl, k3s, containerd, nerdctl, podman, microk8s, minikube"
    exit 1
fi

echo "Using container runtime: $RUNTIME"
echo "Loading images from: $IMAGES_DIR"

# Initialize counters
loaded_count=0
failed_count=0

# Process all .tar and .tar.gz files in images directory
for image_file in "$IMAGES_DIR"/*.tar "$IMAGES_DIR"/*.tar.gz; do
    # Skip if no matching files
    [ ! -f "$image_file" ] && continue
    
    filename=$(basename "$image_file")
    echo "Processing: $filename"
    
    # Extract image name and tag from filename
    # Remove .tar or .tar.gz extension
    image_name_tag="${filename%.tar.gz}"
    image_name_tag="${image_name_tag%.tar}"
    
    # Replace : with _ if it was encoded in filename
    image_name_tag="${image_name_tag//_/:}"
    
    echo "  Image: $image_name_tag"
    
    # Load the image based on runtime
    case "$RUNTIME" in
        "docker")
            if docker load -i "$image_file"; then
                echo "  ✓ Successfully loaded: $image_name_tag"
                ((loaded_count++))
            else
                echo "  ✗ Failed to load: $image_name_tag"
                ((failed_count++))
            fi
            ;;
        "crictl")
            # For crictl, handle compressed files
            if [[ "$image_file" == *.tar.gz ]]; then
                if gunzip -c "$image_file" | crictl load; then
                    echo "  ✓ Successfully loaded: $image_name_tag"
                    ((loaded_count++))
                else
                    echo "  ✗ Failed to load: $image_name_tag"
                    ((failed_count++))
                fi
            else
                if crictl load -i "$image_file"; then
                    echo "  ✓ Successfully loaded: $image_name_tag"
                    ((loaded_count++))
                else
                    echo "  ✗ Failed to load: $image_name_tag"
                    ((failed_count++))
                fi
            fi
            ;;
        "k3s")
            if k3s ctr images import "$image_file"; then
                echo "  ✓ Successfully loaded: $image_name_tag"
                ((loaded_count++))
            else
                echo "  ✗ Failed to load: $image_name_tag"
                ((failed_count++))
            fi
            ;;
        "containerd")
            if ctr -n k8s.io images import "$image_file"; then
                echo "  ✓ Successfully loaded: $image_name_tag"
                ((loaded_count++))
            else
                echo "  ✗ Failed to load: $image_name_tag"
                ((failed_count++))
            fi
            ;;
        "nerdctl")
            if nerdctl load -i "$image_file"; then
                echo "  ✓ Successfully loaded: $image_name_tag"
                ((loaded_count++))
            else
                echo "  ✗ Failed to load: $image_name_tag"
                ((failed_count++))
            fi
            ;;
        "podman")
            if podman load -i "$image_file"; then
                echo "  ✓ Successfully loaded: $image_name_tag"
                ((loaded_count++))
            else
                echo "  ✗ Failed to load: $image_name_tag"
                ((failed_count++))
            fi
            ;;
        "microk8s")
            if microk8s ctr image import "$image_file"; then
                echo "  ✓ Successfully loaded: $image_name_tag"
                ((loaded_count++))
            else
                echo "  ✗ Failed to load: $image_name_tag"
                ((failed_count++))
            fi
            ;;
        "minikube")
            # For minikube, we need to load from file differently
            if [[ "$image_file" == *.tar.gz ]]; then
                # Extract and load
                temp_tar="/tmp/$(basename "$image_file" .gz)"
                if gunzip -c "$image_file" > "$temp_tar" && minikube image load "$temp_tar"; then
                    echo "  ✓ Successfully loaded: $image_name_tag"
                    ((loaded_count++))
                    rm -f "$temp_tar"
                else
                    echo "  ✗ Failed to load: $image_name_tag"
                    ((failed_count++))
                    rm -f "$temp_tar"
                fi
            else
                if minikube image load "$image_file"; then
                    echo "  ✓ Successfully loaded: $image_name_tag"
                    ((loaded_count++))
                else
                    echo "  ✗ Failed to load: $image_name_tag"
                    ((failed_count++))
                fi
            fi
            ;;
        *)
            echo "  ✗ Unsupported runtime: $RUNTIME"
            ((failed_count++))
            ;;
    esac
    
    echo ""
done

# Summary
echo "=== Load Summary ==="
echo "Successfully loaded: $loaded_count images"
echo "Failed to load: $failed_count images"

if [ $failed_count -gt 0 ]; then
    echo "Some images failed to load. Please check the errors above."
    exit 1
else
    echo "All images loaded successfully!"
fi
