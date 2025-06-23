#!/bin/bash

# Backup Script for OpenShift VPC Automation
# Creates a zip backup of all output directories and important files

set -euo pipefail

# Default values
DEFAULT_VPC_OUTPUT_DIR="./vpc-output"
DEFAULT_BASTION_OUTPUT_DIR="./bastion-output"
DEFAULT_OPENSHIFT_INSTALL_DIR="./openshift-install"
DEFAULT_LOGS_DIR="./logs"
DEFAULT_CLUSTER_NAME="my-cluster"
DEFAULT_BACKUP_DIR="./backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Backup Script for OpenShift VPC Automation"
    echo "Creates a zip backup of all output directories and important files"
    echo ""
    echo "Options:"
    echo "  --vpc-output-dir        VPC output directory (default: $DEFAULT_VPC_OUTPUT_DIR)"
    echo "  --bastion-output-dir    Bastion output directory (default: $DEFAULT_BASTION_OUTPUT_DIR)"
    echo "  --openshift-install-dir OpenShift installation directory (default: $DEFAULT_OPENSHIFT_INSTALL_DIR)"
    echo "  --logs-dir              Logs directory (default: $DEFAULT_LOGS_DIR)"
    echo "  --cluster-name          Cluster name for backup naming (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --backup-dir            Directory to save backup (default: $DEFAULT_BACKUP_DIR)"
    echo "  --include-configs       Include install-config.yaml and backups"
    echo "  --include-ssh-keys      Include SSH key files (.pem)"
    echo "  --exclude-logs          Exclude log files to reduce backup size"
    echo "  --dry-run               Show what would be backed up without creating backup"
    echo "  --help                  Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --dry-run                    # Preview what will be backed up"
    echo "  $0 --cluster-name my-cluster    # Create backup for specific cluster"
    echo "  $0 --include-ssh-keys           # Include SSH keys in backup"
    echo "  $0 --exclude-logs               # Exclude logs to reduce size"
}

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if directory exists and has content
check_directory() {
    local dir="$1"
    local description="$2"
    
    if [[ -d "$dir" ]]; then
        local file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
        if [[ $file_count -gt 0 ]]; then
            print_info "Found $description: $dir ($file_count files)"
            return 0
        else
            print_info "Found empty $description: $dir"
            return 0
        fi
    else
        print_info "No $description found: $dir"
        return 1
    fi
}

