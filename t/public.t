use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Encode ();
use File::Temp ();
use JSON::PP ();
use POSIX ();
use IRPG::Public;

# no "use utf8": like the bot, the data below is UTF-8 bytes
sub u { return Encode::decode('UTF-8', shift); }

# fixtures are in UTC unless a test says otherwise
# set before anything reads the time zone, so not local
BEGIN { $ENV{TZ} = "UTC" } ## no critic (RequireLocalizedPunctuationVars)

sub player { # an %rps entry as loaddb() fills it, with the fields given
    my %given = @_;
    my %p = (pass => 'AbCdEfGhIjKlM', isadmin => 0, level => 1, class => 'Class',
             next => 600, nick => 'somenick', userhost => 'someone@host.example',
             online => 1, idled => 0, x => 1, y => 2, created => 1792540000,
             lastlogin => 1792540000, alignment => 'n', %given);
    $p{item}{$_} //= 0 for ("amulet", "charm", "helm", "pair of boots",
                            "pair of gloves", "ring", "set of leggings",
                            "shield", "tunic", "weapon");
    $p{"pen_$_"} //= 0 for qw(mesg nick part kick quit quest logout);
    return \%p;
}

my %rps = (
    Paganel => player(class => 'Гном-інженер', level => 21, next => 523,
                      idled => 172800, alignment => 'e', x => 131, y => 331,
                      created => 1792542356, nick => 'max',
                      userhost => 'max@host.example', pen_mesg => 217,
                      item => { amulet => 12, charm => 24, helm => 9,
                                "pair of boots" => 19, "pair of gloves" => 7,
                                ring => 5, "set of leggings" => 11,
                                shield => 15, tunic => 6, weapon => "160d" }),
    Don => player(class => 'Торговець', online => 0, nick => 'donbot',
                  userhost => 'don@bot.example'),
    Clamps => player(),
    Ghost => player(next => undef),
);
my %mapitems = (
    "300:10" => [ { type => "helm", level => "55a", lasttime => 1 } ],
    "40:220" => [ { type => "shield", level => 13, lasttime => 1 } ],
    "7:8" => [ { type => "pair of boots", level => 7, lasttime => 1 },
               { type => "amulet", level => 3, lasttime => 1 } ],
);
my %quest2 = (questers => [qw(Don Paganel Clamps Blotto)], p1 => [225, 315],
              p2 => [280, 360], qtime => 1792600000,
              text => 'спопелити Вежі Анкх-Аллора', type => 2, stage => 1);

sub modsfile { # a modifiers.txt with these lines, written as the bot does
    my @lines = @_;
    my $tmp = File::Temp->new();
    print $tmp @lines;
    close($tmp);
    return $tmp;
}
my $mods = modsfile("[10/21/26 01:30:00] перша подія\n",
                    "[10/21/26 01:31:02] друга подія\n",
                    "not an event line\n",
                    "[10/21/26 01:32:00] третя подія\n");

my $game = IRPG::Public::build(rps => \%rps, mapitems => \%mapitems,
                               quest => \%quest2, npc => ['Don'],
                               modsfile => "$mods", now => 1792546000,
                               heard => 1792545990);

is_deeply($game->{players}[2], {
    name => 'Paganel', class => u('Гном-інженер'), level => 21, next => 523,
    idled => 172800, alignment => 'e', online => JSON::PP::true,
    npc => JSON::PP::false, x => 131, y => 331, created => '2026-10-21T00:25:56Z',
    items => { amulet => 12, charm => 24, helm => 9, boots => 19, gloves => 7,
               ring => 5, leggings => 11, shield => 15, tunic => 6, weapon => 160 },
    unique => { weapon => 'd' },
    penalties => { mesg => 217, nick => 0, part => 0, kick => 0, quit => 0,
                   quest => 0, logout => 0 },
}, 'a player has the public fields only, items split into level and unique tag');
is_deeply([ map { $_->{name} } @{$game->{players}} ], [qw(Clamps Don Paganel)],
          'players by name, without the ones writedb() leaves out');

my ($don) = grep { $_->{name} eq 'Don' } @{$game->{players}};
ok($don->{npc}, 'a configured NPC is marked');
ok(!$don->{online}, 'an offline player is offline');
is_deeply($game->{npc}, ['Don'], 'and NPCs are listed');

is_deeply($game->{mapitems}, [
    { x => 7, y => 8, type => 'amulet', level => 3 },
    { x => 7, y => 8, type => 'boots', level => 7 },
    { x => 40, y => 220, type => 'shield', level => 13 },
    { x => 300, y => 10, type => 'helm', level => 55, unique => 'a' },
], 'items on the map, in order, with item types named like the slots');

