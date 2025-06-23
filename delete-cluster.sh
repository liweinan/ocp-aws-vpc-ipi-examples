#!/bin/bash

# OpenShift Cluster Deletion Script
# Simple wrapper for openshift-install destroy cluster

set -euo pipefail

# Default values
DEFAULT_INSTALL_DIR="./openshift-install"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --install-dir         Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --force               Skip confirmation prompts"
    echo "  --dry-run             Show what would be deleted without actually deleting"
    echo "  --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Delete cluster in default install dir"
    echo "  $0 --install-dir ./my-cluster         # Delete cluster in specific directory"
    echo "  $0 --dry-run                          # Show what would be deleted"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --force)
            FORCE="yes"
            shift
            ;;
        --dry-run)
            DRY_RUN="yes"
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Set default values if not provided
INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
FORCE=${FORCE:-no}
DRY_RUN=${DRY_RUN:-no}

# Display script header
echo "🚀 OpenShift Cluster Deletion Script"
echo "====================================="
echo ""

# Check if installation directory exists
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "❌ Error: Installation directory not found: $INSTALL_DIR"
    exit 1
fi

# Check if install-config.yaml exists
if [[ ! -f "$INSTALL_DIR/install-config.yaml" ]]; then
    echo "❌ Error: install-config.yaml not found in $INSTALL_DIR"
    echo "This directory may not contain a valid OpenShift installation"
    exit 1
fi

echo "📋 Configuration:"
echo "  Installation Directory: $INSTALL_DIR"
echo "  Force Mode: $FORCE"
echo "  Dry Run: $DRY_RUN"
echo ""

# Perform deletion based on mode
if [[ "$DRY_RUN" == "yes" ]]; then
    echo "🔍 DRY RUN MODE - No resources will be deleted"
    echo ""
    echo "Would run: openshift-install destroy cluster --dir=$INSTALL_DIR"
    echo ""
    echo "To actually delete the cluster, run without --dry-run"
    exit 0
fi

# Confirm deletion
if [[ "$FORCE" != "yes" ]]; then
    echo "⚠️  This will permanently delete the OpenShift cluster and all associated AWS resources!"
    echo "Installation directory: $INSTALL_DIR"
    echo ""
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deletion cancelled"
        exit 0
    fi
fi

# Change to installation directory
cd "$INSTALL_DIR"

# Perform deletion
echo "🚀 Starting cluster deletion..."
echo "⏳ This process may take 10-20 minutes..."
echo ""

if ! openshift-install destroy cluster; then
    echo "❌ Cluster deletion failed"
    echo ""
    echo "Check the logs above for specific error messages"
    exit 1
fi

echo ""
echo "✅ Cluster deletion completed successfully!"
echo ""
echo "Note: The installation directory $INSTALL_DIR still contains:"
echo "  - Log files (for troubleshooting)"
echo "  - Backup files (if any)"
echo "  - OpenShift installer binary"
echo ""
echo "You can manually delete the directory if no longer needed:"
echo "  rm -rf $INSTALL_DIR" 