# Function to create backup
create_backup() {
    local dry_run="$1"
    
    print_info "Creating backup..."
    
    # Create backup directory
    if [[ ! -d "$BACKUP_DIR" ]]; then
        if [[ "$dry_run" == "yes" ]]; then
            print_info "DRY RUN: Would create backup directory: $BACKUP_DIR"
        else
            mkdir -p "$BACKUP_DIR"
            print_success "Created backup directory: $BACKUP_DIR"
        fi
    fi
    
    # Generate backup filename with timestamp
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_filename="${CLUSTER_NAME}-backup-${timestamp}.zip"
    local backup_path="$BACKUP_DIR/$backup_filename"
    
    # Create temporary directory for backup contents
    local temp_dir=$(mktemp -d)
    local backup_contents=()
    
    print_info "Preparing backup contents..."
    
    # Add directories to backup
    local dirs=(
        "$VPC_OUTPUT_DIR"
        "$BASTION_OUTPUT_DIR"
        "$OPENSHIFT_INSTALL_DIR"
    )
    
    # Add logs directory if not excluded
    if [[ "$EXCLUDE_LOGS" != "yes" ]]; then
        dirs+=("$LOGS_DIR")
    fi
    
    # Copy directories to temp location
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local dir_name=$(basename "$dir")
            local temp_subdir="$temp_dir/$dir_name"
            
            if [[ "$dry_run" == "yes" ]]; then
                print_info "DRY RUN: Would copy directory: $dir -> $temp_subdir"
            else
                cp -r "$dir" "$temp_subdir"
                print_success "Copied directory: $dir"
            fi
            backup_contents+=("$dir_name")
        fi
    done
    
    # Add config files if requested
    if [[ "$INCLUDE_CONFIGS" == "yes" ]]; then
        local config_files=(
            "install-config.yaml"
            "install-config.yaml.backup.*"
        )
        
        for pattern in "${config_files[@]}"; do
            for file in $pattern; do
                if [[ -f "$file" ]]; then
                    if [[ "$dry_run" == "yes" ]]; then
                        print_info "DRY RUN: Would copy config file: $file"
                    else
                        cp "$file" "$temp_dir/"
                        print_success "Copied config file: $file"
                    fi
                    backup_contents+=("$file")
                fi
            done
        done
    fi
    
    # Add SSH keys if requested
    if [[ "$INCLUDE_SSH_KEYS" == "yes" ]]; then
        local ssh_keys=(
            "${CLUSTER_NAME}-key.pem"
            "${CLUSTER_NAME}-bastion-key.pem"
        )
        
        for key in "${ssh_keys[@]}"; do
            if [[ -f "$key" ]]; then
                if [[ "$dry_run" == "yes" ]]; then
                    print_info "DRY RUN: Would copy SSH key: $key"
                else
                    cp "$key" "$temp_dir/"
                    print_success "Copied SSH key: $key"
                fi
                backup_contents+=("$key")
            fi
        done
        
        # Also add any .pem files
        for pem_file in *.pem; do
            if [[ -f "$pem_file" ]]; then
                if [[ "$dry_run" == "yes" ]]; then
                    print_info "DRY RUN: Would copy SSH key: $pem_file"
                else
                    cp "$pem_file" "$temp_dir/"
                    print_success "Copied SSH key: $pem_file"
                fi
                backup_contents+=("$pem_file")
            fi
        done
    fi
    
    # Create backup manifest
    if [[ "$dry_run" != "yes" ]]; then
        cat > "$temp_dir/backup-manifest.txt" <<EOF
OpenShift VPC Automation Backup
===============================

Backup created: $(date)
Cluster name: $CLUSTER_NAME
Backup filename: $backup_filename

Contents:
$(printf "  - %s\n" "${backup_contents[@]}")

Configuration:
- VPC Output Dir: $VPC_OUTPUT_DIR
- Bastion Output Dir: $BASTION_OUTPUT_DIR
- OpenShift Install Dir: $OPENSHIFT_INSTALL_DIR
- Logs Dir: $LOGS_DIR
- Include Configs: $INCLUDE_CONFIGS
- Include SSH Keys: $INCLUDE_SSH_KEYS
- Exclude Logs: $EXCLUDE_LOGS

Important files in this backup:
- VPC configuration and outputs
- Bastion host information
- OpenShift installation files
- SSH keys (if included)
- Configuration files (if included)
- Logs (if not excluded)

To restore from this backup:
1. Extract the zip file
2. Copy the directories back to their original locations
3. Ensure SSH keys have correct permissions (chmod 400 *.pem)
4. Update any scripts that reference these paths

Security Note:
- SSH keys are included in this backup
- Store this backup file securely
- Consider encrypting the backup if it contains sensitive information
EOF
    fi
    
    # Create zip file
    if [[ "$dry_run" == "yes" ]]; then
        print_info "DRY RUN: Would create backup: $backup_path"
        print_info "DRY RUN: Backup would contain:"
        for item in "${backup_contents[@]}"; do
            echo "  - $item"
        done
    else
        local orig_dir=$(pwd)
        cd "$temp_dir"
        if zip -r "$orig_dir/$backup_path" .; then
            cd "$orig_dir"
            # Get backup size
            local backup_size=$(du -h "$backup_path" | cut -f1)
            print_success "Backup created successfully!"
            print_info "Backup file: $backup_path"
            print_info "Backup size: $backup_size"
            print_info "Backup contents:"
            for item in "${backup_contents[@]}"; do
                echo "  - $item"
            done
        else
            cd "$orig_dir"
            print_error "Failed to create zip file: $backup_path"
            print_error "Please check if you have write permissions to $BACKUP_DIR"
            return 1
        fi
    fi
    
    # Cleanup temp directory
    if [[ "$dry_run" != "yes" ]]; then
        rm -rf "$temp_dir"
    fi
    
    return 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vpc-output-dir)
            VPC_OUTPUT_DIR="$2"
            shift 2
            ;;
        --bastion-output-dir)
            BASTION_OUTPUT_DIR="$2"
            shift 2
            ;;
        --openshift-install-dir)
            OPENSHIFT_INSTALL_DIR="$2"
            shift 2
            ;;
        --logs-dir)
            LOGS_DIR="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --include-configs)
            INCLUDE_CONFIGS="yes"
            shift
            ;;
        --include-ssh-keys)
            INCLUDE_SSH_KEYS="yes"
            shift
            ;;
        --exclude-logs)
            EXCLUDE_LOGS="yes"
            shift
            ;;
        --dry-run)
            DRY_RUN="yes"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set default values
