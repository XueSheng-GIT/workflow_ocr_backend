FROM pytorch/pytorch:2.9.0-cuda13.0-cudnn9-runtime AS app

ARG USER=serviceuser
ENV HOME=/home/$USER

RUN apt update && \
    apt install -y sudo git curl make gnupg ocrmypdf tesseract-ocr && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -m $USER

USER $USER

WORKDIR /app

COPY --chown=$USER:$USER requirements.txt requirements.txt
COPY --chown=$USER:$USER main.py .
COPY --chown=$USER:$USER workflow_ocr_backend/ ./workflow_ocr_backend
COPY --chown=$USER:$USER --chmod=755 healthcheck.sh /healthcheck.sh

RUN pip install --break-system-packages -r requirements.txt && \
    pip install --break-system-packages -U Celery \
    pip install --break-system-packages git+https://github.com/ocrmypdf/OCRmyPDF-EasyOCR.git

ENTRYPOINT ["python3", "-u", "main.py"]
HEALTHCHECK --interval=10s --timeout=10s --retries=5 CMD /healthcheck.sh

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
