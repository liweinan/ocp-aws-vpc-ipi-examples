# Bastion Host Connection Script

The `connect-bastion.sh` script automates the process of connecting to the bastion host, including setting proper SSH key permissions and optionally copying kubeconfig files.

## 🚀 Quick Start

```bash
# Make script executable
chmod +x connect-bastion.sh

# Basic connection to bastion host
./connect-bastion.sh

# Connect and copy kubeconfig automatically
./connect-bastion.sh --copy-kubeconfig

# Connect and setup OpenShift environment
./connect-bastion.sh --setup-environment

# Full automation: copy kubeconfig and setup environment
./connect-bastion.sh --copy-kubeconfig --setup-environment
```

## 📋 Features

- **Automatic SSH key permission setup** (`chmod 600`)
- **File validation** - checks for required bastion files
- **Kubeconfig copying** - automatically copies kubeconfig to bastion
- **Environment setup** - loads OpenShift environment and tests cluster connection
- **Error handling** - provides helpful error messages and suggestions

## 🔧 Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--bastion-output-dir` | Directory containing bastion output files | `./bastion-output` |
| `--cluster-name` | Cluster name for bastion identification | `my-cluster` |
| `--copy-kubeconfig` | Copy kubeconfig to bastion after connection | `false` |
| `--setup-environment` | Load OpenShift environment after connection | `false` |
| `--help` | Display help message | - |

## 📊 Usage Examples

### Example 1: Basic Connection
```bash
./connect-bastion.sh
```

This will:
1. Check for required bastion files
2. Set proper SSH key permissions
3. Connect to the bastion host interactively

### Example 2: Copy Kubeconfig and Connect
```bash
./connect-bastion.sh --copy-kubeconfig
```

This will:
1. Check for required bastion files
2. Set proper SSH key permissions
3. Copy kubeconfig from `./openshift-install/auth/kubeconfig` to bastion
4. Connect to the bastion host interactively

### Example 3: Setup Environment (Non-interactive)
```bash
./connect-bastion.sh --setup-environment
```

This will:
1. Check for required bastion files
2. Set proper SSH key permissions
3. Load OpenShift environment on bastion
4. Test cluster connection
5. Display cluster information
6. Exit (no interactive session)

### Example 4: Full Automation
```bash
./connect-bastion.sh --copy-kubeconfig --setup-environment
```

This will:
1. Check for required bastion files
2. Set proper SSH key permissions
3. Copy kubeconfig to bastion
4. Load OpenShift environment
5. Test cluster connection
6. Display cluster information
7. Exit (no interactive session)

## 🔍 What the Script Does

### File Validation
The script checks for these required files:
- `./bastion-output/{cluster-name}-bastion-key.pem` - SSH private key
- `./bastion-output/bastion-instance-id` - Bastion instance ID
- `./bastion-output/bastion-public-ip` - Bastion public IP address

### SSH Key Permissions
Automatically sets proper permissions:
```bash
chmod 600 ./bastion-output/{cluster-name}-bastion-key.pem
```

### Kubeconfig Copying
If `--copy-kubeconfig` is used, copies:
```bash
scp -i {ssh-key} ./openshift-install/auth/kubeconfig ec2-user@{bastion-ip}:~/openshift/
```

### Environment Setup
If `--setup-environment` is used, runs on bastion:
```bash
source /home/ec2-user/openshift/env.sh
export KUBECONFIG=~/openshift/kubeconfig
oc get nodes
oc get clusteroperators
```

## 🛠️ Integration with Other Scripts

This script works seamlessly with the other scripts in this project:

```bash
# Complete workflow example
./create-vpc.sh --cluster-name my-cluster                    # Create VPC
./deploy-openshift.sh                                        # Deploy cluster
./create-bastion.sh --cluster-name my-cluster                # Create bastion
./connect-bastion.sh --copy-kubeconfig --setup-environment   # Connect and setup
```

## 🆘 Troubleshooting

### Common Issues

#### 1. Missing Bastion Files
**Error**: `Missing required bastion files`

**Solution**:
```bash
# Run create-bastion.sh first
./create-bastion.sh --cluster-name my-cluster
```

#### 2. SSH Key Permission Issues
**Error**: `Permission denied (publickey)`

**Solution**:
The script automatically sets permissions, but you can manually fix:
```bash
chmod 600 ./bastion-output/my-cluster-bastion-key.pem
```

#### 3. Kubeconfig Not Found
**Error**: `kubeconfig not found at ./openshift-install/auth/kubeconfig`

**Solution**:
```bash
# Ensure OpenShift cluster is deployed
./deploy-openshift.sh

# Or copy kubeconfig manually
scp -i ./bastion-output/my-cluster-bastion-key.pem \
  /path/to/kubeconfig \
  ec2-user@<bastion-ip>:~/openshift/
```

#### 4. Cluster Connection Fails
**Error**: `Could not connect to OpenShift cluster`

**Solution**:
1. Check if cluster is running: `oc get nodes`
2. Verify kubeconfig is correct
3. Check bastion can reach cluster (security groups)

### Manual Steps (if script fails)

```bash
# 1. Set SSH key permissions
chmod 600 ./bastion-output/my-cluster-bastion-key.pem

# 2. Connect to bastion
ssh -i ./bastion-output/my-cluster-bastion-key.pem ec2-user@<bastion-ip>

# 3. Load environment
source /home/ec2-user/openshift/env.sh

# 4. Copy kubeconfig (from local machine)
scp -i ./bastion-output/my-cluster-bastion-key.pem \
  ./openshift-install/auth/kubeconfig \
  ec2-user@<bastion-ip>:~/openshift/

# 5. Set kubeconfig and test
export KUBECONFIG=~/openshift/kubeconfig
oc get nodes
```

## 🔐 Security Notes

- SSH key permissions are automatically set to 600 (user read/write only)
- The script validates all required files before attempting connection
- Kubeconfig copying uses secure SCP protocol
- Environment setup runs in a controlled manner on the bastion host

## 💡 Tips

1. **Use `--setup-environment` for automation**: Perfect for scripts and CI/CD
2. **Use `--copy-kubeconfig` for convenience**: Automatically copies your kubeconfig
3. **Check cluster status first**: Use `--setup-environment` to verify cluster health
4. **Keep bastion files safe**: The script validates file existence but doesn't protect against deletion

## 📁 File Locations

- **SSH Key**: `./bastion-output/{cluster-name}-bastion-key.pem`
- **Bastion Info**: `./bastion-output/bastion-*.txt`
- **Kubeconfig Source**: `./openshift-install/auth/kubeconfig`
- **Bastion Workspace**: `/home/ec2-user/openshift/` 