VPC_OUTPUT_DIR=${VPC_OUTPUT_DIR:-$DEFAULT_VPC_OUTPUT_DIR}
BASTION_OUTPUT_DIR=${BASTION_OUTPUT_DIR:-$DEFAULT_BASTION_OUTPUT_DIR}
OPENSHIFT_INSTALL_DIR=${OPENSHIFT_INSTALL_DIR:-$DEFAULT_OPENSHIFT_INSTALL_DIR}
LOGS_DIR=${LOGS_DIR:-$DEFAULT_LOGS_DIR}
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
BACKUP_DIR=${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}
INCLUDE_CONFIGS=${INCLUDE_CONFIGS:-no}
INCLUDE_SSH_KEYS=${INCLUDE_SSH_KEYS:-no}
EXCLUDE_LOGS=${EXCLUDE_LOGS:-no}
DRY_RUN=${DRY_RUN:-no}

# Check if zip is available
if ! command -v zip &> /dev/null; then
    print_error "zip command is not available. Please install zip to create backups."
    exit 1
fi

# Main execution
echo "📦 OpenShift VPC Automation Backup Script"
echo "========================================="
echo ""
echo "📋 Configuration:"
echo "   VPC Output Dir: $VPC_OUTPUT_DIR"
echo "   Bastion Output Dir: $BASTION_OUTPUT_DIR"
echo "   OpenShift Install Dir: $OPENSHIFT_INSTALL_DIR"
echo "   Logs Dir: $LOGS_DIR"
echo "   Cluster Name: $CLUSTER_NAME"
echo "   Backup Dir: $BACKUP_DIR"
echo "   Include Configs: $INCLUDE_CONFIGS"
echo "   Include SSH Keys: $INCLUDE_SSH_KEYS"
echo "   Exclude Logs: $EXCLUDE_LOGS"
echo "   Dry Run: $DRY_RUN"
echo ""

# Check what will be backed up
print_info "Checking for files and directories to backup..."

found_items=0

# Check directories
check_directory "$VPC_OUTPUT_DIR" "VPC output directory" && found_items=$((found_items + 1))
check_directory "$BASTION_OUTPUT_DIR" "bastion output directory" && found_items=$((found_items + 1))
check_directory "$OPENSHIFT_INSTALL_DIR" "OpenShift installation directory" && found_items=$((found_items + 1))

if [[ "$EXCLUDE_LOGS" != "yes" ]]; then
    check_directory "$LOGS_DIR" "logs directory" && found_items=$((found_items + 1))
fi

# Check config files
if [[ "$INCLUDE_CONFIGS" == "yes" ]]; then
    for pattern in "install-config.yaml" "install-config.yaml.backup.*"; do
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                print_info "Found config file: $file"
                found_items=$((found_items + 1))
            fi
        done
    done
fi

# Check SSH keys
if [[ "$INCLUDE_SSH_KEYS" == "yes" ]]; then
    for key in "${CLUSTER_NAME}-key.pem" "${CLUSTER_NAME}-bastion-key.pem"; do
        if [[ -f "$key" ]]; then
            print_info "Found SSH key: $key"
            found_items=$((found_items + 1))
        fi
    done
    
    for pem_file in *.pem; do
        if [[ -f "$pem_file" ]]; then
            print_info "Found SSH key: $pem_file"
            found_items=$((found_items + 1))
        fi
    done
fi

if [[ $found_items -eq 0 ]]; then
    print_warning "No files or directories found to backup"
    echo ""
    echo "💡 Tips:"
    echo "  - Run create-vpc.sh, create-bastion.sh, or deploy-openshift.sh first"
    echo "  - Use --include-configs to backup configuration files"
    echo "  - Use --include-ssh-keys to backup SSH keys"
    exit 0
fi

echo ""
print_info "Found $found_items items to backup"

# Create backup
create_backup "$DRY_RUN"

echo ""
if [[ "$DRY_RUN" == "yes" ]]; then
    print_success "Dry run completed - no backup was actually created"
else
    print_success "Backup completed successfully!"
fi

echo ""
echo "💡 Tips:"
echo "  - Use --dry-run to preview what will be backed up"
echo "  - Use --include-configs to backup configuration files"
echo "  - Use --include-ssh-keys to backup SSH keys"
echo "  - Use --exclude-logs to reduce backup size"
echo "  - Store backup files securely, especially if they contain SSH keys"
echo "  - Consider encrypting backups with sensitive information" 