FROM pytorch/pytorch:2.9.0-cuda13.0-cudnn9-runtime AS app

ARG USER=serviceuser
ENV HOME=/home/$USER

RUN apt update && \
    apt install -y sudo git curl make gnupg ocrmypdf tesseract-ocr && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -m $USER

# Download and install FRP client
RUN set -ex; \
    ARCH=$(uname -m); \
    if [ "$ARCH" = "aarch64" ]; then \
      FRP_URL="https://raw.githubusercontent.com/nextcloud/HaRP/main/exapps_dev/frp_0.61.1_linux_arm64.tar.gz"; \
    else \
      FRP_URL="https://raw.githubusercontent.com/nextcloud/HaRP/main/exapps_dev/frp_0.61.1_linux_amd64.tar.gz"; \
    fi; \
    echo "Downloading FRP client from $FRP_URL"; \
    curl -L "$FRP_URL" -o /tmp/frp.tar.gz; \
    tar -C /tmp -xzf /tmp/frp.tar.gz; \
    mv /tmp/frp_0.61.1_linux_* /tmp/frp; \
    cp /tmp/frp/frpc /usr/local/bin/frpc; \
    chmod +x /usr/local/bin/frpc; \
    rm -rf /tmp/frp /tmp/frp.tar.gz

# Copy nextcloud HaRP script
# Ref.: https://raw.githubusercontent.com/nextcloud/HaRP/refs/heads/main/exapps_dev/start.sh
COPY --chmod=775 start.sh /usr/local/bin/start.sh

USER $USER

WORKDIR /app

COPY --chown=$USER:$USER requirements.txt requirements.txt
COPY --chown=$USER:$USER main.py .
COPY --chown=$USER:$USER workflow_ocr_backend/ ./workflow_ocr_backend

RUN pip install --break-system-packages -r requirements.txt && \
    pip install --break-system-packages git+https://github.com/ocrmypdf/OCRmyPDF-EasyOCR.git

ENTRYPOINT ["start.sh"]
CMD ["python3", "-u", "main.py"]

FROM app AS devcontainer

COPY --chown=$USER:$USER requirements-dev.txt requirements-dev.txt

# Install dev dependencies and set up sudo
USER root
RUN apt install -y git curl make gnupg && \
    rm -rf /var/lib/apt/lists/* && \
    echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER && \
    chmod 0440 /etc/sudoers.d/$USER
USER $USER
RUN pip install --break-system-packages -r requirements-dev.txt

FROM devcontainer AS test

COPY --chown=$USER:$USER Makefile .
COPY --chown=$USER:$USER test/ ./test
COPY --chown=$USER:$USER .env .
ENTRYPOINT ["make", "test"]
