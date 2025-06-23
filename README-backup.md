# Backup Script

The `backup.sh` script creates compressed backups of project files with various options for inclusion and exclusion.

## 🚀 Quick Start

```bash
# Make script executable
chmod +x backup.sh

# Create basic backup
./backup.sh

# Create backup with configurations and SSH keys
./backup.sh --include-configs --include-ssh-keys

# Create backup excluding logs
./backup.sh --exclude-logs

# Preview backup operations
./backup.sh --dry-run

# Create backup with custom name
./backup.sh --backup-name my-custom-backup
```

## 📋 Features

- **Flexible Content Selection**: Choose what to include/exclude
- **Compressed Archives**: Create zip files for easy storage
- **Timestamped Names**: Automatic timestamp-based naming
- **Dry Run Mode**: Preview operations without executing
- **Custom Naming**: Specify custom backup names
- **Progress Tracking**: Show backup progress and summary

## 🔧 Command Line Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--include-configs` | Include configuration files | `false` | No |
| `--include-ssh-keys` | Include SSH key files | `false` | No |
| `--exclude-logs` | Exclude log files | `false` | No |
| `--backup-name` | Custom backup name | Auto-generated | No |
| `--dry-run` | Preview operations without executing | `false` | No |
| `--help` | Display help message | N/A | No |

## 📦 Backup Content

### Always Included
- `vpc-output/` - VPC creation output directory
- `bastion-output/` - Bastion host output directory
- `openshift-install/` - OpenShift installation directory
- Script files (`.sh` files)
- README files
- Configuration templates (`.yaml` files)

### Optional Content
- **Configurations** (`--include-configs`): `install-config.yaml`, `pull-secret.json`
- **SSH Keys** (`--include-ssh-keys`): `*.pem` files
- **Logs** (excluded with `--exclude-logs`): `logs/` directory, `*.log` files

## 📊 Example Output

### Dry Run Mode
```
📦 Backup Script
================

📋 Configuration:
   Include Configs: yes
   Include SSH Keys: yes
   Exclude Logs: yes
   Backup Name: ocp-aws-vpc-ipi-examples-backup-2024-01-15-143022
   Dry Run: yes

ℹ️  DRY RUN MODE - No backup will be actually created

📁 Files to Include:
   - vpc-output/
   - bastion-output/
   - openshift-install/
   - *.sh files
   - *.md files
   - *.yaml files
   - install-config.yaml
   - pull-secret.json
   - *.pem files

📁 Files to Exclude:
   - logs/
   - *.log files
   - backup-*.zip

📊 Backup Summary
=================
ℹ️  DRY RUN COMPLETED - No backup was actually created

To create actual backup, run the script without --dry-run
```

### Actual Backup
```
📦 Backup Script
================

📋 Configuration:
   Include Configs: yes
   Include SSH Keys: yes
   Exclude Logs: yes
   Backup Name: ocp-aws-vpc-ipi-examples-backup-2024-01-15-143022
   Dry Run: no

📁 Creating Backup Archive
---------------------------
ℹ️  Adding vpc-output/ to backup...
ℹ️  Adding bastion-output/ to backup...
ℹ️  Adding openshift-install/ to backup...
ℹ️  Adding script files to backup...
ℹ️  Adding configuration files to backup...
ℹ️  Adding SSH key files to backup...
ℹ️  Creating zip archive...

✅ Backup created successfully: ocp-aws-vpc-ipi-examples-backup-2024-01-15-143022.zip

📊 Backup Summary
=================
✅ Backup file: ocp-aws-vpc-ipi-examples-backup-2024-01-15-143022.zip
✅ Size: 2.5 MB
✅ Contents: 45 files, 3 directories
✅ Excluded: logs/, *.log files

🎉 Backup completed successfully!
```

## 🔄 Usage Scenarios

### Development Environment Backup
```bash
# Basic backup for development
./backup.sh

# Backup with configurations
./backup.sh --include-configs
```

### Production Environment Backup
```bash
# Complete backup including SSH keys
./backup.sh --include-configs --include-ssh-keys

# Backup with custom name
./backup.sh --include-configs --include-ssh-keys --backup-name production-backup-2024-01-15
```

### Clean Backup (Exclude Logs)
```bash
# Backup without log files
./backup.sh --exclude-logs

# Complete clean backup
./backup.sh --include-configs --include-ssh-keys --exclude-logs
```

