FROM python:3.12-alpine AS app

ARG USER=serviceuser

ENV USER=$USER
ENV HOME=/home/$USER
ENV GOSU_VERSION=1.19

RUN apk update && \
    apk add --no-cache ocrmypdf $(apk search tesseract-ocr-data- | sed 's/-[0-9].*//') curl bash frp ca-certificates && \
    adduser -D $USER && \
	touch /frpc.toml && \
    mkdir -p /certs && \
    chown -R $USER:$USER /frpc.toml /certs && \
    chmod 600 /frpc.toml

# Install GOSU
RUN set -eux; \
	\
	apk add --no-cache --virtual .gosu-deps \
		ca-certificates \
		dpkg \
		gnupg \
	; \
	\
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	\
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	\
	apk del --no-network .gosu-deps; \
	\
	chmod +x /usr/local/bin/gosu

WORKDIR /app

COPY --chown=$USER:$USER requirements.txt requirements.txt
COPY --chown=$USER:$USER main.py .
COPY --chown=$USER:$USER workflow_ocr_backend/ ./workflow_ocr_backend
COPY --chown=$USER:$USER start.sh /start.sh
RUN chmod +x /start.sh && \
	pip install -r requirements.txt

ENTRYPOINT ["/bin/sh", "-c", "exec gosu \"$USER\" /start.sh python3 -u main.py"]

FROM app AS devcontainer

COPY --chown=$USER:$USER requirements-dev.txt requirements-dev.txt

# Install dev dependencies and set up sudo
USER root
RUN apk add --no-cache sudo git docker-cli make gnupg && \
    echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER && \
    chmod 0440 /etc/sudoers.d/$USER
USER $USER
RUN pip install -r requirements-dev.txt

FROM devcontainer AS test

COPY --chown=$USER:$USER Makefile .
COPY --chown=$USER:$USER test/ ./test
COPY --chown=$USER:$USER .env .
ENTRYPOINT ["make", "test"]