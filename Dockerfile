FROM pytorch/pytorch:2.9.0-cuda13.0-cudnn9-runtime AS app

ARG USER=serviceuser

ENV USER=$USER
ENV HOME=/home/$USER
ENV GOSU_VERSION=1.19

RUN apt update && \
    apt install -y sudo git curl make gnupg ocrmypdf tesseract-ocr ca-certificates gosu unzip && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -m $USER && \
	touch /frpc.toml && \
    mkdir -p /certs && \
    chown -R $USER:$USER /frpc.toml /certs && \
    chmod 600 /frpc.toml

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

# Download EasyOCR models (unzip is required!)
RUN mkdir -p /home/$USER/.EasyOCR/model && \
    cd /home/$USER/.EasyOCR/model && \
    curl -fsSL -O https://github.com/JaidedAI/EasyOCR/releases/download/v1.3/latin_g2.zip && \
    curl -fsSL -O https://github.com/JaidedAI/EasyOCR/releases/download/v1.3/english_g2.zip && \
    curl -fsSL -O https://github.com/JaidedAI/EasyOCR/releases/download/pre-v1.1.6/craft_mlt_25k.zip && \
    unzip '*.zip' && rm -f *.zip && \
    chown -R $USER:$USER /home/$USER/.EasyOCR

WORKDIR /app

COPY --chown=$USER:$USER requirements.txt requirements.txt
COPY --chown=$USER:$USER main.py .
COPY --chown=$USER:$USER workflow_ocr_backend/ ./workflow_ocr_backend
COPY --chown=$USER:$USER start.sh /start.sh
COPY --chown=$USER:$USER healthcheck.sh /healthcheck.sh

RUN chmod +x /start.sh && \
	chmod +x /healthcheck.sh && \
	chown -R $USER:$USER /app && \
	pip install --break-system-packages -r requirements.txt && \
	pip install --break-system-packages -U Celery && \
	pip install --break-system-packages git+https://github.com/ocrmypdf/OCRmyPDF-EasyOCR.git

ENTRYPOINT ["/bin/sh", "-c", "exec gosu \"$USER\" /start.sh python3 -u main.py"]
HEALTHCHECK --interval=10s --timeout=10s --retries=5 CMD /healthcheck.sh

FROM app AS devcontainer

COPY --chown=$USER:$USER requirements-dev.txt requirements-dev.txt

# Install dev dependencies and set up sudo
USER root
RUN apt install -y git docker-cli curl make gnupg && \
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
