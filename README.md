idlerpg
=======

Fork of the original IdleRPG by http://idlerpg.net

Includes patches from http://idle.quyo.de/patches.php

UAnet fork
----------

This is the bot behind the Ukrainian IdleRPG on UAnet (irc.uanet.net). It is
based on [falsovsky/idlerpg](https://github.com/falsovsky/idlerpg) and keeps
its history; `upstream` in a local clone points there.

What this fork adds:

- A message table. Every message the bot sends to players lives in
  `lang/<lang>.txt` as `key text`, with `%{name}` placeholders and
  `%{n|form|form...}` plural forms. `lang` and `langdir` in `.irpg.conf` pick
  the language; keys missing from a translation fall back to `lang/en.txt`.
  The English output is the same as the original bot's.
- Tests: `prove t/` (Test::More, part of core Perl).
- `events.uk.txt`, the events in Ukrainian.
- `nodaemon` to stay in the foreground, a SIGTERM handler that saves the database
  and quits IRC, and `eventrate` to make random events more frequent for testing.
- `publicfile`, the public part of the game as JSON for the site,
  [gremax/uanet-idlerpg-site](https://github.com/gremax/uanet-idlerpg-site): the
  players without passwords, nicks or hosts, the items on the map, the quest and
  the latest events. The bot replaces the file whole (a new file, then a rename)
  with every database write and at every level up. `npc` names the characters
  the site marks as NPCs.

Container
---------

Every push to `master` publishes `ghcr.io/gremax/uanet-idlerpg:sha-<commit>`. The
bot has no TLS, so a pod runs the image twice:

- the bot, with the default entrypoint;
- stunnel, with `stunnel /etc/stunnel/irc.conf`. It listens on `127.0.0.1:6667` and
  connects to `irc.uanet.net:6697`, checking the certificate. Start it before the bot
  (a native sidecar); the bot retries every `reconnect_wait` seconds anyway.

The bot runs as uid 10001 in `/data`: `.irpg.conf` is read from there, and the
database (`irpg.db`, `items.db`), `modifiers.txt`, `questinfo.txt`, `public.json`
and the bot's own backups in `.dbbackup/` are written there. Persist `/data`, and
run one copy only.

In `.irpg.conf`, point at the code in `/app` and at stunnel:

```
server 127.0.0.1:6667
eventsfile /app/events.uk.txt
langdir /app/lang
lang uk
publicfile public.json
```

Leave `botident` out; the entrypoint builds it from the environment:

| Variable | Used for |
| --- | --- |
| `IRPG_NICKSERV_PASS` | `PRIVMSG NickServ :IDENTIFY <password>` on connect |
| `IRPG_ADMIN`, `IRPG_ADMIN_PASS`, `IRPG_ADMIN_CLASS` | the admin character, on the first run only (no `irpg.db` yet); the class defaults to `Admin` |

Licensing
---------

The parts differ:

- `bot.pl`, `events.txt`, `irpgdbtool`, `README` and `ChangeLog.txt` are by
  jotun and the other IdleRPG authors. Their terms are in the header of
  `bot.pl`: distributing modified versions needs written permission from the
  authors. This fork does not have it, same as the forks it is based on.
- `lang/` holds the bot's messages taken out of `bot.pl`, and translations of
  them; `events.uk.txt` translates `events.txt`. Both fall under the same terms
  as `bot.pl`.
- `lib/`, `t/`, `docker/`, `Dockerfile` and `.github/` are new code written for
  this fork and are under the MIT license, see `LICENSE-MIT`.
