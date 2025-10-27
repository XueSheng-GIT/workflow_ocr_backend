FROM python:3.12-alpine3.21 AS app

ARG USER=serviceuser
ENV HOME=/home/$USER

RUN apk update && \
    apk add --no-cache sudo ocrmypdf $(apk search tesseract-ocr-data- | sed 's/-[0-9].*//') curl bash frp && \
    adduser -D $USER

USER $USER

WORKDIR /app

COPY --chown=$USER:$USER requirements.txt requirements.txt
COPY --chown=$USER:$USER main.py .
COPY --chown=$USER:$USER workflow_ocr_backend/ ./workflow_ocr_backend
COPY --chown=$USER:$USER start.sh /start.sh

RUN pip install -r requirements.txt

# Make start.sh executable
USER root
RUN chmod +x /start.sh
USER $USER

ENTRYPOINT ["/start.sh", "python3", "-u", "main.py"]

FROM app AS devcontainer

COPY --chown=$USER:$USER requirements-dev.txt requirements-dev.txt

# Install dev dependencies and set up sudo
USER root
RUN apk add --no-cache git curl make gnupg && \
    echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER && \
    chmod 0440 /etc/sudoers.d/$USER
USER $USER
RUN pip install -r requirements-dev.txt 

FROM devcontainer AS test

COPY --chown=$USER:$USER Makefile .
COPY --chown=$USER:$USER test/ ./test
COPY --chown=$USER:$USER .env .
ENTRYPOINT ["make", "test"]