### Automated Backup
```bash
# Use in scripts or cron jobs
./backup.sh --include-configs --backup-name daily-backup-$(date +%Y%m%d)
```

## 📁 Backup File Structure

The backup zip file contains:

```
ocp-aws-vpc-ipi-examples-backup-2024-01-15-143022.zip
├── vpc-output/
│   ├── vpc-id
│   ├── private-subnet-ids
│   ├── public-subnet-ids
│   └── ...
├── bastion-output/
│   ├── bastion-instance-id
│   ├── bastion-public-ip
│   └── ...
├── openshift-install/
│   ├── install-config.yaml (if --include-configs)
│   ├── auth/
│   └── ...
├── *.sh files
├── *.md files
├── *.yaml files
├── pull-secret.json (if --include-configs)
└── *.pem files (if --include-ssh-keys)
```

## 🔄 Restore from Backup

To restore from a backup:

```bash
# Extract backup
unzip ocp-aws-vpc-ipi-examples-backup-2024-01-15-143022.zip

# Verify contents
ls -la

# Restore specific directories
cp -r vpc-output/ ./restored-vpc-output/
cp -r bastion-output/ ./restored-bastion-output/
cp -r openshift-install/ ./restored-openshift-install/
```

## ⚠️ Important Notes

### Security Considerations
- **SSH keys are sensitive** - Only include with `--include-ssh-keys` when needed
- **Pull secrets are sensitive** - Only include with `--include-configs` when needed
- **Secure storage** - Store backup files in a secure location
- **Access control** - Limit access to backup files containing sensitive data

### Backup Size
- **Basic backup**: ~1-5 MB
- **With configs**: ~1-10 MB
- **With SSH keys**: ~1-15 MB
- **Complete backup**: ~1-20 MB

### Storage Recommendations
- Use cloud storage (S3, Google Drive, etc.) for long-term storage
- Keep multiple backup versions
- Test backup restoration periodically
- Monitor backup storage costs

## 🆘 Troubleshooting

### Permission Issues
```bash
# Check file permissions
ls -la vpc-output/ bastion-output/ openshift-install/

# Fix permissions if needed
chmod -R 755 vpc-output/ bastion-output/ openshift-install/
```

### Disk Space Issues
```bash
# Check available disk space
df -h

# Clean up old backups
rm -f backup-*.zip

# Use exclude options to reduce size
./backup.sh --exclude-logs
```

### Zip Command Issues
```bash
# Check if zip is installed
which zip

# Install zip if needed (Ubuntu/Debian)
sudo apt-get install zip

# Install zip if needed (CentOS/RHEL)
sudo yum install zip
```

## 💡 Best Practices

### Regular Backups
```bash
# Daily backup script
#!/bin/bash
./backup.sh --include-configs --backup-name daily-backup-$(date +%Y%m%d)
```

### Before Major Changes
```bash
# Backup before VPC deletion
./backup.sh --include-configs --include-ssh-keys --backup-name pre-deletion-backup

# Backup before script updates
./backup.sh --backup-name pre-update-backup
```

### Backup Rotation
```bash
# Keep only last 7 daily backups
find . -name "daily-backup-*.zip" -mtime +7 -delete

# Keep only last 30 backups
find . -name "backup-*.zip" -mtime +30 -delete
```

## 🔄 Integration with Other Scripts

### Workflow Integration
```bash
# Backup before deployment
./backup.sh --include-configs --backup-name pre-deployment-backup

# Deploy OpenShift
./deploy-openshift.sh --cluster-name my-cluster --base-domain example.com

# Backup after deployment
./backup.sh --include-configs --include-ssh-keys --backup-name post-deployment-backup
```

### Cleanup Integration
```bash
# Backup before cleanup
./backup.sh --include-configs --include-ssh-keys

# Clean up environment
./cleanup.sh --clean-aws
```

## 📚 Related Documentation

- [Cleanup Script](README-cleanup.md) - Clean up files after backup
- [Delete VPC Scripts](README-delete-vpc.md) - Delete resources safely
- [AWS S3](https://docs.aws.amazon.com/s3/) - Cloud storage for backups
- [Zip Documentation](https://linux.die.net/man/1/zip) - Archive format details 