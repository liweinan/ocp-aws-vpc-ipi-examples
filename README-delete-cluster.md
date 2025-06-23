# OpenShift Cluster Deletion Script

This script provides a simple wrapper for `openshift-install destroy cluster` with basic safety features.

## Features

- **Simple wrapper** for `openshift-install destroy cluster`
- **Confirmation prompt** to prevent accidental deletion
- **Dry-run mode** to preview the command
- **Basic validation** of installation directory and files

## Usage

### Basic Usage

```bash
# Delete cluster in default installation directory
./delete-cluster.sh

# Delete cluster in specific directory
./delete-cluster.sh --install-dir ./my-cluster
```

### Advanced Options

```bash
# Dry run - show what command would be run
./delete-cluster.sh --dry-run

# Force deletion - skip confirmation prompts
./delete-cluster.sh --force
```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--install-dir` | Installation directory containing the cluster | `./openshift-install` |
| `--force` | Skip confirmation prompts | `false` |
| `--dry-run` | Show what command would be run | `false` |
| `--help` | Display help message | - |

## Examples

### Example 1: Safe Deletion with Confirmation

```bash
./delete-cluster.sh --install-dir ./my-openshift-cluster
```

This will:
1. Validate the installation directory exists
2. Check for `install-config.yaml`
3. Prompt for confirmation
4. Run `openshift-install destroy cluster`

### Example 2: Dry Run to Preview

```bash
./delete-cluster.sh --dry-run
```

This will show what command would be run without actually executing it.

### Example 3: Force Deletion (Use with Caution)

```bash
./delete-cluster.sh --force
```

This will delete the cluster without confirmation prompts.

## What Happens

The script simply runs:
```bash
cd <install-dir>
openshift-install destroy cluster
```

The `openshift-install destroy cluster` command handles:
- Deleting all AWS resources (EC2 instances, load balancers, security groups, etc.)
- Cleaning up network configurations
- Removing cluster-specific resources

## Prerequisites

- **OpenShift installer** in PATH
- **AWS credentials** configured (via AWS CLI, environment variables, or AWS_PROFILE)
- **Valid installation directory** with `install-config.yaml`

## Troubleshooting

### Common Issues

#### 1. Installation Directory Not Found

**Error**: `Installation directory not found: /path/to/dir`

**Solution**:
```bash
# Check if the directory exists
ls -la /path/to/dir

# Use the correct path
./delete-cluster.sh --install-dir /correct/path
```

#### 2. install-config.yaml Not Found

**Error**: `install-config.yaml not found in /path/to/dir`

**Solution**:
```bash
# Check if the file exists
ls -la /path/to/dir/install-config.yaml

# Ensure you're using the correct installation directory
```

#### 3. Cluster Deletion Fails

**Error**: `Cluster deletion failed`

**Solution**:
1. Check the logs for specific error messages
2. Ensure you have sufficient AWS permissions
3. Try running the deletion manually:
   ```bash
   cd /path/to/install/dir
   openshift-install destroy cluster
   ```

## Integration with Other Scripts

This script works with the other scripts in this project:

```bash
# Complete workflow example
./create-vpc.sh                    # Create VPC
./deploy-openshift.sh              # Deploy cluster
./backup.sh                        # Create backup
./delete-cluster.sh --dry-run      # Preview deletion
./delete-cluster.sh                # Delete cluster
./delete-vpc.sh                    # Delete VPC
```

## Manual Deletion

If you prefer to delete manually without the script:

```bash
# Navigate to installation directory
cd openshift-install

# Delete the cluster
openshift-install destroy cluster
```

## Security Notes

- The script requires AWS credentials with sufficient permissions
- Cluster deletion is permanent and cannot be undone
- Always review what will be deleted before proceeding 