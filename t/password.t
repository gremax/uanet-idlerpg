use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use IRPG::Password;

my $hash = IRPG::Password::hash("correct horse battery");
like($hash, qr/^\$argon2id\$/, "new passwords are hashed with argon2id");
isnt(IRPG::Password::hash("correct horse battery"), $hash,
     "each hash has its own salt");
ok(IRPG::Password::check("correct horse battery", $hash),
   "the password matches its hash");
ok(!IRPG::Password::check("correct horse", $hash), "a wrong one does not");
ok(!IRPG::Password::check("correct horse battery staple", $hash),
   "nor does one that only starts with it");
ok(!IRPG::Password::legacy($hash), "an argon2id hash needs no upgrade");

# a hash from upstream's crypt(), as old databases hold them: DES, which reads
# only the first eight characters
my $des = crypt("password1", "ab");
ok(IRPG::Password::check("password1", $des), "an old DES hash still matches");
ok(!IRPG::Password::check("wrong", $des), "and still refuses a wrong one");
ok(IRPG::Password::legacy($des), "a DES hash is due for an upgrade");
ok(!IRPG::Password::check("password1", ""), "an empty hash matches nothing");

# what debug() writes, in and out
my %lines = (
    ':max!m@host PRIVMSG IdleRPG :LOGIN Paganel s3cret'
        => ':max!m@host PRIVMSG IdleRPG :LOGIN Paganel ***',
    ':max!m@host PRIVMSG IdleRPG :register Paganel s3cret Гном-інженер'
        => ':max!m@host PRIVMSG IdleRPG :register Paganel ***',
    ':max!m@host PRIVMSG IdleRPG :NEWPASS s3cret'
        => ':max!m@host PRIVMSG IdleRPG :NEWPASS ***',
    ':max!m@host PRIVMSG IdleRPG :CHPASS Paganel s3cret'
        => ':max!m@host PRIVMSG IdleRPG :CHPASS Paganel ***',
    '(q000) = PRIVMSG NickServ :IDENTIFY IdleRPG s3cret'
        => '(q000) = PRIVMSG NickServ :IDENTIFY ***',
    '(fm4) -> PRIVMSG NickServ :GHOST IdleRPG s3cret'
        => '(fm4) -> PRIVMSG NickServ :GHOST IdleRPG ***',
    ':max!m@host PRIVMSG IdleRPG :STATUS Paganel'
        => ':max!m@host PRIVMSG IdleRPG :STATUS Paganel',
    # typed into the channel by mistake
    ':max!m@host PRIVMSG #idlerpg :login Paganel s3cret'
        => ':max!m@host PRIVMSG #idlerpg :login Paganel ***',
    ':max!m@host PRIVMSG IdleRPG :LOGIN Paganel'
        => ':max!m@host PRIVMSG IdleRPG :LOGIN Paganel',
);
is(IRPG::Password::redact($_), $lines{$_}, "redact: $_") for sort keys %lines;

done_testing();
