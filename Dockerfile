# python:2.7-alpine with GEOS, GDAL, and Proj installed (built as a separate image
# because it takes a long time to build)
#FROM rapidpro/rapidpro-base:v4
FROM python:3.6-alpine

COPY stack/geolibs.sh /

ARG RAPIDPRO_VERSION
ENV PIP_RETRIES=120 \
    PIP_TIMEOUT=400 \
    PIP_DEFAULT_TIMEOUT=400 \
    C_FORCE_ROOT=1 \
    PIP_EXTRA_INDEX_URL="https://alpine-3.wheelhouse.praekelt.org/simple"

# TODO determine if a more recent version of Node is needed
# TODO extract openssl and tar to their own upgrade/install line
#RUN set -ex \
#  && apk add --no-cache nodejs-lts nodejs-npm openssl tar \
#  && npm install -g coffee-script less bower

COPY requirements.txt /app/requirements.txt
WORKDIR /rapidpro
RUN set -ex \
        && apk add --no-cache --virtual .build-deps \
                --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \
                --repository http://dl-cdn.alpinelinux.org/alpine/edge/main \
                bash \
                patch \
                git \
		gcc \
                g++ \
                make \
                libc-dev \
                musl-dev \
                linux-headers \
                postgresql-dev \
                libjpeg-turbo-dev \
                libpng-dev \
                freetype-dev \
                libxslt-dev \
                libxml2-dev \
                zlib-dev \
                libffi-dev \
                pcre-dev \
                readline \
                readline-dev \
                ncurses \
                ncurses-dev \
                libzmq \
		gdal \
                gdal-dev \
                geos-dev \
		python3-dev \
		rsync

ARG RAPIDPRO_VERSION
ARG RAPIDPRO_REPO=POLLSTERPRO_REPO
ENV RAPIDPRO_VERSION=${RAPIDPRO_VERSION:-master}
ENV RAPIDPRO_REPO=${RAPIDPRO_REPO:-istresearch/rapidpro}
ENV GITHUB_USER=${GITHUB_USER}
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN  echo "Downloading PollsterPro $RAPIDPRO_VERSION from https://github.com/$RAPIDPRO_REPO" && \
    git init && \
    git remote add -t rp-orig-merge -f origin/rapidpro https://$GITHUB_USER:$GITHUB_TOKEN@github.com/istresearch/rapidpro.git && \
    git fetch && \
    git checkout origin/rapidpro/rp-orig-merge

WORKDIR /rapidpro
RUN set -ex \
		&& apk add --no-cache --virtual .build-deps \
               	rsync \
		&& rsync -a /usr/lib/* /usr/local/lib \
                && pip install -U virtualenv \
		&& pip install -r /app/requirements.txt \
                && virtualenv /venv 

#RUN set -ex \
#  && apk add --no-cache nodejs-lts nodejs-npm openssl tar \
#  && npm install -g coffee-script less bower


# Build Python virtualenv
COPY requirements.txt /app/requirements.txt
RUN LIBRARY_PATH=/lib:/usr/lib /bin/sh -c "/venv/bin/pip install setuptools==41.0.1" \
    && LIBRARY_PATH=/lib:/usr/lib /bin/sh -c "/venv/bin/pip install -r /app/requirements.txt" \
    && runDeps="$( \
      scanelf --needed --nobanner --recursive /venv \
              | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
              | sort -u \
              | xargs -r apk info --installed \
              | sort -u \
    )" \
    && apk --no-cache add --virtual .python-rundeps $runDeps \
    && apk del .build-deps && rm -rf /var/cache/apk/*

RUN set -ex \
		&& apk add --no-cache --virtual .build-deps \
                rsync \
                && rsync -a /usr/lib/* /usr/local/lib \
                && pip install -U virtualenv \
                && pip install -r /app/requirements.txt \
                && virtualenv /venv

RUN set -ex \
  && apk add --no-cache nodejs-lts nodejs-npm openssl tar \
  && npm install -g coffee-script less bower

# TODO should this be in startup.sh?
RUN cd /rapidpro && npm install npm@latest && npm install && bower install --allow-root

# Install `psql` command (needed for `manage.py dbshell` in stack/init_db.sql)
# Install `libmagic` (needed since rapidpro v3.0.64)
RUN apk add --no-cache postgresql-client libmagic

ENV UWSGI_VIRTUALENV=/venv UWSGI_WSGI_FILE=temba/wsgi.py UWSGI_HTTP=:8000 UWSGI_MASTER=1 UWSGI_WORKERS=8 UWSGI_HARAKIRI=20
# Enable HTTP 1.1 Keep Alive options for uWSGI (http-auto-chunked needed when ConditionalGetMiddleware not installed)
# These options don't appear to be configurable via environment variables, so pass them in here instead
ENV STARTUP_CMD="/venv/bin/uwsgi --http-auto-chunked --http-keepalive"
ENV CELERY_CMD="/venv/bin/celery --beat --app=temba worker --loglevel=INFO --queues=celery,msgs,flows,handler"
COPY settings.py /rapidpro/temba/
# 500.html needed to keep the missing template from causing an exception during error handling
COPY stack/500.html /rapidpro/templates/
COPY stack/init_db.sql /rapidpro/
COPY stack/clear-compressor-cache.py /rapidpro/
COPY Procfile /rapidpro/
COPY Procfile /
EXPOSE 8000
COPY stack/startup.sh /
COPY settings.py /rapidpro/temba/settings.py
COPY urls.py /rapidpro/temba/urls.py

LABEL org.label-schema.name="RapidPro" \
      org.label-schema.description="RapidPro allows organizations to visually build scalable interactive messaging applications." \
      org.label-schema.url="https://www.rapidpro.io/" \
      org.label-schema.vcs-url="https://github.com/$RAPIDPRO_REPO" \
      org.label-schema.vendor="Nyaruka, UNICEF, and individual contributors." \
      org.label-schema.version=$RAPIDPRO_VERSION \
      org.label-schema.schema-version="1.0"

CMD ["/startup.sh"]
