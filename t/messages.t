use strict;
use warnings;
use FindBin;
use Test::More;

# the real message files against the keys bot.pl uses
my $root = "$FindBin::Bin/..";

sub readlang {
    my $file = shift;
    my %msgs;
    open(my $fh, '<', $file) or die("Cannot open $file: $!\n");
    while (my $line = <$fh>) {
        chomp($line);
        next if $line =~ /^#/ || !length($line);
        my ($key, $text) = split(/\t/, $line, 2);
        $msgs{$key} = $text;
    }
    close($fh);
    return \%msgs;
}

sub placeholders {
    my $text = shift;
    my %names = map { $_ => 1 } ($text =~ /%\{(\w+)[|}]/g);
    return join(",", sort keys(%names));
}

my $en = readlang("$root/lang/en.txt");

open(my $fh, '<', "$root/bot.pl") or die("Cannot open bot.pl: $!\n");
my $code = do { local $/; <$fh> };
close($fh);
my %used = map { $_ => 1 } ($code =~ /\bmsg\(\s*['"]([\w.]+)['"]/g);
$used{duration} = 1; # used by IRPG::Lang::duration()

for my $key (sort keys(%used)) {
    ok(exists($en->{$key}), "bot.pl key $key is in en.txt");
}
for my $key (sort keys(%$en)) {
    ok($used{$key}, "en.txt key $key is used by bot.pl");
}

for my $file (glob("$root/lang/*.txt")) {
    next if $file =~ m{/en\.txt$};
    my $tr = readlang($file);
    for my $key (sort keys(%$tr)) {
        ok(exists($en->{$key}), "$file: $key exists in en.txt") or next;
        is(placeholders($tr->{$key}), placeholders($en->{$key}),
           "$file: $key has the placeholders of en.txt");
    }
}

done_testing();
