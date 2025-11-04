#!/bin/bash

workdir=${WORKDIR:-/tmp/apisix}
target=${TARGET:-/etc/apisix/conf.d}
filename=${FILENAME:-/apisix.yaml}
interval="${INTERVAL:-5s}"
replace="${REPLACE:-true}"
merged_file=/tmp/merged.yaml
pull=false

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
    log error 写入配置出错 "{username: ${USERNAME}, password: ${PASSWORD}}"
  fi
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
    git clone "${REMOTE}" "${workdir}" > /dev/null 2>&1 # 不显示输出
    pull=true
  fi

  if [ "${pull}" = true ]; then
    mkdir -p "$(dirname ${merged_file})" > /dev/null 2>&1
    touch ${merged_file}

    log info 合并配置文件 "{dir: ${workdir}}"

    extensions=("yaml" "yml" "json")
    find_args=()
    for ext in "${extensions[@]}"; do
      if [[ ${#find_args[@]} -gt 0 ]]; then
          find_args+=("-o")
      fi
      find_args+=("-name" "*.${ext}")
    done

    while IFS= read -r -d '' path; do
      log debug 发现配置文件 "${path}"
      if [[ "$filename" == *.json ]]; then
        found_files+=("--input-format=json" "${path}")
      else
        found_files+=("--input-format=yaml" "${path}")
      fi
    done < <(find "${workdir}" -type f \( "${find_args[@]}" \) -print0)

    # 文件处理
    expression=". as \$item ireduce ({}; . *+ \$item)"
    expression="${expression} | .routes += .route | del(.route)" # 合并路由
    expression="${expression} | .upstreams += .upstream | del(.upstream)" # 合并上游
    expression="${expression} | .ssls += .ssl | del(.ssl)" # 合并证书
    if yq --prettyPrint --output-format=yaml eval-all "${expression}" "${found_files[@]}" > ${merged_file};then
      log info 配置文件合并成功 "{filename: ${merged_file}}"
    fi

    if yq --exit-status 'tag == "!!map" or tag == "!!seq"' "${merged_file}" >/dev/null; then
      config_file="${target}/${filename}"
      if [ "${replace}" = true ]; then
        log info 配置文件格式正确，替换新的配置 "{to: ${config_file}, from: ${merged_file}}"
        echo "#END" >> "${merged_file}"
        cat "${merged_file}" > "${config_file}" # 写入文件内容
      fi
    else
      log error 配置文件格式不正确 "new_file: $(cat ${merged_file})"
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
