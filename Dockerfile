# IdleRPG bot for UAnet. One image, two containers in the pod: the bot
# (default entrypoint) and stunnel (`stunnel /etc/stunnel/irc.conf`), because
# bot.pl speaks plain text only. The bot connects to stunnel on 127.0.0.1:6667.
#
# Code lives in /app; the database, logs and .irpg.conf live in /data, which is
# the bot's working directory and the volume to persist.
FROM debian:13-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        perl libio-socket-inet6-perl stunnel4 ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN useradd --system --uid 10001 --home-dir /data --no-create-home idlerpg \
 && mkdir /data && chown idlerpg /data
COPY bot.pl events.txt events.uk.txt /app/
COPY lib /app/lib
COPY lang /app/lang
COPY docker/entrypoint.sh /app/entrypoint.sh
COPY docker/stunnel.conf /etc/stunnel/irc.conf
WORKDIR /data
USER 10001
ENTRYPOINT ["/app/entrypoint.sh"]
