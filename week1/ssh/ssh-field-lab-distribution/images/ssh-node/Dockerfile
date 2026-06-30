FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        openssh-server \
        python3 \
        rsync \
        sudo \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/field-lab-entrypoint
COPY bin/ /usr/local/bin/

RUN chmod +x \
        /usr/local/bin/field-lab-entrypoint \
        /usr/local/bin/journalctl \
        /usr/local/bin/robot-config-check \
        /usr/local/bin/robot-diagnostic-server \
        /usr/local/bin/robot-service \
        /usr/local/bin/systemctl

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/field-lab-entrypoint"]
