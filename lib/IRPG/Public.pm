package IRPG::Public;
# The game as the site rpg.uanet.net shows it, built from the bot's own data
# and written as JSON. Only public fields leave: never password hashes, nicks
# or user@host.

use strict;
use warnings;
use Encode ();
use JSON::PP ();
use POSIX ();
use Time::Local ();

my @penalties = qw(mesg nick part kick quit quest logout);

# item types as bot.pl names them, and the slots the site names them by
my %slot = (amulet => "amulet", charm => "charm", helm => "helm",
            "pair of boots" => "boots", "pair of gloves" => "gloves",
            ring => "ring", "set of leggings" => "leggings",
            shield => "shield", tunic => "tunic", weapon => "weapon");

# build(rps => \%rps, mapitems => \%mapitems, quest => \%quest, npc => [names],
#       modsfile => FILE, events => COUNT, now => EPOCH, heard => EPOCH)
# heard is when the bot last got a line from the server, undef while it is not
# connected: the site's /status reports a bot that hears nothing
sub build {
    my %opt = @_;
    my %npc = map { $_ => 1 } @{$opt{npc} || []};
    my $rps = $opt{rps};
    # writedb() leaves out a player without a next, so does the site
    my @names = sort grep { defined($rps->{$_}{next}) } keys(%$rps);
    return {
        players => [ map { player($_, $rps->{$_}, \%npc) } @names ],
        npc => [ map { text($_) } @{$opt{npc} || []} ],
        mapitems => [ mapitems($opt{mapitems} || {}) ],
        quest => quest($opt{quest}),
        events => [ events($opt{modsfile}, $opt{events} // 20) ],
        updated => iso($opt{now} // time()),
        heard => defined($opt{heard}) ? iso($opt{heard}) : undef,
    };
}

sub write_json { # write $data to $file atomically, through a file next to it
    my ($data, $file) = @_;
    my $tmp = "$file.tmp";
    open(my $fh, '>:raw', $tmp) or die("Cannot write $tmp: $!\n");
    print $fh JSON::PP->new->utf8->canonical->encode($data);
    close($fh) or die("Cannot write $tmp: $!\n");
    rename($tmp, $file) or die("Cannot rename $tmp to $file: $!\n");
    return;
}

sub player { # public view of one %rps entry
    my ($name, $p, $npc) = @_;
    my (%items, %unique);
    for my $type (keys(%slot)) {
        my ($level, $tag) = itemlevel($p->{item}{$type});
        $items{$slot{$type}} = $level;
        $unique{$slot{$type}} = $tag if $tag;
    }
    return {
        name => text($name), class => text($p->{class}),
        level => 0 + $p->{level}, next => 0 + $p->{next},
        idled => 0 + $p->{idled}, alignment => text($p->{alignment}),
        online => bool($p->{online}), npc => bool($npc->{$name}),
        x => 0 + $p->{x}, y => 0 + $p->{y}, created => iso($p->{created}),
        items => \%items, unique => \%unique,
        penalties => { map { $_ => 0 + ($p->{"pen_$_"} // 0) } @penalties },
    };
}

sub mapitems { # %mapitems is "x:y" => [ { type, level, lasttime } ]
    my $map = shift;
    my @items;
    for my $xy (keys(%$map)) {
        my ($x, $y) = split(/:/, $xy);
        for my $i (@{$map->{$xy}}) {
            my ($level, $tag) = itemlevel($i->{level});
            my %item = (x => 0 + $x, y => 0 + $y,
                        type => $slot{$i->{type}} // text($i->{type}),
                        level => $level);
            $item{unique} = $tag if $tag;
            push(@items, \%item);
        }
    }
    my @sorted = sort { $a->{x} <=> $b->{x} || $a->{y} <=> $b->{y} ||
                         $a->{type} cmp $b->{type} || $a->{level} <=> $b->{level} }
                       @items;
    return @sorted;
}

sub quest { # the running quest, or undef between quests
    my $q = shift;
    # build() calls this in a list, where a bare return would shift the keys
    return undef if !$q || !@{$q->{questers} || []}; ## no critic (ProhibitExplicitReturnUndef)
    my %quest = (type => 0 + $q->{type}, text => text($q->{text}),
                 players => [ map { text($_) } @{$q->{questers}} ],
                 p1 => undef, p2 => undef, stage => undef, ends => undef);
    if ($quest{type} == 1) { $quest{ends} = iso($q->{qtime}); }
    else {
        $quest{p1} = [ map { 0 + $_ } @{$q->{p1}} ];
        $quest{p2} = [ map { 0 + $_ } @{$q->{p2}} ];
        $quest{stage} = 0 + $q->{stage};
    }
    return \%quest;
}

sub events { # the last $count lines of modifiers.txt, newest first
    my ($file, $count) = @_;
    open(my $fh, '<', $file // '') or return ();
    # the bot only ever appends to this file, so read just its tail, and twice
    # as much each time it holds fewer than $count lines
    my $size = -s $fh;
    my @events;
    for (my $tail = 256 * $count; ; $tail *= 2) {
        @events = ();
        seek($fh, $size > $tail ? $size - $tail : 0, 0);
        <$fh> if $size > $tail; # skip the partial first line
        while (my $l = <$fh>) {
            $l =~ s/[\r\n]//g;
            # "[mm/dd/yy hh:mm:ss] text" from ts(), in the bot's local time
            my ($mo, $d, $y, $h, $mi, $s, $text) =
                $l =~ m{^\[(\d\d)/(\d\d)/(\d\d) (\d\d):(\d\d):(\d\d)\] (.*)$}
                or next;
            push(@events, { t => iso(Time::Local::timelocal($s, $mi, $h, $d,
                                                         $mo - 1, 2000 + $y)),
                            text => text($text) });
        }
        last if @events >= $count || $tail >= $size;
    }
    close($fh);
    splice(@events, 0, @events - $count) if @events > $count;
    return reverse(@events);
}

sub itemlevel { # "75b" is a level 75 unique item b: returns (75, "b")
    my ($level, $tag) = (shift // "") =~ /^(\d+)(\D?)$/;
    return (0 + ($level // 0), $tag);
}

sub text { # the bot keeps bytes; invalid UTF-8 becomes U+FFFD, not an error
    return Encode::decode('UTF-8', shift // '');
}

sub bool {
    return shift ? JSON::PP::true : JSON::PP::false;
}

sub iso { # epoch seconds as UTC ISO 8601
    return POSIX::strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(shift));
}

1;
