#!/bin/bash

# 设置输出目录
OUTPUT_DIR="ci-operator/disconnected-cluster/bootstrap-scripts"
JSON_FILE="ci-operator/disconnected-cluster/bootstrap.ign.decoded.json"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

echo "开始提取bootstrap.ign中的脚本文件..."

# 获取所有/usr/local/bin/下的脚本文件路径
script_paths=$(jq -r '.storage.files[] | select(.path | startswith("/usr/local/bin/")) | .path' "$JSON_FILE")

# 遍历每个脚本文件
for script_path in $script_paths; do
    # 获取文件名（去掉路径）
    filename=$(basename "$script_path")
    
    echo "正在提取: $filename"
    
    # 提取base64内容并解码
    jq -r --arg path "$script_path" '.storage.files[] | select(.path == $path) | .contents.source' "$JSON_FILE" | \
    sed 's/^data:text\/plain;charset=utf-8;base64,//' | \
    base64 -d > "$OUTPUT_DIR/$filename"
    
    # 检查是否成功
    if [ $? -eq 0 ]; then
        echo "  ✓ 成功提取: $filename"
    else
        echo "  ✗ 提取失败: $filename"
    fi
done

# 提取其他重要文件
echo "正在提取其他重要文件..."

# 提取registries.conf
echo "正在提取: registries.conf"
jq -r --arg path "/etc/containers/registries.conf" '.storage.files[] | select(.path == $path) | .contents.source' "$JSON_FILE" | \
sed 's/^data:text\/plain;charset=utf-8;base64,//' | \
base64 -d > "$OUTPUT_DIR/registries.conf"

# 提取systemd服务文件
echo "正在提取systemd服务文件..."
systemd_files=$(jq -r '.storage.files[] | select(.path | startswith("/etc/systemd/system/")) | .path' "$JSON_FILE")

for service_path in $systemd_files; do
    filename=$(basename "$service_path")
    echo "正在提取: $filename"
    
    jq -r --arg path "$service_path" '.storage.files[] | select(.path == $path) | .contents.source' "$JSON_FILE" | \
    sed 's/^data:text\/plain;charset=utf-8;base64,//' | \
    base64 -d > "$OUTPUT_DIR/$filename"
done

# 提取systemd target文件
echo "正在提取systemd target文件..."
target_files=$(jq -r '.storage.files[] | select(.path | startswith("/etc/systemd/system/") and endswith(".target")) | .path' "$JSON_FILE")

for target_path in $target_files; do
    filename=$(basename "$target_path")
    echo "正在提取: $filename"
    
    jq -r --arg path "$target_path" '.storage.files[] | select(.path == $path) | .contents.source' "$JSON_FILE" | \
    sed 's/^data:text\/plain;charset=utf-8;base64,//' | \
    base64 -d > "$OUTPUT_DIR/$filename"
done

# 提取systemd generator文件
echo "正在提取systemd generator文件..."
generator_files=$(jq -r '.storage.files[] | select(.path | startswith("/etc/systemd/system-generators/")) | .path' "$JSON_FILE")

for generator_path in $generator_files; do
    filename=$(basename "$generator_path")
    echo "正在提取: $filename"
    
    jq -r --arg path "$generator_path" '.storage.files[] | select(.path == $path) | .contents.source' "$JSON_FILE" | \
    sed 's/^data:text\/plain;charset=utf-8;base64,//' | \
    base64 -d > "$OUTPUT_DIR/$filename"
done

# 提取配置文件
echo "正在提取配置文件..."
config_files=$(jq -r '.storage.files[] | select(.path | startswith("/etc/systemd/system.conf.d/")) | .path' "$JSON_FILE")

for config_path in $config_files; do
    filename=$(basename "$config_path")
    echo "正在提取: $filename"
    
    jq -r --arg path "$config_path" '.storage.files[] | select(.path == $path) | .contents.source' "$JSON_FILE" | \
    sed 's/^data:text\/plain;charset=utf-8;base64,//' | \
    base64 -d > "$OUTPUT_DIR/$filename"
done

# 提取Docker配置
echo "正在提取: docker-config.json"
jq -r --arg path "/root/.docker/config.json" '.storage.files[] | select(.path == $path) | .contents.source' "$JSON_FILE" | \
sed 's/^data:text\/plain;charset=utf-8;base64,//' | \
base64 -d > "$OUTPUT_DIR/docker-config.json"

# 提取profile配置
echo "正在提取: proxy.sh"
jq -r --arg path "/etc/profile.d/proxy.sh" '.storage.files[] | select(.path == $path) | .contents.source' "$JSON_FILE" | \
sed 's/^data:text\/plain;charset=utf-8;base64,//' | \
base64 -d > "$OUTPUT_DIR/proxy.sh"

# 提取motd
echo "正在提取: motd"
jq -r --arg path "/etc/motd" '.storage.files[] | select(.path == $path) | .contents.append[0].source' "$JSON_FILE" | \
sed 's/^data:text\/plain;charset=utf-8;base64,//' | \
base64 -d > "$OUTPUT_DIR/motd"

echo ""
echo "提取完成！文件保存在: $OUTPUT_DIR"
echo ""
echo "提取的文件列表:"
ls -la "$OUTPUT_DIR" 