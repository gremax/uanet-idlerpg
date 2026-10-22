use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use IRPG::Mode;

# opped(NICK, MODES, PARAMS...): whether a MODE line gives NICK ops
ok(IRPG::Mode::opped("IdleRPG", "+o", "IdleRPG"), "ChanServ's OP");
ok(IRPG::Mode::opped("IdleRPG", "+o", "idlerpg"), "nicks match in any case");
ok(IRPG::Mode::opped("IdleRPG", ":+o", ":IdleRPG"), "a trailing parameter");
ok(!IRPG::Mode::opped("IdleRPG", "+o", "gremax"), "someone else's op");
ok(!IRPG::Mode::opped("IdleRPG", "-o", "IdleRPG"), "a deop");
ok(!IRPG::Mode::opped("IdleRPG", "+v", "IdleRPG"), "a voice");
ok(IRPG::Mode::opped("IdleRPG", "+vo", "gremax", "IdleRPG"),
   "op after another mode's parameter");
ok(!IRPG::Mode::opped("IdleRPG", "+o-o", "gremax", "IdleRPG"),
   "the sign changes halfway");
ok(IRPG::Mode::opped("IdleRPG", "+bo", "*!*\@spam", "IdleRPG"),
   "a ban takes a parameter");
ok(IRPG::Mode::opped("IdleRPG", "+lo", "50", "IdleRPG"),
   "so does a limit being set");
ok(IRPG::Mode::opped("IdleRPG", "-l+o", "IdleRPG"),
   "but not one being removed");
ok(!IRPG::Mode::opped("IdleRPG", "+nt"), "no parameters at all");

# voice(CHANNEL, PER_LINE, NICKS...): the MODE lines voicing NICKS
is_deeply([IRPG::Mode::voice("#idlerpg", 3, qw(a b))],
          ["MODE #idlerpg +vv a b"], "fewer than a line");
is_deeply([IRPG::Mode::voice("#idlerpg", 3, qw(a b c))],
          ["MODE #idlerpg +vvv a b c"], "exactly a line, and no empty one");
is_deeply([IRPG::Mode::voice("#idlerpg", 3, qw(a b c d e f g))],
          ["MODE #idlerpg +vvv a b c", "MODE #idlerpg +vvv d e f",
           "MODE #idlerpg +v g"], "several lines");
is_deeply([IRPG::Mode::voice("#idlerpg", 3)], [], "nobody to voice");

done_testing();
