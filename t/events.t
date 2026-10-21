use strict;
use warnings;
use FindBin;
use Test::More;

# the rules in the header of events.uk.txt
my $file = "$FindBin::Bin/../events.uk.txt";
open(my $fh, '<:encoding(UTF-8)', $file) or die("Cannot open $file: $!\n");
my %count;
while (my $line = <$fh>) {
    chomp($line);
    next if $line =~ /^#/ || !length($line);
    my $at = "line $.";
    my ($type, $text);
    if ($line =~ /^Q2 (\d+) (\d+) (\d+) (\d+) (.*)$/) {
        $type = 'Q2';
        $text = $5;
        my @xy = ($1, $2, $3, $4);
        ok(!grep({ $_ > 500 } @xy), "$at: quest points are on the 500 x 500 map")
            or diag($line);
    }
    elsif ($line =~ /^(C|G|Q1) (.*)$/) { ($type, $text) = ($1, $2); }
    else {
        fail("$at: starts with C, G, Q1 or Q2 and their fields");
        diag($line);
        next;
    }
    $count{$type}++;
    like($text, qr/^\S(?:.*\S)?$/, "$at: has text, without spaces around it");
    unlike($text, qr/[.!]$/, "$at: does not end in . or !");
}
close($fh);

ok($count{$_}, "has $_ events") for qw(C G Q1 Q2);

done_testing();
