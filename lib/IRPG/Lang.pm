package IRPG::Lang;
# message table for the bot: one "key<TAB>text" line per message, with
# %{name} placeholders and %{name|form|form...} plurals

use strict;
use warnings;

# index of the plural form to use for a number, per language
my %plural = (
    en => sub { $_[0] == 1 ? 0 : 1 },
    uk => sub {
        my ($n10, $n100) = ($_[0] % 10, $_[0] % 100);
        return 0 if $n10 == 1 && $n100 != 11;
        return 1 if $n10 >= 2 && $n10 <= 4 && ($n100 < 12 || $n100 > 14);
        return 2;
    },
);

sub load {
    my ($class, $dir, $lang) = @_;
    my $self = bless({ msgs => {}, plural => $plural{$lang} }, $class);
    # English is the base, so a key missing from a translation still prints
    $self->readfile("$dir/en.txt");
    $self->readfile("$dir/$lang.txt") if $lang ne 'en';
    return $self;
}

sub readfile {
    my ($self, $file) = @_;
    open(my $fh, '<', $file) or die("Cannot open $file: $!\n");
    while (my $line = <$fh>) {
        chomp($line);
        next if $line =~ /^#/ || !length($line); # skip comments, blank lines
        my ($key, $text) = split(/\t/, $line, 2);
        $self->{msgs}{$key} = $text;
    }
    close($fh);
}

sub msg {
    my ($self, $key, %arg) = @_;
    # an unknown key shows up as itself, so a typo is visible in the channel
    my $text = $self->{msgs}{$key} // $key;
    $text =~ s/%\{(\w+)\|([^}]*)\}/(split(m{\|}, $2))[$self->{plural}->($arg{$1})]/ge;
    $text =~ s/%\{(\w+)\}/$arg{$1}/g;
    return $text;
}

sub duration { # return human duration of seconds
    my ($self, $s) = @_;
    return "NA ($s)" if $s !~ /^\d+$/;
    return $self->msg('duration', days => int($s/86400),
                      hms => sprintf("%02d:%02d:%02d", ($s%86400)/3600,
                                     ($s%3600)/60, ($s%60)));
}

1;
