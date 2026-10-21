#!/bin/sh
# Start bot.pl in the foreground from /data, the bot's working directory.
#
# The configuration is the image's own, /app/irpg.conf, linked to
# /data/.irpg.conf on every start; IRPG_CONFIG names another file instead.
#
# IRPG_NICKSERV_PASS, if set, becomes the bot's NickServ IDENTIFY line and the
# GHOST line it sends to take its nick back, so the password comes from a
# secret and not from the configuration. Both name the account, the botnick,
# as the bot may be on another nick when it sends them.
#
# On the first run, when the database does not exist yet, bot.pl asks on stdin
# for the admin account; IRPG_ADMIN, IRPG_ADMIN_CLASS and IRPG_ADMIN_PASS
# answer it. The answers go through a file that is removed before bot.pl
# starts, so the password does not stay on disk.
set -eu

ln -sf "${IRPG_CONFIG:-/app/irpg.conf}" .irpg.conf
option() {
    sed -n "s/^$1[[:space:]]\{1,\}//p" .irpg.conf
}

set -- --nodaemon "$@"
if [ -n "${IRPG_NICKSERV_PASS:-}" ]; then
    nick=$(option botnick)
    set -- "$@" --botident "PRIVMSG NickServ :IDENTIFY $nick $IRPG_NICKSERV_PASS" \
        --botghostcmd "PRIVMSG NickServ :GHOST $nick $IRPG_NICKSERV_PASS"
fi

dbfile=$(option dbfile)
if [ ! -e "${dbfile:-irpg.db}" ]; then
    if [ -z "${IRPG_ADMIN:-}" ] || [ -z "${IRPG_ADMIN_PASS:-}" ]; then
        echo "No database yet: set IRPG_ADMIN and IRPG_ADMIN_PASS for the first run." >&2
        exit 1
    fi
    answers=$(mktemp)
    printf '%s\n%s\n%s\n' "$IRPG_ADMIN" "${IRPG_ADMIN_CLASS:-Admin}" \
        "$IRPG_ADMIN_PASS" > "$answers"
    exec 3< "$answers"
    rm -f "$answers"
    exec perl /app/bot.pl "$@" <&3 3<&-
fi
exec perl /app/bot.pl "$@"
