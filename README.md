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

Licensing
---------

The parts differ:

- `bot.pl`, `events.txt`, `irpgdbtool`, `README` and `ChangeLog.txt` are by
  jotun and the other IdleRPG authors. Their terms are in the header of
  `bot.pl`: distributing modified versions needs written permission from the
  authors. This fork does not have it, same as the forks it is based on.
- `lang/` holds the bot's messages taken out of `bot.pl`, and translations of
  them, so it falls under the same terms as `bot.pl`.
- `lib/` and `t/` are new code written for this fork and are under the MIT
  license, see `LICENSE-MIT`.
