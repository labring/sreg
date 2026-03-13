# 运行阶段：直接使用 GoReleaser 产出的二进制，不在 Docker 中重复编译
FROM ubuntu:24.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      tzdata \
      libgpgme11 \
      lvm2 && \
    rm -rf /var/lib/apt/lists/*

COPY sreg /usr/local/bin/sreg
RUN chmod +x /usr/local/bin/sreg

ENTRYPOINT ["/usr/local/bin/sreg"]
CMD ["--help"]
