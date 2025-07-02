# Disconnected Cluster Improvements

## Overview

This document describes improvements made to the disconnected OpenShift cluster deployment scripts based on successful manual image synchronization experience.

## Key Improvements

### 1. Infrastructure Changes

#### Bastion Host Storage Increase
- **File**: `01-create-infrastructure.sh`
- **Change**: Increased bastion host storage from 20GB to 50GB
- **Reason**: Original 20GB was insufficient for OpenShift image synchronization
- **Line**: `--block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":50}}]'`

### 2. Image Synchronization Strategy

#### New CI Registry-Based Script
- **File**: `05-sync-images-ci.sh` (new)
- **Source**: Based on successful manual sync from `registry.ci.openshift.org/ocp/4.19.2`
- **Advantages**:
  - Uses proven working image sources
  - Includes all successfully tested core components
  - Proper CI authentication handling
  - Comprehensive error handling and retry logic

#### Core Images Successfully Synchronized
```
registry.ci.openshift.org/ocp/4.19.2:cli
registry.ci.openshift.org/ocp/4.19.2:installer
registry.ci.openshift.org/ocp/4.19.2:machine-config-operator
registry.ci.openshift.org/ocp/4.19.2:cluster-version-operator
registry.ci.openshift.org/ocp/4.19.2:etcd
registry.ci.openshift.org/ocp/4.19.2:hyperkube
registry.ci.openshift.org/ocp/4.19.2:oauth-server
registry.ci.openshift.org/ocp/4.19.2:oauth-proxy
registry.ci.openshift.org/ocp/4.19.2:console
registry.ci.openshift.org/ocp/4.19.2:haproxy-router
registry.ci.openshift.org/ocp/4.19.2:coredns
```

### 3. Install Configuration Updates

#### Updated Image Content Sources
- **File**: `07-prepare-install-config.sh`
- **Change**: Updated `imageContentSources` to include CI registry mappings
- **New mappings**:
  ```yaml
  imageContentSources:
  - mirrors:
    - localhost:5000/openshift
    source: registry.ci.openshift.org/ocp/4.19.2
  - mirrors:
    - localhost:5000/openshift
    source: registry.ci.openshift.org/openshift
  - mirrors:
    - localhost:5000/openshift
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - localhost:5000/openshift
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
  ```

## Manual Sync Success Summary

### Registry Status Before Improvements
- Only 3 repositories: `openshift/apicast-gateway`, `openshift/cli`, `openshift/ocp-release`
- Insufficient for OpenShift installation

### Registry Status After Improvements
- 13 repositories with complete core components
- All critical OpenShift services available
- Successful image pulls and pushes verified

### Successful Sync Process
1. **CI Authentication**: `oc login --token=<TOKEN> --server=https://api.ci.l2s4.p1.openshiftapps.com:6443`
2. **Registry Login**: `podman login -u="$CI_USER" -p="$CI_TOKEN" registry.ci.openshift.org`
3. **Image Discovery**: Found `registry.ci.openshift.org/ocp/4.19.2` with 188+ components
4. **Selective Sync**: Synced 11 core components successfully
5. **Local Registry**: All images pushed to `localhost:5000/openshift/`

## Usage Instructions

### Using the Improved Scripts

1. **Create Infrastructure** (with 50GB bastion storage):
   ```bash
   ./01-create-infrastructure.sh --cluster-name my-cluster
   ```

2. **Setup Bastion and Registry**:
   ```bash
   ./02-create-bastion.sh
   ./03-copy-credentials.sh
   ./04-setup-mirror-registry.sh
   ```

3. **Sync Images** (using new CI-based script):
   ```bash
   ./05-sync-images-ci.sh
   ```

4. **Prepare Installation** (with updated image sources):
   ```bash
   ./07-prepare-install-config.sh
   ```

5. **Install Cluster**:
   ```bash
   ./08-install-cluster.sh
   ```

### Prerequisites for CI Registry Access

1. **OpenShift CI Cluster Access**: You need valid credentials for the CI cluster
2. **Token Authentication**: Obtain token from CI cluster web console
3. **Network Access**: Bastion host must reach `registry.ci.openshift.org`

### Verification Commands

Check registry contents:
```bash
curl -k -u admin:admin123 https://localhost:5000/v2/_catalog | jq .
```

Verify specific images:
```bash
curl -k -u admin:admin123 https://localhost:5000/v2/openshift/cli/tags/list
```

## Troubleshooting

### Common Issues and Solutions

1. **Disk Space Full**:
   - Solution: Use 50GB bastion host (implemented in 01 script)
   - Cleanup: `podman system prune -a -f`

2. **CI Authentication Failure**:
   - Check: `oc whoami` returns valid user
   - Re-login: Use fresh token from CI cluster console

3. **Image Pull Failures**:
   - Verify: CI registry connectivity
   - Check: Image exists in `registry.ci.openshift.org/ocp/4.19.2`

4. **Registry Push Failures**:
   - Check: Local registry is running (`podman ps`)
   - Verify: Registry authentication (`curl -k -u admin:admin123 https://localhost:5000/v2/_catalog`)

## Performance Optimizations

1. **Parallel Processing**: Consider parallel image pulls for faster sync
2. **Selective Sync**: Only sync required components for specific use cases
3. **Incremental Sync**: Skip already synced images in subsequent runs
4. **Storage Management**: Regular cleanup of unused images

## Future Improvements

1. **Automated Token Refresh**: Handle CI token expiration
2. **Version Detection**: Auto-detect latest stable OpenShift version
3. **Health Checks**: Verify image integrity after sync
4. **Backup Strategy**: Implement registry backup before major syncs

## Validation Results

### Pre-Improvement
- ❌ Installation failures due to missing images
- ❌ Insufficient storage space (97% utilization)
- ❌ Only 3 repositories in local registry

### Post-Improvement
- ✅ 13 repositories with core OpenShift components
- ✅ Sufficient storage space (66% utilization after cleanup)
- ✅ All critical images available for installation
- ✅ Proven sync process with CI registry

## Conclusion

These improvements address the core issues identified during manual testing:
1. **Storage constraints** resolved with 50GB bastion host
2. **Image availability** solved with CI registry-based sync
3. **Authentication handling** improved with proper CI token usage
4. **Configuration accuracy** enhanced with correct image source mappings

The new approach provides a reliable foundation for disconnected OpenShift cluster deployments. 