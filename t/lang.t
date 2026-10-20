use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use IRPG::Lang;

my $dir = "$FindBin::Bin/lang";

my $en = IRPG::Lang->load($dir, 'en');
is($en->msg('levelup', player => 'Don', class => 'NPC', level => 5),
   'Don, the NPC, has attained level 5!', 'placeholders are filled in');

my $uk = IRPG::Lang->load($dir, 'uk');
my %levels = (0 => '0 рівнів', 1 => '1 рівень', 2 => '2 рівні', 4 => '4 рівні',
              5 => '5 рівнів', 11 => '11 рівнів', 12 => '12 рівнів',
              14 => '14 рівнів', 21 => '21 рівень', 22 => '22 рівні',
              101 => '101 рівень', 112 => '112 рівнів');
for my $n (sort { $a <=> $b } keys(%levels)) {
    is($uk->msg('levels', n => $n), $levels{$n}, "uk plural for $n");
}
is($uk->msg('levelup', player => 'Don', class => 'NPC', level => 5),
   'Don, the NPC, has attained level 5!', 'a missing uk key falls back to en');
is($en->msg('no.such.key'), 'no.such.key', 'an unknown key renders as itself');
is($en->msg('#levelup'), '#levelup', 'comment lines define no keys');
is($en->msg('levelup', player => '%{class}', class => 'NPC', level => 5),
   '%{class}, the NPC, has attained level 5!',
   'placeholders inside values are left alone');

# en output must match the original bot.pl duration() byte for byte
my %en_durations = (54 => '0 days, 00:00:54', 90061 => '1 day, 01:01:01',
                    172800 => '2 days, 00:00:00', 1814400 => '21 days, 00:00:00',
                    abc => 'NA (abc)', -5 => 'NA (-5)');
for my $s (sort keys(%en_durations)) {
    is($en->duration($s), $en_durations{$s}, "en duration of $s");
}

done_testing();
