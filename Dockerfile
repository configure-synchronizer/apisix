FROM mikefarah/yq:4.48.1 AS yq


FROM ccr.ccs.tencentyun.com/dockerat/alpine:3.20.1 AS builder
# 复制文件
COPY --from=yq /usr/bin/yq /docker/usr/bin/yq
COPY docker /docker



# 打包真正的镜像
FROM ccr.ccs.tencentyun.com/dockerat/alpine:3.20.1


LABEL author="storezhang<华寅>" \
    email="storezhang@gmail.com" \
    qq="160290688" \
    wechat="storezhang" \
    description="网关配置刷新插件"

# 所需环境变量
ENV USERNAME ""
ENV PASSWORD ""
ENV REPLACE true
ENV WORKDIR /tmp/apisix
ENV TARGET /etc/apisix/conf.d
ENV FILENAME apisix.yaml

RUN set -ex \
    \
    \
    \
    && apk update \
    \
    # 安装Git工具 \
    && apk --no-cache add git openssh-client \
    \
    \
    \
    && rm -rf /var/cache/apk/*

# 一次性复制所有文件，充分利用构建缓存，同时减少镜像层级
COPY --from=builder /docker /

# 启动命令
ENTRYPOINT ["/usr/local/bin/synchronizer.sh"]