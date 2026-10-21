use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use IRPG::Lang;

# the real message files against the keys bot.pl uses
my $root = "$FindBin::Bin/..";

# other forms of a placeholder that bot.pl passes along with it, so a
# translation may use either
my %variants = (item_acc => 'item');

# placeholders a translation may leave out, where its line reads better without
my %optional = ('topic.entry' => { rank => 1, class => 1 });

sub placeholders { # the names of the placeholders in a text
    my $text = shift;
    return { map { ($variants{$_} // $_) => 1 } ($text =~ /%\{(\w+)[|}]/g) };
}

my $en = IRPG::Lang::parse("$root/lang/en.txt");

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
    my $tr = IRPG::Lang::parse($file);
    for my $key (sort keys(%$tr)) {
        ok(exists($en->{$key}), "$file: $key exists in en.txt") or next;
        my ($want, $have) = (placeholders($en->{$key}), placeholders($tr->{$key}));
        my @missing = grep { !$have->{$_} && !$optional{$key}{$_} } sort keys(%$want);
        my @extra = grep { !$want->{$_} } sort keys(%$have);
        ok(!@missing && !@extra, "$file: $key has the placeholders of en.txt")
            or diag("missing: @missing; not in en.txt: @extra");
    }
}

done_testing();
