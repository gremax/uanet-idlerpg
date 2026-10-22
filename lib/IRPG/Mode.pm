package IRPG::Mode;
# Channel modes the bot reads and sends: whether a MODE line ops it, and the
# lines that voice players.

use strict;
use warnings;

# modes with a parameter, as Solanum's 005 gives them (PREFIX=(ov),
# CHANMODES=eIbq,k,flj,...): always, or only when set
my %always = map { $_ => 1 } qw(o v e I b q k);
my %onset = map { $_ => 1 } qw(f l j);

sub opped { # whether "MODE <channel> $modes @params" gives $nick ops
    my ($nick, $modes, @params) = @_;
    # the last word may come as an IRC trailing parameter, after a colon
    ($modes, @params) = map { s/^://r } ($modes, @params);
    my $sign = "+";
    for my $mode (split(//, $modes)) {
        if ($mode eq "+" || $mode eq "-") { $sign = $mode; next; }
        next unless $always{$mode} || ($onset{$mode} && $sign eq "+");
        my $param = shift(@params);
        return 1 if $mode eq "o" && $sign eq "+" && defined($param) &&
                    lc($param) eq lc($nick);
    }
    return 0;
}

sub voice { # the MODE lines voicing @nicks in $channel, $perline at a time
    my ($channel, $perline, @nicks) = @_;
    my @lines;
    while (my @some = splice(@nicks, 0, $perline)) {
        push(@lines, "MODE $channel +".("v" x @some)." @some");
    }
    return @lines;
}

1;
