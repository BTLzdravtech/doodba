FROM python:3.12.3-slim-bookworm AS base

EXPOSE 8069 8072

ARG TARGETARCH
ARG GEOIP_UPDATER_VERSION=6.0.0
ARG WKHTMLTOPDF_VERSION=0.12.6.1
ARG WKHTMLTOPDF_AMD64_CHECKSUM='98ba0d157b50d36f23bd0dedf4c0aa28c7b0c50fcdcdc54aa5b6bbba81a3941d'
ARG WKHTMLTOPDF_ARM64_CHECKSUM="b6606157b27c13e044d0abbe670301f88de4e1782afca4f9c06a5817f3e03a9c"
ARG WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOPDF_VERSION}-3/wkhtmltox_${WKHTMLTOPDF_VERSION}-3.bookworm_${TARGETARCH}.deb"
ARG LAST_SYSTEM_UID=499
ARG LAST_SYSTEM_GID=499
ARG FIRST_UID=500
ARG FIRST_GID=500
ENV DB_FILTER=.* \
    DEPTH_DEFAULT=1 \
    DEPTH_MERGE=100 \
    EMAIL=https://hub.docker.com/r/tecnativa/odoo \
    GEOIP_ACCOUNT_ID="" \
    GEOIP_LICENSE_KEY="" \
    GIT_AUTHOR_NAME=docker-odoo \
    INITIAL_LANG="" \
    LC_ALL=C.UTF-8 \
    LIST_DB=false \
    NODE_PATH=/usr/local/lib/node_modules:/usr/lib/node_modules \
    OPENERP_SERVER=/opt/odoo/auto/odoo.conf \
    PATH="/home/odoo/.local/bin:$PATH" \
    PIP_NO_CACHE_DIR=0 \
    DEBUGPY_ARGS="--listen 0.0.0.0:6899 --wait-for-client" \
    DEBUGPY_ENABLE=0 \
    PUDB_RDB_HOST=0.0.0.0 \
    PUDB_RDB_PORT=6899 \
    PYTHONOPTIMIZE="" \
    UNACCENT=true \
    WAIT_DB=true \
    WDB_NO_BROWSER_AUTO_OPEN=True \
    WDB_SOCKET_SERVER=wdb \
    WDB_WEB_PORT=1984 \
    WDB_WEB_SERVER=localhost

# Other requirements and recommendations
# See https://github.com/$ODOO_SOURCE/blob/$ODOO_VERSION/debian/control
RUN echo "LAST_SYSTEM_UID=$LAST_SYSTEM_UID\nLAST_SYSTEM_GID=$LAST_SYSTEM_GID\nFIRST_UID=$FIRST_UID\nFIRST_GID=$FIRST_GID" >> /etc/adduser.conf \
    && echo "SYS_UID_MAX   $LAST_SYSTEM_UID\nSYS_GID_MAX   $LAST_SYSTEM_GID" >> /etc/login.defs \
    && sed -i -E "s/^UID_MIN\s+[0-9]+.*/UID_MIN   $FIRST_UID/;s/^GID_MIN\s+[0-9]+.*/GID_MIN   $FIRST_GID/" /etc/login.defs \
    && useradd --system -u $LAST_SYSTEM_UID -s /usr/sbin/nologin -d / systemd-network \
    && apt-get -qq update \
    && apt-get install -yqq --no-install-recommends \
        curl \
    && if [ "$TARGETARCH" = "arm64" ]; then \
        WKHTMLTOPDF_CHECKSUM=$WKHTMLTOPDF_ARM64_CHECKSUM; \
    elif [ "$TARGETARCH" = "amd64" ]; then \
        WKHTMLTOPDF_CHECKSUM=$WKHTMLTOPDF_AMD64_CHECKSUM; \
    else \
        echo "Unsupported architecture: $TARGETARCH" >&2; \
        exit 1; \
    fi \
    && curl -SLo wkhtmltox.deb ${WKHTMLTOPDF_URL} \
    && echo "Downloading wkhtmltopdf from: ${WKHTMLTOPDF_URL}" \
    && echo "Expected wkhtmltox checksum: ${WKHTMLTOPDF_CHECKSUM}" \
    && echo "Computed wkhtmltox checksum: $(sha256sum wkhtmltox.deb | awk '{ print $1 }')" \
    && echo "${WKHTMLTOPDF_CHECKSUM} wkhtmltox.deb" | sha256sum -c - \
    && apt-get install -yqq --no-install-recommends \
        ./wkhtmltox.deb \
        chromium \
        ffmpeg \
        fonts-liberation2 \
        gettext \
        git \
        gnupg2 \
        locales-all \
        nano \
        npm \
        openssh-client \
        telnet \
        vim
RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ bookworm-pgdg main' >> /etc/apt/sources.list.d/postgresql.list \
    && curl -SL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && apt-get update \
    && curl --silent -L --output geoipupdate_${GEOIP_UPDATER_VERSION}_linux_${TARGETARCH}.deb https://github.com/maxmind/geoipupdate/releases/download/v${GEOIP_UPDATER_VERSION}/geoipupdate_${GEOIP_UPDATER_VERSION}_linux_${TARGETARCH}.deb \
    && dpkg -i geoipupdate_${GEOIP_UPDATER_VERSION}_linux_${TARGETARCH}.deb \
    && rm geoipupdate_${GEOIP_UPDATER_VERSION}_linux_${TARGETARCH}.deb \
    && apt-get autopurge -yqq \
    && rm -Rf wkhtmltox.deb /var/lib/apt/lists/* /tmp/* \
    && sync

WORKDIR /opt/odoo
COPY bin/* /usr/local/bin/
COPY lib/doodbalib /usr/local/lib/python3.12/site-packages/doodbalib
COPY build.d common/build.d
COPY conf.d common/conf.d
COPY entrypoint.d common/entrypoint.d
RUN rm -f /opt/odoo/common/conf.d/60-geoip-lt17.conf \
    && mv /opt/odoo/common/conf.d/60-geoip-ge17.conf /opt/odoo/common/conf.d/60-geoip.conf
RUN mkdir -p auto/addons auto/geoip custom/src/private \
    && ln /usr/local/bin/direxec common/entrypoint \
    && ln /usr/local/bin/direxec common/build \
    && chmod -R a+rx common/entrypoint* common/build* /usr/local/bin \
    && chmod -R a+rX /usr/local/lib/python3.12/site-packages/doodbalib \
    && cp -a /etc/GeoIP.conf /etc/GeoIP.conf.orig \
    && mv /etc/GeoIP.conf /opt/odoo/auto/geoip/GeoIP.conf \
    && ln -s /opt/odoo/auto/geoip/GeoIP.conf /etc/GeoIP.conf \
    && sed -i 's/.*DatabaseDirectory .*$/DatabaseDirectory \/opt\/odoo\/auto\/geoip\//g' /opt/odoo/auto/geoip/GeoIP.conf \
    && sync

# Doodba-QA dependencies in a separate virtualenv
COPY qa /qa
RUN python -m venv --system-site-packages /qa/venv \
    && . /qa/venv/bin/activate \
    && pip install \
        click \
        coverage \
    && deactivate \
    && mkdir -p /qa/artifacts

ARG ODOO_SOURCE=OCA/OCB
ARG ODOO_VERSION=18.0
ENV ODOO_VERSION="$ODOO_VERSION"

# Install Odoo hard & soft dependencies, and Doodba utilities
RUN build_deps=" \
        build-essential \
        libfreetype6-dev \
        libfribidi-dev \
        libghc-zlib-dev \
        libharfbuzz-dev \
        libjpeg-dev \
        liblcms2-dev \
        libldap2-dev \
        libopenjp2-7-dev \
        libpq-dev \
        libsasl2-dev \
        libtiff5-dev \
        libwebp-dev \
        libxml2-dev \
        libxslt-dev \
        tcl-dev \
        tk-dev \
        zlib1g-dev \
    " \
    && apt-get update \
    && apt-get install -yqq --no-install-recommends $build_deps \
    && curl -o requirements.txt https://raw.githubusercontent.com/$ODOO_SOURCE/$ODOO_VERSION/requirements.txt \
    # disable gevent version recommendation from odoo and use 22.10.2 used in debian bookworm as python3-gevent
    && sed -i -E "s/(gevent==)21\.8\.0( ; sys_platform != 'win32' and python_version == '3.10')/\122.10.2\2/;s/(greenlet==)1.1.2( ; sys_platform != 'win32' and python_version == '3.10')/\12.0.2\2/" requirements.txt \
    # need to upgrade setuptools, since the fixes for CVE-2024-6345 rolled out in base images we get errors "error: invalid command 'bdist_wheel'"
    && pip install --upgrade setuptools \
    && pip install -r requirements.txt \
        'websocket-client~=0.56' \
        astor \
        click-odoo-contrib \
        debugpy \
        pydevd-odoo \
        git+https://github.com/mailgun/flanker.git@v0.9.15#egg=flanker[validator] \
        geoip2 \
        "git-aggregator==4.0" \
        inotify \
        pdfminer.six \
        pg_activity \
        phonenumbers \
        plumbum \
        pudb \
        pyOpenSSL \
        python-magic \
        watchdog \
        wdb \
    && (python3 -m compileall -q /usr/local/lib/python3.12/ || true) \
    # generate flanker cached tables during install when /usr/local/lib/ is still intended to be written to
    # https://github.com/Tecnativa/doodba/issues/486
    && python3 -c 'from flanker.addresslib import address' >/dev/null 2>&1 \
    && apt-get purge -yqq $build_deps \
    && apt-get autopurge -yqq \
    && rm -Rf /var/lib/apt/lists/* /tmp/*

# Metadata
ARG VCS_REF
ARG BUILD_DATE
ARG VERSION
LABEL org.label-schema.schema-version="$VERSION" \
      org.label-schema.vendor=Tecnativa \
      org.label-schema.license=Apache-2.0 \
      org.label-schema.build-date="$BUILD_DATE" \
      org.label-schema.vcs-ref="$VCS_REF" \
      org.label-schema.vcs-url="https://github.com/Tecnativa/doodba"
