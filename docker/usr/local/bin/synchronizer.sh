#!/bin/bash

workdir=${WORKDIR:-/tmp/apisix}
branch=${BRANCH:-main}
target=${TARGET:-/etc/apisix/conf.d}
filename=${FILENAME:-/apisix.yaml}
interval="${INTERVAL:-5s}"
replace="${REPLACE:-true}"
merged_file=/tmp/merged.yaml

pull=false
code=0

# 嵌入脚本
set -euo pipefail
# shellcheck source=https://gitea.com/storezhang/script/raw/branch/main/core/log.sh
source <(wget -q -O - https://gitea.com/storezhang/script/raw/branch/main/core/log.sh)

cleanup() {
    log info 系统退出 "cause: system"
    exit 0
}
trap cleanup SIGINT SIGTERM

log debug 启动配置加载器 "{target: ${target}, interval: ${interval}}"

if [[ "${REMOTE}" =~ ^https?:// ]]; then
    if [ -n "${USERNAME}" ] && [ -n "${PASSWORD}" ]; then
        tee "${HOME}/.netrc" <<-EOF > /dev/null
default login ${USERNAME} password ${PASSWORD}
EOF
    else
        code=1
        log error 写入配置出错 "{username: ${USERNAME}, password: ${PASSWORD}}"
    fi
fi
if [ ${code} -ne 0 ]; then
    exit ${code}
fi

log info 创建工作目录 "{dir: ${workdir}}"
mkdir -p "${workdir}"

while true; do
    if git -C "${workdir}" rev-parse --git-dir > /dev/null 2>&1; then
        git -C "${workdir}" fetch > /dev/null 2>&1

        if git -C "${workdir}" status | grep -q "Your branch is behind"; then # 检查是否需要 pull
            log info 更新代码 "dir: ${workdir}"
            if git -C "${workdir}" pull > /dev/null 2>&1; then # 不显示输出
                pull=true
                log info 代码更新成功 "dir: ${workdir}"
            fi
        fi
    else
        log info 检出代码 "{dir: ${workdir}, remote: ${REMOTE}}"
        git clone --branch "${branch}" "${REMOTE}" "${workdir}" > /dev/null 2>&1 # 不显示输出
        pull=true
    fi

    if [ "${pull}" = true ]; then
        mkdir -p "$(dirname ${merged_file})" > /dev/null 2>&1
        touch ${merged_file}

        log info 合并配置文件 "{dir: ${workdir}}"
        if msg=$(gateway apisix config --path="${workdir}" merge --output=${merged_file} 2>&1); then
            log info 配置文件合并成功 "{filename: ${merged_file}}"
            config_file="${target}/${filename}"
            if [ "${replace}" = true ]; then
                log info 配置文件格式正确，替换新的配置 "{to: ${config_file}, from: ${merged_file}}"
                echo "#END" >> "${merged_file}"
                cat "${merged_file}" > "${config_file}" # 写入文件内容
            fi
        else
            code=3
            log info 配置文件合并失败 "{filename: ${merged_file}, message: ${msg}}"
        fi
        if [ ${code} -ne 0 ]; then
            exit ${code}
        fi

        pull=false
    fi

    # 清理文件
    log info 清理配置文件 "{filepath: ${merged_file}}"
    rm -rf "${merged_file}"

    # 等待指定间隔
    log debug 等待重新加载配置文件 "interval: ${interval}"
    sleep "${interval}"
done
