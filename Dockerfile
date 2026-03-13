# 运行阶段：直接使用 GoReleaser 产出的二进制，不在 Docker 中重复编译
FROM alpine:3.19

RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    libgcc \
    gpgme \
    lvm2

COPY sreg /usr/local/bin/sreg
RUN chmod +x /usr/local/bin/sreg

ENTRYPOINT ["/usr/local/bin/sreg"]
CMD ["--help"]