is_deeply($game->{quest}, {
    type => 2, text => u('спопелити Вежі Анкх-Аллора'),
    players => [qw(Don Paganel Clamps Blotto)],
    p1 => [225, 315], p2 => [280, 360], stage => 1, ends => undef,
}, 'a type 2 quest has its two points and the stage');

my %quest1 = (questers => [qw(Don Paganel Clamps Blotto)], p1 => [], p2 => [],
              qtime => 1792600000, text => 'знайти томи пророка', type => 1,
              stage => 1);
is_deeply(IRPG::Public::build(rps => {}, quest => \%quest1)->{quest}, {
    type => 1, text => u('знайти томи пророка'),
    players => [qw(Don Paganel Clamps Blotto)],
    p1 => undef, p2 => undef, stage => undef, ends => '2026-10-21T16:26:40Z',
}, 'a type 1 quest has the time it ends');
is(IRPG::Public::build(rps => {}, quest => { %quest1, questers => [] })->{quest},
   undef, 'no questers: no quest');

is_deeply($game->{events}, [
    { t => '2026-10-21T01:32:00Z', text => u('третя подія') },
    { t => '2026-10-21T01:31:02Z', text => u('друга подія') },
    { t => '2026-10-21T01:30:00Z', text => u('перша подія') },
], 'the latest events, newest first');
is_deeply(IRPG::Public::build(rps => {}, modsfile => "$mods", events => 2)->{events},
          [ @{$game->{events}}[0, 1] ], 'as many as asked for');
is($game->{updated}, '2026-10-21T01:26:40Z', 'the time of the export');
is($game->{heard}, '2026-10-21T01:26:30Z', 'when the bot last heard the server');
is(IRPG::Public::build(rps => {})->{heard}, undef, 'null while disconnected');

my $long = modsfile(map { sprintf("[10/21/26 01:%02d:%02d] подія номер %d\n",
                                  $_ / 60, $_ % 60, $_) } (0..3599));
my $tail = IRPG::Public::build(rps => {}, modsfile => "$long", events => 3);
is_deeply([ map { $_->{text} } @{$tail->{events}} ],
          [ map { u("подія номер $_") } (3599, 3598, 3597) ],
          'a long event log: the last lines only, no cut-off line');
is(scalar(@{IRPG::Public::build(rps => {}, modsfile => "$long",
                                events => 50)->{events}}), 50,
   'and as many as asked for');
my $wordy = modsfile(map { "[10/21/26 01:00:00] $_ " . ("ж" x 400) . "\n" } (1..100));
is(scalar(@{IRPG::Public::build(rps => {}, modsfile => "$wordy")->{events}}), 20,
   'also when the lines are long, 20 by default');
is_deeply(IRPG::Public::build(rps => {}, modsfile => "/nonexistent/mods")->{events},
          [], 'no modifiers.txt: no events');

# ts() writes the bot's local time
{
    local $ENV{TZ} = 'Europe/Kyiv';
    POSIX::tzset();
    is(IRPG::Public::build(rps => {}, modsfile => "$mods", events => 1)->{events}[0]{t},
       '2026-10-20T22:32:00Z', 'event times are read in the local time zone');
}
POSIX::tzset();

is(IRPG::Public::build(rps => { "bad\xff" => player(class => "x\xffy") })
   ->{players}[0]{class}, "x\x{fffd}y", 'invalid UTF-8 becomes U+FFFD');

my $out = File::Temp::tempdir(CLEANUP => 1);
IRPG::Public::write_json($game, "$out/public.json");
IRPG::Public::write_json($game, "$out/public.json");
opendir(my $dh, $out) or die;
is_deeply([ sort grep { !/^\./ } readdir($dh) ], ['public.json'],
          'written in place of the old file, no temporary files left');
closedir($dh);
open(my $jf, '<:raw', "$out/public.json") or die;
my $json = do { local $/; <$jf> };
close($jf);
like($json, qr/"level":21,/, 'numbers are JSON numbers');
ok(index($json, 'Гном-інженер') >= 0, 'text is UTF-8, not \u escapes');
is_deeply(JSON::PP->new->utf8->decode($json)->{quest}{p1}, [225, 315],
          'and it reads back');
for my $secret ('AbCdEfGhIjKlM', 'host.example', 'bot.example', 'somenick',
                '"donbot"', '"max"', 'lastlogin', 'isadmin') {
    is(index($json, $secret), -1, "no $secret in the file");
}

ok(!eval { IRPG::Public::write_json($game, "/nonexistent/public.json"); 1 },
   'a file that cannot be written dies');
like($@, qr{^Cannot write /nonexistent/public\.json\.tmp: }, 'and says why');

done_testing();
