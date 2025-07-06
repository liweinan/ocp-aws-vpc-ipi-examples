#!/usr/bin/env bash
# This library provides an `image_for` helper function which can get the
# pull spec for a specific image in a release.

# 使用本地 registry mirror 而不是直接访问外部 registry
RELEASE_IMAGE_DIGEST="localhost:5000/openshift/ocp/release:4.19"

image_for() {
    # 直接使用本地 registry，避免网络访问
    echo "localhost:5000/openshift/${1}"
}
