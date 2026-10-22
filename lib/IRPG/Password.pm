package IRPG::Password;
# Players' passwords: hashed with argon2id, checked against that or against
# the DES crypt() hashes of upstream's databases, and kept out of the debug
# log. DES reads only the first eight characters, so the bot rehashes such a
# password at its owner's next LOGIN.

use strict;
use warnings;
use Crypt::Argon2 qw(argon2id_pass argon2_verify);

# OWASP's minimum for argon2id: 19 MiB, two passes, one lane. A LOGIN blocks
# the bot for its hashing, so not more
my @cost = (2, "19M", 1, 32);

sub hash {
    my $pass = shift;
    return argon2id_pass($pass, salt(), @cost);
}

sub check { # whether $pass is the password $hash was made from
    my ($pass, $hash) = @_;
    return 0 unless defined($hash) && length($hash);
    return argon2_verify($hash, $pass) ? 1 : 0 if !legacy($hash);
    return crypt($pass, $hash) eq $hash ? 1 : 0;
}

sub legacy { # whether $hash is an old crypt() one, to be rehashed
    return shift !~ /^\$argon2/;
}

sub salt {
    open(my $fh, '<:raw', '/dev/urandom') or die("Cannot open /dev/urandom: $!\n");
    read($fh, my $salt, 16) == 16 or die("Cannot read /dev/urandom\n");
    close($fh);
    return $salt;
}

# the commands that carry a password, and how many of their words come before
# it; everything from the password on is masked
my %before = (login => 1, register => 1, chpass => 1, ghost => 1, regain => 1,
              newpass => 0, identify => 0);

sub redact { # a line for the debug log, without the password in it
    my $line = shift;
    my ($head, $cmd, $rest) = $line =~ /^(.*?\bPRIVMSG \S+ :)(\S+)(.*)$/i
        or return $line;
    my $n = $before{lc($cmd)};
    return $line unless defined($n);
    my ($keep) = $rest =~ /^((?:\s+\S+){$n})\s+\S/ or return $line;
    return "$head$cmd$keep ***";
}

1;
