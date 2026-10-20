#!/bin/sh
# Start bot.pl in the foreground from /data, which holds .irpg.conf.
#
# IRPG_NICKSERV_PASS, if set, becomes the bot's NickServ IDENTIFY line, so the
# password comes from a secret and not from .irpg.conf.
#
# On the first run, when the database does not exist yet, bot.pl asks on stdin
# for the admin account; IRPG_ADMIN, IRPG_ADMIN_CLASS and IRPG_ADMIN_PASS
# answer it. The answers go through a file that is removed before bot.pl
# starts, so the password does not stay on disk.
set -eu

set -- --nodaemon "$@"
if [ -n "${IRPG_NICKSERV_PASS:-}" ]; then
    set -- "$@" --botident "PRIVMSG NickServ :IDENTIFY $IRPG_NICKSERV_PASS"
fi

dbfile=$(sed -n 's/^dbfile[[:space:]]\{1,\}//p' .irpg.conf)
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
