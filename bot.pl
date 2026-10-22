#!/usr/bin/perl
# irpg bot v3.1.2 by jotun, jotun@idlerpg.net, et al. See http://idlerpg.net/
#
# Some code within this file was written by authors other than myself. As such,
# distributing this code or distributing modified versions of this code is
# strictly prohibited without written authorization from the authors. Contact
# jotun@idlerpg.net. Please note that this may change (at any time, no less) if
# authorization for distribution is given by patch submitters.
#
# As a side note, patches submitted for this project are automatically taken to
# be freely distributable and modifiable for any use, public or private, though
# I make no claim to ownership; original copyrights will be retained.. except as
# I've just stated.
#
# Please mail bugs, etc. to me. Patches are welcome to fix bugs or clean up
# the code, but please do not use a radically different coding style. Thanks
# to everyone that's contributed!
#
# NOTE: This code should NOT be run as root. You deserve anything that happens
# to you if you run this code as a superuser.

use strict;
use warnings;
use IO::Socket;
use IO::Socket::INET6;
use IO::Select;
use Data::Dumper;
use Getopt::Long;
use Encode ();
use FindBin;
use lib "$FindBin::Bin/lib";
use IRPG::Lang;
use IRPG::Public;
use IRPG::Password;
use IRPG::Mode;

# To use this script in OpenBSD you need to install the Crypt::UnixCrypt
# perl module because OpenBSD crypt() isn't compatible with the Linux crypt().
#
# You can install it via cpan, and just uncomment the last commented line.
#
# Or create a "Crypt" directory on the bot directory, and put UnixCrypt.pm
# there. Then change the "use lib" path to bot directory. And uncomment
# the next three lines. Enjoy!
#use lib '/path/to/bot';
#BEGIN { $Crypt::UnixCrypt::OVERRIDE_BUILTIN = 1 }
#use Crypt::UnixCrypt;

my %opts;

readconfig();

my $version = "3.3";

# command line overrides .irpg.conf
GetOptions(\%opts,
    "help|h",
    "verbose|v",
    "ipv6",
    "debug",
    "debugfile=s",
    "server|s=s",
    "botnick|n=s",
    "botuser|u=s",
    "botrlnm|r=s",
    "botchan|c=s",
    "botident|p=s",
    "botmodes|m=s",
    "botopcmd|o=s",
    "localaddr=s",
    "botghostcmd|g=s",
    "helpurl=s",
    "admincommurl=s",
    "doban",
    "silentmode=i",
    "writequestfile",
    "questfilename=s",
    "voiceonlogin",
    "noccodes",
    "nononp",
    "mapurl=s",
    "statuscmd",
    "pidfile=s",
    "reconnect",
    "reconnect_wait=i",
    "self_clock=i",
    "modsfile=s",
    "casematters",
    "detectsplits",
    "autologin",
    "splitwait=i",
    "allowuserinfo",
    "noscale",
    "phonehome",
    "nodaemon",
    "owner=s",
    "owneraddonly",
    "ownerdelonly",
    "senduserlist",
    "limitpen=i",
    "mapx=i",
    "mapy=i",
    "modesperline=i",
    "okurl|k=s@",
    "eventsfile=s",
    "eventrate=f",
    "rpstep=f",
    "rpbase=i",
    "rppenstep=f",
    "itemdbfile=s",
    "dbfile|irpgdb|db|d=s",
    "lang=s",
    "langdir=s",
    "publicfile=s",
    "npc=s",
) or debug("Error: Could not parse command line. Try $0 --help\n",1);

$opts{help} and do { help(); exit 0; };

my $lang; # IRPG::Lang message table
loadlang();

debug("Config: read $_: ".Dumper($opts{$_})) for keys(%opts);

my $outbytes = 0; # sent bytes
my $primnick = $opts{botnick}; # for regain or register checks
my $inbytes = 0; # received bytes
my %onchan; # users on game channel
my %rps; # role-players
my %quest = (
    questers => [],
    p1 => [], # point 1 for q2
    p2 => [], # point 2 for q2
    qtime => time() + int(rand(21600)), # first quest starts in <=6 hours
    text => "",
    type => 1,
    stage => 1); # quest info
my %mapitems = (); # items lying around

my $rpreport = 0; # constant for reporting top players
my $oldrpreport = 0; # constant for reporting top players (last value)
my %prev_online; # user@hosts online on restart, die
my %auto_login; # users to automatically log back on
my @bans; # bans auto-set by the bot, saved to be removed after 1 hour
my $pausemode = 0; # pausemode on/off flag
my $silentmode = 0; # silent mode 0/1/2/3, see head of file
my @queue; # outgoing message queue
my $lastreg = 0; # holds the time of the last reg. cleared every second.
                 # prevents more than one account being registered / second
my $registrations = 0; # count of registrations this period
my $sel; # IO::Select object
my $lasttime = 1; # last time that rpcheck() was run
my $buffer; # buffer for socket stuff
my $conn_tries = 0; # number of connection tries. gives up after trying each
                    # server twice
my $sock; # IO::Socket::INET object
my %split; # holds nick!user@hosts for clients that have been netsplit
my $freemessages = 4; # number of "free" privmsgs we can send. 0..$freemessages

sub daemonize(); # prototype to avoid warnings

if (! -e $opts{dbfile}) {
    $|=1;
    %rps = ();
    print "$opts{dbfile} does not appear to exist. I'm guessing this is your ".
          "first time using IRPG. Please give an account name that you would ".
          "like to have admin access [$opts{owner}]: ";
    chomp(my $uname = <STDIN>);
    $uname =~ s/\s.*//g;
    $uname = length($uname)?$uname:$opts{owner};
    print "Enter a character class for this account: ";
    chomp(my $uclass = <STDIN>);
    $rps{$uname}{class} = usubstr($uclass,30);
    print "Enter a password for this account: ";
    if ($^O ne "MSWin32") {
        system("stty -echo");
    }
    chomp(my $upass = <STDIN>);
    if ($^O ne "MSWin32") {
        system("stty echo");
    }
    $rps{$uname}{pass} = IRPG::Password::hash($upass);
    $rps{$uname}{next} = $opts{rpbase};
    $rps{$uname}{nick} = "";
    $rps{$uname}{userhost} = "";
    $rps{$uname}{level} = 0;
    $rps{$uname}{online} = 0;
    $rps{$uname}{idled} = 0;
    $rps{$uname}{created} = time();
    $rps{$uname}{lastlogin} = time();
    $rps{$uname}{x} = int(rand($opts{mapx}));
    $rps{$uname}{y} = int(rand($opts{mapy}));
    $rps{$uname}{alignment}="n";
    $rps{$uname}{isadmin} = 1;
    for my $item ("ring","amulet","charm","weapon","helm",
                  "tunic","pair of gloves","shield",
                  "set of leggings","pair of boots") {
        $rps{$uname}{item}{$item} = 0;
    }
    for my $pen ("pen_mesg","pen_nick","pen_part",
                 "pen_kick","pen_quit","pen_quest",
                 "pen_logout","pen_logout") {
        $rps{$uname}{$pen} = 0;
    }
    writedb();
    print "OK, wrote you into $opts{dbfile}.\n";
}

if ($opts{nodaemon}) { print debug("Staying in the foreground.")."\n"; }
else {
    print "\n".debug("Becoming a daemon...")."\n";
    daemonize();
}

$SIG{HUP} = "rehash"; # sighup = reread config file and message table
$SIG{TERM} = $SIG{INT} = "quitbot"; # save the database before going down

CONNECT: # cheese.

loaddb();

while (!$sock && $conn_tries < 100000*@{$opts{servers}}) {
    debug("Connecting to $opts{servers}->[0]...");
    my %sockinfo = (PeerAddr => $opts{servers}->[0]);
    if ($opts{localaddr}) { $sockinfo{LocalAddr} = $opts{localaddr}; }

    if ($opts{ipv6}) {
        $sock = IO::Socket::INET6->new(%sockinfo) or
            debug("Error: failed to connect: $!\n");
    }
    else {
        $sock = IO::Socket::INET->new(%sockinfo) or
            debug("Error: failed to connect: $!\n");
    }

    ++$conn_tries;
    if (!$sock) {
        # cycle front server to back if connection failed
        push(@{$opts{servers}},shift(@{$opts{servers}}));
    }
    else { debug("Connected."); }
}

if (!$sock) {
    debug("Error: Too many connection failures, exhausted server list.\n",1);
}

$conn_tries=0;

$sel = IO::Select->new($sock);

sts("NICK $opts{botnick}");
sts("USER $opts{botuser} 0 0 :$opts{botrlnm}");

while (1) {
    my($readable) = IO::Select->select($sel,undef,undef,0.5);
    if (defined($readable)) {
        my $fh = $readable->[0];
        my $buffer2;
        $fh->recv($buffer2,512,0);
        if (length($buffer2)) {
            $buffer .= $buffer2;
            while (index($buffer,"\n") != -1) {
                my $line = substr($buffer,0,index($buffer,"\n")+1);
                $buffer = substr($buffer,length($line));
                parse($line);
            }
        }
        else {
            # uh oh, we've been disconnected from the server, possibly before
            # we've logged in the users in %auto_login. so, we'll set those
            # users' online flags to 1, rewrite db, and attempt to reconnect
            # (if that's wanted of us)
            $rps{$_}{online}=1 for keys(%auto_login);
            writedb();

            close($fh);
            $sel->remove($fh);

            if ($opts{reconnect}) {
                undef(@queue);
                undef($sock);
                debug("Socket closed; disconnected. Cleared outgoing message ".
                      "queue. Waiting $opts{reconnect_wait}s before next ".
                      "connection attempt...");
                sleep($opts{reconnect_wait});
                goto CONNECT;
            }
            else { debug("Socket closed; disconnected.",1); }
        }
    }
    else { select(undef,undef,undef,1); }
    if ((time()-$lasttime) >= $opts{self_clock}) { rpcheck(); }
}


sub parse {
    my($in) = shift;
    $inbytes += length($in); # increase parsed byte count
    $in =~ s/[\r\n]//g; # strip all \r and \n
    debug("<- $in");
    my @arg = split(/\s/,$in); # split into "words"
    my $usernick = substr((split(/!/,$arg[0]))[0],1);
    # logged in char name of nickname, or undef if nickname is not online
    my $username = finduser($usernick);
    if (lc($arg[0]) eq 'ping') { sts("PONG $arg[1]",1); }
    elsif (lc($arg[0]) eq 'error') {
        # uh oh, we've been disconnected from the server, possibly before we've
        # logged in the users in %auto_login. so, we'll set those users' online
        # flags to 1, rewrite db, and attempt to reconnect (if that's wanted of
        # us)
        $rps{$_}{online}=1 for keys(%auto_login);
        writedb();
        return;
    }
    $arg[1] = lc($arg[1]); # original case no longer matters
    if ($arg[1] eq '433' && $opts{botnick} eq $arg[3]) {
        $opts{botnick} .= 0;
        sts("NICK $opts{botnick}");
    }
    elsif ($arg[1] eq 'join') {
        # %onchan holds time user joined channel. used for the advertisement ban
        $onchan{$usernick}=time();
        if ($opts{'detectsplits'} && exists($split{substr($arg[0],1)})) {
            delete($split{substr($arg[0],1)});
        }
        elsif ($opts{botnick} eq $usernick) {
            sts("WHO $opts{botchan}");
            (my $opcmd = $opts{botopcmd}) =~ s/%botnick%/$opts{botnick}/eg;
            sts($opcmd);
            $lasttime = time(); # start rpcheck()
        }
        elsif ($opts{autologin}) {
            for my $k (keys %rps) {
                if (":".$rps{$k}{userhost} eq $arg[0]) {
                    if ($opts{voiceonlogin}) {          
                        sts("MODE $opts{botchan} +v :$usernick");
                    }
                    $rps{$k}{online} = 1;
                    $rps{$k}{nick} = $usernick;
                    $rps{$k}{lastlogin} = time();
                    chanmsg(msg('online', player => $k,
                                level => $rps{$k}{level},
                                class => $rps{$k}{class}, nick => $usernick,
                                time => duration($rps{$k}{next})));
                    notice(msg('login.ok', time => duration($rps{$k}{next})),
                           $usernick);
                }
            }
        }
    }
    elsif ($arg[1] eq 'quit') {
        # if we see our nick come open, grab it (skipping queue)
        if ($usernick eq $primnick) { sts("NICK $primnick",1); }
        elsif ($opts{'detectsplits'} &&
               "@arg[2..$#arg]" =~ /^:\S+\.\S+ \S+\.\S+$/) {
            if (defined($username)) { # user was online
                $split{substr($arg[0],1)}{time}=time();
                $split{substr($arg[0],1)}{account}=$username;
            }
        }
        else {
            penalize($username,"quit");
        }
        delete($onchan{$usernick});
    }
    elsif ($arg[1] eq 'nick') {
        # if someone (nickserv) changes our nick for us, update $opts{botnick}
        if ($usernick eq $opts{botnick}) {
            $opts{botnick} = substr($arg[2],1);
        }
        # if we see our nick come open, grab it (skipping queue), unless it was
        # us who just lost it
        elsif ($usernick eq $primnick) { sts("NICK $primnick",1); }
        else {
            penalize($username,"nick",$arg[2]);
            $onchan{substr($arg[2],1)} = delete($onchan{$usernick});
        }
    }
    elsif ($arg[1] eq 'part') {
        penalize($username,"part");
        delete($onchan{$usernick});
    }
    elsif ($arg[1] eq 'kick') {
        $usernick = $arg[3];
        penalize(finduser($usernick),"kick");
        delete($onchan{$usernick});
    }
    # don't penalize /notices to the bot
    elsif ($arg[1] eq 'notice' && $arg[2] ne $opts{botnick}) {
        penalize($username,"notice",length("@arg[3..$#arg]")-1);
    }
    elsif ($arg[1] eq 'mode' && lc($arg[2]) eq lc($opts{botchan})) {
        # opped, by ChanServ after botopcmd or by anyone: set the topic now
        # rather than at the next top-players report, ten hours on
        if (IRPG::Mode::opped($opts{botnick}, @arg[3..$#arg])) {
            sts("TOPIC $opts{botchan} :".topic(), 1);
        }
    }
    elsif ($arg[1] eq '001') {
        # send our identify command, set our usermode, join channel
        sts($opts{botident});
        sts("MODE $opts{botnick} :$opts{botmodes}");
        sts("JOIN $opts{botchan}");
        $opts{botchan} =~ s/ .*//; # strip channel key if present
    }
    elsif ($arg[1] eq '315') {
        # 315 is /WHO end. report who we automagically signed online iff it will
        # print < 1k of text
        if (keys(%auto_login)) {
            # not a true measure of size, but easy
            if (length("%auto_login") < 1024 && $opts{senduserlist}) {
                chanmsg(msg('autologin.list', users => scalar(keys(%auto_login)),
                            hosts => scalar(keys(%prev_online)),
                            accounts => join(", ",keys(%auto_login))));
            }
            else {
                chanmsg(msg('autologin.count',
                            users => scalar(keys(%auto_login)),
                            hosts => scalar(keys(%prev_online))));
            }
            if ($opts{voiceonlogin}) {
                sts($_) for IRPG::Mode::voice($opts{botchan},
                                              $opts{modesperline},
                                              map { $rps{$_}{nick} }
                                                  keys(%auto_login));
            }
        }
        else { chanmsg(msg('autologin.none')); }
        undef(%prev_online);
        undef(%auto_login);
    }
    elsif ($arg[1] eq '005') {
        if ("@arg" =~ /MODES=(\d+)/) { $opts{modesperline}=$1; }
    }
    elsif ($arg[1] eq '352') {
        my $user;
        # 352 is one line of /WHO. check that the nick!user@host exists as a key
        # in %prev_online, the list generated in loaddb(). the value is the user
        # to login
        $onchan{$arg[7]}=time();
        if (exists($prev_online{$arg[7]."!".$arg[4]."\@".$arg[5]})) {
            $rps{$prev_online{$arg[7]."!".$arg[4]."\@".$arg[5]}}{online} = 1;
            $auto_login{$prev_online{$arg[7]."!".$arg[4]."\@".$arg[5]}}=1;
        }
    }
    elsif ($arg[1] eq 'privmsg') {
        $arg[0] = substr($arg[0],1); # strip leading : from privmsgs
        if (lc($arg[2]) eq lc($opts{botnick})) { # to us, not channel
            $arg[3] = lc(substr($arg[3],1)); # lowercase, strip leading :
            if ($arg[3] eq "\1version\1") {
                notice("\1VERSION IRPG bot v$version by jotun; ".
                       "http://idlerpg.net/\1",$usernick);
            }
            elsif ($arg[3] eq "register") {
                if (defined $username) {
                    privmsg(msg('already.online', player => $username),
                            $usernick);
                }
                else {
                    if ($#arg < 6 || $arg[6] eq "") {
                        privmsg(msg('usage.register'),$usernick);
                        privmsg(msg('usage.register.example'),$usernick);
                    }
                    elsif ($pausemode) {
                        privmsg(msg('register.paused'),$usernick);
                    }
                    elsif (exists $rps{$arg[4]} || ($opts{casematters} &&
                           scalar(grep { lc($arg[4]) eq lc($_) } keys(%rps)))) {
                        privmsg(msg('register.taken'),$usernick);
                    }
                    elsif (lc($arg[4]) eq lc($opts{botnick}) ||
                           lc($arg[4]) eq lc($primnick)) {
                        privmsg(msg('register.reserved'),$usernick);
                    }
                    elsif (!exists($onchan{$usernick})) {
                        privmsg(msg('notonchan', channel => $opts{botchan}),
                                $usernick);
                    }
                    elsif (ulength($arg[4]) > 16 || ulength($arg[4]) < 1) {
                        privmsg(msg('register.namelength'), $usernick);
                    }
                    elsif ($arg[4] =~ /^#/) {
                        privmsg(msg('register.hash'),$usernick);
                    }
                    elsif ($arg[4] =~ /\001/) {
                        privmsg(msg('register.ctcp'),$usernick);
                    }
                    elsif ($opts{noccodes} && ($arg[4] =~ /[[:cntrl:]]/ ||
                           "@arg[6..$#arg]" =~ /[[:cntrl:]]/)) {
                        privmsg(msg('register.ccodes'),$usernick);
                    }
                    # names stay ASCII, a class may be any UTF-8 text
                    elsif ($opts{nononp} && $arg[4] =~ /[^[:ascii:]]/) {
                        privmsg(msg('register.ascii'),$usernick);
                    }
                    elsif ($opts{nononp} && ($arg[4] =~ /[[:^print:]]/ ||
                           nonprint("@arg[6..$#arg]"))) {
                        privmsg(msg('register.nonprint'),$usernick);
                    }
                    elsif (ulength("@arg[6..$#arg]") > 30) {
                        privmsg(msg('register.classlength'),$usernick);
                    }
                    elsif (time() == $lastreg) {
                        privmsg(msg('register.wait'),$usernick);
                    }
                    else {
                        if ($opts{voiceonlogin}) {
                            sts("MODE $opts{botchan} +v :$usernick");
                        }
                        ++$registrations;
                        $lastreg = time();
                        $rps{$arg[4]}{next} = $opts{rpbase};
                        $rps{$arg[4]}{class} = "@arg[6..$#arg]";
                        $rps{$arg[4]}{level} = 0;
                        $rps{$arg[4]}{online} = 1;
                        $rps{$arg[4]}{nick} = $usernick;
                        $rps{$arg[4]}{userhost} = $arg[0];
                        $rps{$arg[4]}{created} = time();
                        $rps{$arg[4]}{lastlogin} = time();
                        $rps{$arg[4]}{pass} = IRPG::Password::hash($arg[5]);
                        $rps{$arg[4]}{x} = int(rand($opts{mapx}));
                        $rps{$arg[4]}{y} = int(rand($opts{mapy}));
                        $rps{$arg[4]}{alignment}="n";
                        $rps{$arg[4]}{isadmin} = 0;
                        for my $item ("ring","amulet","charm","weapon","helm",
                                      "tunic","pair of gloves","shield",
                                      "set of leggings","pair of boots") {
                            $rps{$arg[4]}{item}{$item} = 0;
                        }
                        for my $pen ("pen_mesg","pen_nick","pen_part",
                                     "pen_kick","pen_quit","pen_quest",
                                     "pen_logout","pen_logout") {
                            $rps{$arg[4]}{$pen} = 0;
                        }
                        chanmsg(msg('register.welcome', nick => $usernick,
                                    player => $arg[4],
                                    class => "@arg[6..$#arg]",
                                    time => duration($opts{rpbase})));
                        privmsg(msg('register.ok', player => $arg[4],
                                    seconds => $opts{rpbase}), $usernick);
                        privmsg(msg('register.note'),$usernick);
                        if ($opts{phonehome}) {
                            my $tempsock = IO::Socket::INET->new(PeerAddr=>
                                "jotun.ultrazone.org:80");
                            if ($tempsock) {
                                print $tempsock
                                    "GET /g7/count.php?new=1 HTTP/1.1\r\n".
                                    "Host: jotun.ultrazone.org:80\r\n\r\n";
                                sleep(1);
                                close($tempsock);
                            }
                        }
                    }
                }
            }
            elsif ($arg[3] eq "delold") {
                if (!ha($username)) {
                    privmsg(msg('noaccess', cmd => "DELOLD"), $usernick);
                }
                # insure it is a number
                elsif ($arg[4] !~ /^[\d\.]+$/) {
                    privmsg(msg('usage.delold'), $usernick, 1);
                }
                else {
                    my @oldaccounts = grep { (time()-$rps{$_}{lastlogin}) >
                                             ($arg[4] * 86400) &&
                                             !$rps{$_}{online} } keys(%rps);
                    delete(@rps{@oldaccounts});
                    chanmsg(msg('delold.done', count => scalar(@oldaccounts),
                                days => $arg[4], by => $arg[0]));
                }
            }
            elsif ($arg[3] eq "del") {
                if (!ha($username)) {
                    privmsg(msg('noaccess', cmd => "DEL"), $usernick);
                }
                elsif (!defined($arg[4])) {
                   privmsg(msg('usage.del'), $usernick, 1);
                }
                elsif (!exists($rps{$arg[4]})) {
                    privmsg(msg('nosuch.account', player => $arg[4]),
                            $usernick, 1);
                }
                else {
                    delete($rps{$arg[4]});
                    chanmsg(msg('del.done', player => $arg[4], by => $arg[0]));
                }
            }
            elsif ($arg[3] eq "mkadmin") {
                if (!ha($username) || ($opts{owneraddonly} &&
                    $opts{owner} ne $username)) {
                    privmsg(msg('noaccess', cmd => "MKADMIN"), $usernick);
                }
                elsif (!defined($arg[4])) {
                    privmsg(msg('usage.mkadmin'), $usernick, 1);
                }
                elsif (!exists($rps{$arg[4]})) {
                    privmsg(msg('nosuch.account', player => $arg[4]),
                            $usernick, 1);
                }
                else {
                    $rps{$arg[4]}{isadmin}=1;
                    privmsg(msg('mkadmin.done', player => $arg[4]),
                            $usernick, 1);
                }
            }
            elsif ($arg[3] eq "deladmin") {
                if (!ha($username) || ($opts{ownerdelonly} &&
                    $opts{owner} ne $username)) {
                    privmsg(msg('noaccess', cmd => "DELADMIN"), $usernick);
                }
                elsif (!defined($arg[4])) {
                    privmsg(msg('usage.deladmin'), $usernick, 1);
                }
                elsif (!exists($rps{$arg[4]})) {
                    privmsg(msg('nosuch.account', player => $arg[4]),
                            $usernick, 1);
                }
                elsif ($arg[4] eq $opts{owner}) {
                    privmsg(msg('deladmin.owner'), $usernick, 1);
                }
                else {
                    $rps{$arg[4]}{isadmin}=0;
                    privmsg(msg('deladmin.done', player => $arg[4]),
                            $usernick, 1);
                }
            }
            elsif ($arg[3] eq "hog") {
                if (!ha($username)) {
                    privmsg(msg('noaccess', cmd => "HOG"), $usernick);
                }
                else {
                    chanmsg(msg('hog.summon', nick => $usernick));
                    hog();
                }
            }
            elsif ($arg[3] eq "rehash") {
                if (!ha($username)) {
                    privmsg(msg('noaccess', cmd => "REHASH"), $usernick);
                }
                else {
                    if (rehash()) {
                        privmsg(msg('rehash.done'),$usernick,1);
                    }
                    else {
                        privmsg("Error: Cannot load message table, kept the ".
                                "old one. See the debug log.",$usernick,1);
                    }
                    $opts{botchan} =~ s/ .*//; # strip channel key if present
                }
            }
            elsif ($arg[3] eq "chpass") {
                if (!ha($username)) {
                    privmsg(msg('noaccess', cmd => "CHPASS"), $usernick);
                }
                elsif (!defined($arg[5])) {
                    privmsg(msg('usage.chpass'), $usernick, 1);
                }
                elsif (!exists($rps{$arg[4]})) {
                    privmsg(msg('nosuch.username', player => $arg[4]),
                            $usernick, 1);
                }
                else {
                    $rps{$arg[4]}{pass} = IRPG::Password::hash($arg[5]);
                    privmsg(msg('chpass.done', player => $arg[4]),
                            $usernick, 1);
                }
            }
            elsif ($arg[3] eq "chuser") {
                if (!ha($username)) {
                    privmsg(msg('noaccess', cmd => "CHUSER"), $usernick);
                }
                elsif (!defined($arg[5])) {
                    privmsg(msg('usage.chuser'), $usernick, 1);
                }
                elsif (!exists($rps{$arg[4]})) {
                    privmsg(msg('nosuch.username', player => $arg[4]),
                            $usernick, 1);
                }
                elsif (exists($rps{$arg[5]})) {
                    privmsg(msg('chuser.taken', player => $arg[5]),
                            $usernick,1);
                }
                else {
                    $rps{$arg[5]} = delete($rps{$arg[4]});
                    privmsg(msg('chuser.done', player => $arg[4],
                                new => $arg[5]), $usernick, 1);
                }
            }
            elsif ($arg[3] eq "chclass") {
                if (!ha($username)) {
                    privmsg(msg('noaccess', cmd => "CHCLASS"), $usernick);
                }
                elsif (!defined($arg[5])) {
                    privmsg(msg('usage.chclass'), $usernick, 1);
                }
                elsif (!exists($rps{$arg[4]})) {
                    privmsg(msg('nosuch.username', player => $arg[4]),
                            $usernick, 1);
                }
                else {
                    $rps{$arg[4]}{class} = "@arg[5..$#arg]";
                    privmsg(msg('chclass.done', player => $arg[4],
                                class => "@arg[5..$#arg]"), $usernick, 1);
                }
            }
            elsif ($arg[3] eq "push") {
                if (!ha($username)) {
                    privmsg(msg('noaccess', cmd => "PUSH"), $usernick);
                }
                # insure it's a positive or negative, integral number of seconds
                elsif ($arg[5] !~ /^\-?\d+$/) {
                    privmsg(msg('usage.push'), $usernick, 1);
                }
                elsif (!exists($rps{$arg[4]})) {
                    privmsg(msg('nosuch.username', player => $arg[4]),
                            $usernick, 1);
                }
                elsif ($arg[5] > $rps{$arg[4]}{next}) {
                    privmsg(msg('push.toomuch', player => $arg[4],
                                next => $rps{$arg[4]}{next},
                                seconds => $arg[5]), $usernick, 1);
                    chanmsg(msg('push.all', nick => $usernick,
                                player => $arg[4],
                                seconds => $rps{$arg[4]}{next},
                                level => $rps{$arg[4]}{level}+1));
                    $rps{$arg[4]}{next}=0;
                }
                else {
                    $rps{$arg[4]}{next} -= $arg[5];
                     chanmsg(msg('push.done', nick => $usernick,
                                 player => $arg[4], seconds => $arg[5],
                                 level => $rps{$arg[4]}{level}+1,
                                 time => duration($rps{$arg[4]}{next})));
                }
            }
            elsif ($arg[3] eq "logout") {
                if (defined($username)) {
                    penalize($username,"logout");
                }
                else {
                    privmsg(msg('notloggedin'), $usernick);
                }
            }
            elsif ($arg[3] eq "quest") {
                if (!@{$quest{questers}}) {
                    privmsg(msg('quest.none'),$usernick);
                }
                elsif ($quest{type} == 1) {
                    privmsg(msg('quest.status1', plist(@{$quest{questers}}),
                                text => $quest{text},
                                time => duration($quest{qtime}-time())),
                            $usernick);
                }
                elsif ($quest{type} == 2) {
                    privmsg(msg('quest.status2', plist(@{$quest{questers}}),
                                text => $quest{text},
                                x1 => $quest{p1}->[0], y1 => $quest{p1}->[1],
                                x2 => $quest{p2}->[0], y2 => $quest{p2}->[1]).
                            ($opts{mapurl}?" ".msg('quest.mapurl',
                                                   url => $opts{mapurl}):""),
                            $usernick);
                }
            }
            elsif ($arg[3] eq "status" && $opts{statuscmd}) {
                if (!defined($username)) {
                    privmsg(msg('notloggedin'), $usernick);
                }
                # argument is optional
                elsif ($arg[4] && !exists($rps{$arg[4]})) {
                    privmsg(msg('nosuch.user'),$usernick);
                }
                else {
                    # optional 'user' argument, or look up this user
                    my $u = $arg[4] ? $arg[4] : $username;
                    privmsg(msg('status', player => $u,
                                level => $rps{$u}{level},
                                class => $rps{$u}{class},
                                status => $rps{$u}{online} ?
                                          msg('status.online') :
                                          msg('status.offline'),
                                ttl => duration($rps{$u}{next}),
                                idled => duration($rps{$u}{idled}),
                                sum => itemsum($u)),$usernick);
                }
            }
            elsif ($arg[3] eq "whoami") {
                if (!defined($username)) {
                    privmsg(msg('notloggedin'), $usernick);
                }
                else {
                    privmsg(msg('whoami', player => $username,
                                level => $rps{$username}{level},
                                class => $rps{$username}{class},
                                time => duration($rps{$username}{next})),
                            $usernick);
                }
            }
            elsif ($arg[3] eq "newpass") {
                if (!defined($username)) {
                    privmsg(msg('notloggedin'), $usernick)
                }
                elsif (!defined($arg[4])) {
                    privmsg(msg('usage.newpass'), $usernick);
                }
                else {
                    $rps{$username}{pass} = IRPG::Password::hash($arg[4]);
                    privmsg(msg('newpass.done'),$usernick);
                }
            }
            elsif ($arg[3] eq "align") {
                if (!defined($username)) {
                    privmsg(msg('notloggedin'), $usernick)
                }
                elsif (!defined($arg[4]) || (lc($arg[4]) ne "good" &&
                       lc($arg[4]) ne "neutral" && lc($arg[4]) ne "evil")) {
                    privmsg(msg('usage.align'), $usernick);
                }
                else {
                    $rps{$username}{alignment} = substr(lc($arg[4]),0,1);
                    chanmsg(msg('align.chan', player => $username,
                                alignment => alignname(lc($arg[4]))));
                    privmsg(msg('align.done', alignment => alignname(lc($arg[4]))),
                            $usernick);
                }
            }
            elsif ($arg[3] eq "removeme") {
                if (!defined($username)) {
                    privmsg(msg('notloggedin'), $usernick)
                }
                else {
                    privmsg(msg('removeme.done', player => $username),
                            $usernick);
                    chanmsg(msg('removeme.chan', by => $arg[0],
                                player => $username,
                                class => $rps{$username}{class}));
                    delete($rps{$username});
                }
            }
            elsif ($arg[3] eq "help") {
                if (!ha($username)) {
                    privmsg(msg('help.user', url => $opts{helpurl}),
                            $usernick);
                }
                else {
                    privmsg(msg('help.url', url => $opts{helpurl}),
                            $usernick, 1);
                    privmsg(msg('help.admin', url => $opts{admincommurl}),
                            $usernick, 1);
                }
            }
            elsif ($arg[3] eq "die") {
                if (!ha($username)) {
                    privmsg(msg('noaccess.alt', cmd => "DIE"), $usernick);
                }
                else {
                    $opts{reconnect} = 0;
                    writedb();
                    sts("QUIT :DIE from $arg[0]",1);
                }
            }
            elsif ($arg[3] eq "reloaddb") {
                if (!ha($username)) {
                    privmsg(msg('noaccess.alt', cmd => "RELOADDB"), $usernick);
                }
                elsif (!$pausemode) {
                    privmsg(msg('reloaddb.paused'), $usernick, 1);
                }
                else {
                    loaddb();
                    privmsg(msg('reloaddb.done', count => scalar(keys(%rps))),
                            $usernick,1);
                }
            }
            elsif ($arg[3] eq "backup") {
                if (!ha($username)) {
                    privmsg(msg('noaccess.alt', cmd => "BACKUP"), $usernick);
                }
                else {
                    backup();
                    privmsg(msg('backup.done', file => $opts{dbfile},
                                time => time()),$usernick,1);
                }
            }
            elsif ($arg[3] eq "pause") {
                if (!ha($username)) {
                    privmsg(msg('noaccess.alt', cmd => "PAUSE"), $usernick);
                }
                else {
                    $pausemode = $pausemode ? 0 : 1;
                    privmsg(msg('pause.done', mode => $pausemode),$usernick,1);
                }
            }
            elsif ($arg[3] eq "silent") {
                if (!ha($username)) {
                    privmsg(msg('noaccess.alt', cmd => "SILENT"), $usernick);
                }
                elsif (!defined($arg[4]) || $arg[4] < 0 || $arg[4] > 3) {
                    privmsg(msg('usage.silent'), $usernick,1);
                }
                else {
                    $silentmode = $arg[4];
                    privmsg(msg('silent.done', mode => $silentmode),
                            $usernick,1);
                }
            }
            elsif ($arg[3] eq "jump") {
                if (!ha($username)) {
                    privmsg(msg('noaccess.alt', cmd => "JUMP"), $usernick);
                }
                elsif (!defined($arg[4])) {
                    privmsg(msg('usage.jump'), $usernick, 1);
                }
                else {
                    writedb();
                    sts("QUIT :JUMP to $arg[4] from $arg[0]");
                    unshift(@{$opts{servers}},$arg[4]);
                    close($sock);
                    sleep(3);
                    goto CONNECT;
                }
            }
            elsif ($arg[3] eq "restart") {
                if (!ha($username)) {
                    privmsg(msg('noaccess.alt', cmd => "RESTART"), $usernick);
                }
                else {
                    writedb();
                    sts("QUIT :RESTART from $arg[0]",1);
                    close($sock);
                    exec("perl $0");
                }
            }
            elsif ($arg[3] eq "clearq") {
                if (!ha($username)) {
                    privmsg(msg('noaccess.alt', cmd => "CLEARQ"), $usernick);
                }
                else {
                    undef(@queue);
                    chanmsg(msg('clearq.chan', by => $arg[0]));
                    privmsg(msg('clearq.done'),$usernick,1);
                }
            }
            elsif ($arg[3] eq "info") {
                my $info;
                my $admins = join(", ", map { $rps{$_}{nick} }
                                        grep { $rps{$_}{isadmin} &&
                                               $rps{$_}{online} } keys(%rps));
                if (!ha($username) && $opts{allowuserinfo}) {
                    $info = msg('info.user', version => $version,
                                server => $opts{servers}->[0],
                                admins => $admins);
                    privmsg($info, $usernick);
                }
                elsif (!ha($username) && !$opts{allowuserinfo}) {
                    privmsg(msg('noaccess.alt', cmd => "INFO"), $usernick);
                }
                else {
                    my $queuedbytes = 0;
                    $queuedbytes += (length($_)+2) for @queue; # +2 = \r\n
                    $info = msg('info.admin',
                        sent => sprintf("%.2f", $outbytes/1024),
                        received => sprintf("%.2f", $inbytes/1024),
                        uptime => duration(time()-$^T),
                        online => scalar(grep { $rps{$_}{online} } keys(%rps)),
                        total => scalar(keys(%rps)),
                        registrations => $registrations,
                        pause => $pausemode,
                        silent => $silentmode,
                        qbytes => $queuedbytes,
                        qitems => scalar(@queue),
                        server => $opts{servers}->[0],
                        admins => $admins);
                    privmsg($info, $usernick, 1);
                }
            }
            elsif ($arg[3] eq "login") {
                if (defined($username)) {
                    notice(msg('already.online', player => $username),
                            $usernick);
                }
                else {
                    if ($#arg < 5 || $arg[5] eq "") {
                        notice(msg('usage.login'), $usernick);
                    }
                    elsif (!exists $rps{$arg[4]}) {
                        notice(msg('login.nosuch'),$usernick);
                    }
                    elsif (!exists $onchan{$usernick}) {
                        notice(msg('notonchan', channel => $opts{botchan}),
                                $usernick);
                    }
                    elsif (!IRPG::Password::check($arg[5],
                                                  $rps{$arg[4]}{pass})) {
                        notice(msg('login.wrongpass'), $usernick);
                    }
                    else {
                        # an old DES hash: now that we have the password
                        if (IRPG::Password::legacy($rps{$arg[4]}{pass})) {
                            $rps{$arg[4]}{pass} = IRPG::Password::hash($arg[5]);
                        }
                        if ($opts{voiceonlogin}) {
                            sts("MODE $opts{botchan} +v :$usernick");
                        }
                        $rps{$arg[4]}{online} = 1;
                        $rps{$arg[4]}{nick} = $usernick;
                        $rps{$arg[4]}{userhost} = $arg[0];
                        $rps{$arg[4]}{lastlogin} = time();
                        chanmsg(msg('online', player => $arg[4],
                                    level => $rps{$arg[4]}{level},
                                    class => $rps{$arg[4]}{class},
                                    nick => $usernick,
                                    time => duration($rps{$arg[4]}{next})));
                        notice(msg('login.ok',
                                   time => duration($rps{$arg[4]}{next})),
                               $usernick);
                    }
                }
            }

            #
            # normal users
            # teleport <x> <y>
            #
            elsif ($arg[3] eq "teleport") {
                if ($#arg < 5 || $arg[5] eq "" || (($arg[4] !~ /^\d+$/) && ($arg[5] !~ /^\d+$/))) {
                    privmsg(msg('usage.teleport'), $usernick, 1);
                } else {
                    privmsg(msg('teleport.no'), $usernick, 1, 1);
                }
            }

            #
            # normal users
            # fight <Player>
            #
            elsif ($arg[3] eq "fight") {
                if ($#arg < 4 || $arg[4] eq "") {
                    privmsg(msg('usage.fight'), $usernick, 1);
                } elsif (!exists($rps{$arg[4]})) {
                    privmsg(msg('nosuch.username', player => $arg[4]), $usernick, 1, 1);
                } else {
                    privmsg(msg('fight.no'), $usernick, 1);
                }
            }

            #
            # admin only
            # irc <irc raw command>
            #
            elsif ($arg[3] eq "irc") {
                if (!ha($username)) {
                   privmsg(msg('noaccess.loser'), $usernick, 1);
                } else {
                   privmsg(msg('okay'), $usernick, 1);
                   sts("@arg[4..$#arg]",1);
                }
            }

            #
            # admin only
            # topic
            #
            elsif ($arg[3] eq "topic") {
                if (!ha($username)) {
                   privmsg(msg('noaccess.loser'), $usernick, 1);
                } else {
                   privmsg(msg('okay'), $usernick, 1);
                   # without text, the topic the bot sets itself
                   sts("TOPIC $opts{botchan} :".
                       topic($#arg > 3 ? "@arg[4..$#arg]" : undef), 1);
                }
            }

            #
            # admin only
            # move <Player> <x> <y>
            #
            elsif ($arg[3] eq "move") {
                if (!ha($username)) {
                   privmsg(msg('noaccess.loser'), $usernick, 1);
                } else {
                    if ($#arg < 6 || $arg[6] eq "" || (($arg[5] !~ /^\d+$/) && ($arg[6] !~ /^\d+$/))) {
                        privmsg(msg('usage.move'), $usernick, 1);
                    } elsif (!exists($rps{$arg[4]})) {
                       privmsg(msg('nosuch.username', player => $arg[4]), $usernick, 1, 1);
                    } else {
                        my $old_x = $rps{$arg[4]}{x};
                        my $old_y = $rps{$arg[4]}{y};
                        $rps{$arg[4]}{x} = $arg[5];
                        $rps{$arg[4]}{y} = $arg[6];
                        privmsg(msg('move.done', player => $arg[4], oldx => $old_x,
                                    oldy => $old_y, x => $rps{$arg[4]}{x},
                                    y => $rps{$arg[4]}{y}), $usernick, 1, 1);
                    }
                }
            }

            #
            # admin only
            # pit <Player 1> <Player 2>
            #
            elsif ($arg[3] eq "pit") {
                if (!ha($username)) {
                   privmsg(msg('noaccess.loser'), $usernick, 1);
                } else {
                    if ($#arg < 5 || $arg[5] eq "") {
                        privmsg(msg('usage.pit'), $usernick, 1);
                    } elsif (!exists($rps{$arg[4]})) {
                        privmsg(msg('nosuch.username', player => $arg[4]), $usernick, 1, 1);
                    } elsif (!exists($rps{$arg[5]})) {
                        privmsg(msg('nosuch.username', player => $arg[5]), $usernick, 1, 1);
                    } else {
                       collision_fight($arg[4], $arg[5]);
                       privmsg(msg('pit.done', player => $arg[4], opp => $arg[5]),
                               $usernick, 1);
                    }
                }
            }



        }

        # penalize returns true if user was online and successfully penalized.
        # if the user is not logged in, then penalize() fails. so, if user is
        # offline, and they say something including "http:", and they've been on
        # the channel less than 90 seconds, and the http:-style ban is on, then
        # check to see if their url is in @{$opts{okurl}}. if not, kickban them
        elsif (!penalize($username,"privmsg",length("@arg[3..$#arg]")) &&
               index(lc("@arg[3..$#arg]"),"http:") != -1 &&
               (time()-$onchan{$usernick}) < 90 && $opts{doban}) {
            my $isokurl = 0;
            for (@{$opts{okurl}}) {
                if (index(lc("@arg[3..$#arg]"),lc($_)) != -1) { $isokurl = 1; }
            }
            if (!$isokurl) {
                sts("MODE $opts{botchan} +b $arg[0]");
                sts("KICK $opts{botchan} $usernick :".msg('ban.kick'));
                push(@bans,$arg[0]) if @bans < 12;
            }
        }
    }
}

sub sts { # send to server
    my($text,$skipq) = @_;
    if ($skipq) {
        if ($sock) {
            print $sock "$text\r\n";
            $outbytes += length($text) + 2;
            debug("-> $text");
        }
        else {
            # something is wrong. the socket is closed. clear the queue
            undef(@queue);
            debug("\$sock isn't writeable in sts(), cleared outgoing queue.\n");
            return;
        }
    }
    else {
        push(@queue,$text);
        debug(sprintf("(q%03d) = %s\n",$#queue,$text));
    }
}

sub fq { # deliver message(s) from queue
    if (!@queue) {
        ++$freemessages if $freemessages < 4;
        return undef;
    }
    my $sentbytes = 0;
    for (0..$freemessages) {
        last() if !@queue; # no messages left to send
        # lower number of "free" messages we have left
        my $line=shift(@queue);
        # if we have already sent one message, and the next message to be sent
        # plus the previous messages we have sent this call to fq() > 768 bytes,
        # then requeue this message and return. we don't want to flood off,
        # after all
        if ($_ != 0 && (length($line)+$sentbytes) > 768) {
            unshift(@queue,$line);
            last();
        }
        if ($sock) {
            debug("(fm$freemessages) -> $line");
            --$freemessages if $freemessages > 0;
            print $sock "$line\r\n";
            $sentbytes += length($line) + 2;
        }
        else {
            undef(@queue);
            debug("Disconnected: cleared outgoing message queue.");
            last();
        }
        $outbytes += length($line) + 2;
    }
}

sub ttl { # return ttl
    my $lvl = shift;
    return ($opts{rpbase} * ($opts{rpstep}**$lvl)) if $lvl <= 60;
    return (($opts{rpbase} * ($opts{rpstep}**60))
             + (86400*($lvl - 60)));
}

sub penttl { # return ttl with $opts{rppenstep}
    my $lvl = shift;
    return ($opts{rpbase} * ($opts{rppenstep}**$lvl)) if $lvl <= 60;
    return (($opts{rpbase} * ($opts{rppenstep}**60))
             + (86400*($lvl - 60)));
}

sub duration { # return human duration of seconds
    return $lang->duration(shift);
}

sub loadlang { # (re)load the message table for $opts{lang}
    my $new = eval {
        IRPG::Lang->load($opts{langdir} || "lang", $opts{lang} || "en");
    };
    if (!$new) {
        # die if there is no table yet, otherwise keep the old one
        debug("Error: Cannot load message table: $@", !$lang);
        return 0;
    }
    $lang = $new;
    return 1;
}

sub quitbot { # SIGTERM, SIGINT: save the database, quit IRC and exit
    # before the bot has joined, %rps has everyone offline; writing it would
    # lose the automatic logins of the next start
    writedb() if $lasttime != 1;
    sts("QUIT :Shutting down",1) if $sock;
    exit(0);
}

sub rehash { # reread config file and message table
    readconfig();
    return loadlang();
}

sub msg { # return message $key from the message table, filled in with %args
    return $lang->msg(@_);
}

sub uchars { # UTF-8 text as characters, or undef if it is not UTF-8
    my $text = shift;
    return eval { Encode::decode('UTF-8', $text, Encode::FB_CROAK) };
}

sub ulength { # length in characters of UTF-8 text, in bytes if it is not UTF-8
    my $text = shift;
    return length(uchars($text) // $text);
}

sub usubstr { # the first $n characters of UTF-8 text, or bytes if it is not UTF-8
    my ($text, $n) = @_;
    my $chars = uchars($text);
    return defined($chars) ? Encode::encode('UTF-8', substr($chars, 0, $n))
                           : substr($text, 0, $n);
}

sub nonprint { # whether text has characters that don't print; any byte of text
               # that is not UTF-8 counts as one
    my $text = shift;
    return (uchars($text) // $text) =~ /[[:^print:]]/;
}

sub andlist { # "a, b and c"
    return "" unless @_;
    my $text = pop(@_);
    $text = msg('list.and', a => pop(@_), b => $text) if @_;
    $text = msg('list.comma', a => pop(@_), b => $text) while @_;
    return $text;
}

sub itemargs { # item, item_acc message arguments: names of item $type
    my $type = shift;
    my %names = (
        "ring" => [msg('item.ring'), msg('item.ring.acc')],
        "amulet" => [msg('item.amulet'), msg('item.amulet.acc')],
        "charm" => [msg('item.charm'), msg('item.charm.acc')],
        "weapon" => [msg('item.weapon'), msg('item.weapon.acc')],
        "helm" => [msg('item.helm'), msg('item.helm.acc')],
        "tunic" => [msg('item.tunic'), msg('item.tunic.acc')],
        "pair of gloves" => [msg('item.gloves'), msg('item.gloves.acc')],
        "shield" => [msg('item.shield'), msg('item.shield.acc')],
        "set of leggings" => [msg('item.leggings'), msg('item.leggings.acc')],
        "pair of boots" => [msg('item.boots'), msg('item.boots.acc')],
    );
    return (item => $names{$type}[0], item_acc => $names{$type}[1]);
}

sub alignname { # name of alignment good, neutral or evil
    my %names = (good => msg('align.good'), neutral => msg('align.neutral'),
                 evil => msg('align.evil'));
    return $names{shift()};
}

sub plist { # p1..p4 message arguments for the four questers
    my @p = @_;
    return (p1 => $p[0], p2 => $p[1], p3 => $p[2], p4 => $p[3]);
}

sub ts { # timestamp
    my @ts = localtime(time());
    return sprintf("[%02d/%02d/%02d %02d:%02d:%02d] ",
                   $ts[4]+1,$ts[3],$ts[5]%100,$ts[2],$ts[1],$ts[0]);
}

sub hog { # summon the hand of god
    my @players = grep { $rps{$_}{online} } keys(%rps);
    my $player = $players[rand(@players)];
    my $win = int(rand(5));
    my $time = int(((5 + int(rand(71)))/100) * $rps{$player}{next});
    if ($win) {
        chanmsg(clog(msg('hog.win', player => $player, time => duration($time),
                         level => $rps{$player}{level}+1)));
        $rps{$player}{next} -= $time;
    }
    else {
        chanmsg(clog(msg('hog.lose', player => $player, time => duration($time),
                         level => $rps{$player}{level}+1)));
        $rps{$player}{next} += $time;
    }
    chanmsg(msg('nextlevel', player => $player,
                time => duration($rps{$player}{next})));
}

sub rpcheck { # check levels, update database
    # check splits hash to see if any split users have expired
    checksplits() if $opts{detectsplits};
    # send out $freemessages lines of text from the outgoing message queue
    fq();
    # clear registration limiting
    $lastreg = 0;
    my $online = scalar(grep { $rps{$_}{online} } keys(%rps));
    # there's really nothing to do here if there are no online users, but move
    # the clock on, or the first one to log in gets all the time nobody was
    if (!$online) {
        $lasttime = time() if $lasttime != 1;
        return;
    }
    my $onlineevil = scalar(grep { $rps{$_}{online} &&
                                   $rps{$_}{alignment} eq "e" } keys(%rps));
    my $onlinegood = scalar(grep { $rps{$_}{online} &&
                                   $rps{$_}{alignment} eq "g" } keys(%rps));
    # multiplies the chance of every random event, for testing
    my $rate = $opts{eventrate} || 1;
    if (!$opts{noscale}) {
        if (rand((20*86400)/$opts{self_clock}) < $online*$rate) { hog(); }
        if (rand((24*86400)/$opts{self_clock}) < $online*$rate) { team_battle(); }
        if (rand((8*86400)/$opts{self_clock}) < $online*$rate) { calamity(); }
        if (rand((4*86400)/$opts{self_clock}) < $online*$rate) { godsend(); }
    }
    else {
        hog() if rand(4000) < $rate;
        team_battle() if rand(4000) < $rate;
        calamity() if rand(4000) < $rate;
        godsend() if rand(2000) < $rate;
    }
    if (rand((8*86400)/$opts{self_clock}) < $onlineevil*$rate) { evilness(); }
    if (rand((12*86400)/$opts{self_clock}) < $onlinegood*$rate) { goodness(); }
    if (rand((10*86400)/$opts{self_clock}) < $rate) { war(); }

    moveplayers();
    process_items();
    
    # statements using $rpreport do not bother with scaling by the clock because
    # $rpreport is adjusted by the number of seconds since last rpcheck()
    if (($rpreport%120 < $oldrpreport%120) && $opts{writequestfile}) { writequestfile(); }
    if (time() > $quest{qtime}) {
        if (!@{$quest{questers}}) { quest(); }
        elsif ($quest{type} == 1) {
            chanmsg(clog(msg('quest.done1', plist(@{$quest{questers}}))));
            for (@{$quest{questers}}) {
                $rps{$_}{next} = int($rps{$_}{next} * .75);
            }
            undef(@{$quest{questers}});
            $quest{qtime} = time() + 21600;
        }
        # quest type 2 awards are handled in moveplayers()
    }
    if ($rpreport && ($rpreport%36000 < $oldrpreport%36000)) { # 10 hours
        my @u = ranking();
        chanmsg(msg('top.header')) if @u;
        for my $i (0..4) {
            $#u >= $i and
            chanmsg(msg('top.entry', player => $u[$i],
                        level => $rps{$u[$i]}{level},
                        class => $rps{$u[$i]}{class}, rank => $i + 1,
                        time => duration($rps{$u[$i]}{next})));
        }

        sts("TOPIC $opts{botchan} :".topic(), 1);

        backup();
    }
    if (($rpreport%3600 < $oldrpreport%3600) && $rpreport) { # 1 hour
        my @players = grep { $rps{$_}{online} &&
                             $rps{$_}{level} > 44 } keys(%rps);
        # 20% of all players must be level 45+
        if ((scalar(@players)/scalar(grep { $rps{$_}{online} } keys(%rps))) > .15) {
            challenge_opp($players[int(rand(@players))]);
        }
        while (@bans) {
            sts("MODE $opts{botchan} -bbbb :@bans[0..3]");
            splice(@bans,0,4);
        }
    }
    if ($rpreport%1800 < $oldrpreport%1800) { # 30 mins
        if ($opts{botnick} ne $primnick) {
            sts($opts{botghostcmd}) if $opts{botghostcmd};
            sts("NICK $primnick");
        }
    }
    if (($rpreport%600 < $oldrpreport%600) && $pausemode) { # warn every 10m
        chanmsg("WARNING: Cannot write database in PAUSE mode!");
    }
    # do not write in pause mode, and do not write if not yet connected. (would
    # log everyone out if the bot failed to connect. $lasttime = time() on
    # successful join to $opts{botchan}, initial value is 1). if fails to open
    # $opts{dbfile}, will not update $lasttime and so should have correct values
    # on next rpcheck(). 
    if ($lasttime != 1) {
        my $curtime=time();
        my $levelup = 0;
        for my $k (keys(%rps)) {
            if ($rps{$k}{online} && exists $rps{$k}{nick} &&
                $rps{$k}{nick} && exists $onchan{$rps{$k}{nick}}) {
                $rps{$k}{next} -= ($curtime - $lasttime);
                $rps{$k}{idled} += ($curtime - $lasttime);
                if ($rps{$k}{next} < 1) {
                    my $ttl = int(ttl($rps{$k}{level}));
                    $rps{$k}{level}++;
                    $rps{$k}{next} += $ttl;
                    $levelup = 1;
                    chanmsg(msg('levelup', player => $k,
                                class => $rps{$k}{class},
                                level => $rps{$k}{level},
                                time => duration($ttl)));
                    find_item($k);
                    challenge_opp($k);
                }
            }
            # attempt to make sure this is an actual user
        }
        if (!$pausemode && ($rpreport%60 < $oldrpreport%60)) { writedb(); }
        # the site shows the new level now, not at the next writedb()
        elsif (!$pausemode && $levelup) { writepublic(); }
        $oldrpreport = $rpreport;
        $rpreport += $curtime - $lasttime;
        $lasttime = $curtime;
    }
}

sub war { # let the four quadrants battle
    my @players = grep { $rps{$_}{online} } keys(%rps);
    my @quadrantname = (msg('war.quadrant.0'), msg('war.quadrant.1'),
                        msg('war.quadrant.2'), msg('war.quadrant.3'));
    my %quadrant = ();
    my @sum = (0,0,0,0,0);
    # get quadrant for each player and item sum per quadrant
    for my $k (@players) {
        # "quadrant" 4 is for players in the middle
        $quadrant{$k} = 4;
        if (2 * $rps{$k}{y} + 1 < $opts{mapy}) {
            $quadrant{$k} = 3 if (2 * $rps{$k}{x} + 1 < $opts{mapx});
            $quadrant{$k} = 0 if (2 * $rps{$k}{x} + 1 > $opts{mapx});
        }
        elsif (2 * $rps{$k}{y} + 1 > $opts{mapy})
        {
            $quadrant{$k} = 2 if (2 * $rps{$k}{x} + 1 < $opts{mapx});
            $quadrant{$k} = 1 if (2 * $rps{$k}{x} + 1 > $opts{mapx});
        }
        $sum[$quadrant{$k}] += itemsum($k);
    }
    # roll for each quadrant
    my @roll = (0,0,0,0);
    $roll[$_] = int(rand($sum[$_])) foreach (0..3);
    # winner if value >= maximum value of both direct neighbors, "quadrant" 4 never wins
    my @iswinner = map($_ < 4 && $roll[$_] >= $roll[($_ + 1) % 4] &&
                                 $roll[$_] >= $roll[($_ + 3) % 4],(0..4));
    my @side = map(msg('war.side', quadrant => $quadrantname[$_],
                       roll => $roll[$_], sum => $sum[$_]),(0..3));
    my @winners = map($side[$_],grep($iswinner[$_],(0..3)));
    my $winnertext = "";
    $winnertext = msg('war.winners', list => andlist(@winners)) if (@winners);
    # loser if value < minimum value of both direct neighbors, "quadrant" 4 never loses
    my @isloser = map($_ < 4 && $roll[$_] < $roll[($_ + 1) % 4] &&
                                $roll[$_] < $roll[($_ + 3) % 4],(0..4));
    my @losers = map($side[$_],grep($isloser[$_],(0..3)));
    my $losertext = "";
    $losertext = msg('war.losers', list => andlist(@losers)) if (@losers);
    my @neutrals = map($side[$_],grep(!$iswinner[$_] && !$isloser[$_],(0..3)));
    my $neutraltext = "";
    $neutraltext = " ".msg('war.neutrals', list => andlist(@neutrals))
        if (@neutrals);
    if ($winnertext ne "" && $losertext ne "") {
        # there are winners and losers
        chanmsg(clog(msg('war.both', winners => $winnertext,
                         losers => $losertext, neutrals => $neutraltext)));
    }
    elsif ($winnertext eq "" && $losertext eq "") {
        # there are only neutrals
        chanmsg(clog(msg('war.balanced', neutrals => $neutraltext)));
    }
    else {
        # there are either winners or losers
        chanmsg(clog(msg('war.one', text => "$winnertext$losertext",
                         neutrals => $neutraltext)));
    }
    for my $k (@players) {
        # halve ttl of users in winning quadrant
        # users in "quadrant" 4 are not awarded or penalized
        $rps{$k}{next} = int($rps{$k}{next} / 2) if ($iswinner[$quadrant{$k}]);
        # double ttl of users in losing quadrant
        $rps{$k}{next} *= 2 if ($isloser[$quadrant{$k}]);
    }
}

sub challenge_opp { # pit argument player against random player
    my $u = shift;
    if ($rps{$u}{level} < 25) { return unless rand(4) < 1; }
    my @opps = grep { $rps{$_}{online} && $u ne $_ } keys(%rps);
    return unless @opps;
    my $opp = $opps[int(rand(@opps))];
    $opp = $primnick if rand(@opps+1) < 1;
    my $mysum = itemsum($u,1);
    my $oppsum = itemsum($opp,1);
    my $myroll = int(rand($mysum));
    my $opproll = int(rand($oppsum));
    if ($myroll >= $opproll) {
        my $gain = ($opp eq $primnick)?20:int($rps{$opp}{level}/4);
        $gain = 7 if $gain < 7;
        $gain = int(($gain/100)*$rps{$u}{next});
        chanmsg(clog(msg('challenge.won', player => $u, roll => $myroll,
                         sum => $mysum, opp => $opp, opproll => $opproll,
                         oppsum => $oppsum, time => duration($gain))));
        $rps{$u}{next} -= $gain;
        chanmsg(msg('nextlevel', player => $u,
                    time => duration($rps{$u}{next})));
        my $csfactor = $rps{$u}{alignment} eq "g" ? 50 :
                       $rps{$u}{alignment} eq "e" ? 20 :
                       35;
        if (rand($csfactor) < 1 && $opp ne $primnick) {
            $gain = int(((5 + int(rand(20)))/100) * $rps{$opp}{next});
            chanmsg(clog(msg('critical', player => $u, opp => $opp,
                             time => duration($gain))));
            $rps{$opp}{next} += $gain;
            chanmsg(msg('nextlevel', player => $opp,
                        time => duration($rps{$opp}{next})));
        }
        elsif (rand(25) < 1 && $opp ne $primnick && $rps{$u}{level} > 19) {
            my @items = ("ring","amulet","charm","weapon","helm","tunic",
                         "pair of gloves","set of leggings","shield",
                         "pair of boots");
            my $type = $items[rand(@items)];
            if (itemlevel($rps{$opp}{item}{$type}) > itemlevel($rps{$u}{item}{$type})) {
                chanmsg(clog(msg('battle.item', opp => $opp,
                                 opplevel => itemlevel($rps{$opp}{item}{$type}),
                                 itemargs($type), player => $u,
                                 level => itemlevel($rps{$u}{item}{$type}))));
                my $tempitem = $rps{$u}{item}{$type};
                $rps{$u}{item}{$type}=$rps{$opp}{item}{$type};
                $rps{$opp}{item}{$type} = $tempitem;
            }
        }
    }
    else {
        my $gain = ($opp eq $primnick)?10:int($rps{$opp}{level}/7);
        $gain = 7 if $gain < 7;
        $gain = int(($gain/100)*$rps{$u}{next});
        chanmsg(clog(msg('challenge.lost', player => $u, roll => $myroll,
                         sum => $mysum, opp => $opp, opproll => $opproll,
                         oppsum => $oppsum, time => duration($gain))));
        $rps{$u}{next} += $gain;
        chanmsg(msg('nextlevel', player => $u,
                    time => duration($rps{$u}{next})));
    }
}

sub team_battle { # pit three players against three other players
    my @opp = grep { $rps{$_}{online} } keys(%rps);
    return if @opp < 6;
    # choose random point       
    my $x = int(rand($opts{mapx}));
    my $y = int(rand($opts{mapy}));
    my %polar = ();
    for my $player (@opp) {   
        my $dx = $rps{$player}{x}-$x;
        my $dy = $rps{$player}{y}-$y;
        # polar coordinates
        $polar{$player}{r} = sqrt($dx*$dx+$dy*$dy);
        $polar{$player}{phi} = atan2($dy,$dx)      
    }
    # sort by radius 
    my @sorted = sort { $polar{$a}{r} <=> $polar{$b}{r} } keys %polar;
    # get players at least as close as #6
    @sorted = grep { $polar{$_}{r} <= $polar{$sorted[5]}{r} } @sorted;
    # pick 6 random players from these  
    @opp = ();
    for (my $i = 0; $i < 6; $i++) {
        $opp[$i] = splice(@sorted,int(rand(@sorted)),1);  
    }
    # sort by angle
    @opp = sort { $polar{$a}{phi} <=> $polar{$b}{phi} } @opp;
    # shift splitting position
    my $rot = int(rand(6));
    @opp = @opp[$rot..5,0..$rot-1];  
    my $mysum = itemsum($opp[0],1) + itemsum($opp[1],1) + itemsum($opp[2],1);
    my $oppsum = itemsum($opp[3],1) + itemsum($opp[4],1) + itemsum($opp[5],1);
    my $gain = $rps{$opp[0]}{next};
    for my $p (1,2) {
        $gain = $rps{$opp[$p]}{next} if $gain > $rps{$opp[$p]}{next};
    }
    $gain = int($gain*.20);
    my $myroll = int(rand($mysum));
    my $opproll = int(rand($oppsum));
    my %teams = (p1 => $opp[0], p2 => $opp[1], p3 => $opp[2], p4 => $opp[3],
                 p5 => $opp[4], p6 => $opp[5], roll => $myroll, sum => $mysum,
                 opproll => $opproll, oppsum => $oppsum, x => $x, y => $y,
                 time => duration($gain));
    if ($myroll >= $opproll) {
        chanmsg(clog(msg('teambattle.won', %teams)));
        $rps{$opp[0]}{next} -= $gain;
        $rps{$opp[1]}{next} -= $gain;
        $rps{$opp[2]}{next} -= $gain;
    }
    else {
        chanmsg(clog(msg('teambattle.lost', %teams)));
        $rps{$opp[0]}{next} += $gain;
        $rps{$opp[1]}{next} += $gain;
        $rps{$opp[2]}{next} += $gain;
    }
}

sub itemlevel {
    my $level = shift;
    $level =~ s/\D$//;
    return $level;
}

sub itemtag {
    my $level = shift;
    $level =~ s/^\d+//;
    return $level;
}

sub process_items { # decrease items lying around
    my $curtime = time();

    for my $xy (keys(%mapitems)) {
        for my $i (0..$#{$mapitems{$xy}}) {
            my $level = $mapitems{$xy}[$i]{level};
            my $ttl = int($opts{rpitembase} * ttl(itemlevel($level)) / 600);
            if ($mapitems{$xy}[$i]{lasttime} + $ttl <= $curtime ) {
               $mapitems{$xy}[$i]{lasttime} += $ttl;
               $mapitems{$xy}[$i]{level} = downgrade_item($level);
               splice(@{$mapitems{$xy}},$i,1) if ($mapitems{$xy}[$i]{level} == 0);
               delete($mapitems{$xy}) if (scalar(@{$mapitems{$xy}} == 0));
            }
        }
    }
}

sub drop_item { # drop item on the map
    my $u = shift;
    my $type = shift;
    my $level = shift;
    my $ulevel = itemlevel($level);
    my $x = $rps{$u}{x};
    my $y = $rps{$u}{y};

    push(@{$mapitems{"$x:$y"}},{type=>$type,level=>$level,lasttime=>time()}) if ($ulevel > 0);
}

sub downgrade_item { # returns the decreased item level
    my $level = shift;
    my $ulevel = itemlevel($level);
    my $tag = itemtag($level);
    my %minlevel = (''=>0,a=>50,h=>50,b=>75,d=>150,e=>175,f=>250,g=>300);
    $tag = '' if ($ulevel == $minlevel{$tag});
    $ulevel-- if ($ulevel > 0);
    return "$ulevel$tag";
}

sub exchange_item { # take item and drop the current
    my $u = shift;
    my $type = shift;
    my $level = shift;
    my $ulevel = itemlevel($level);
    my $tag = itemtag($level);

    if ($tag eq 'a') {
        notice(msg('unique.a', level => $ulevel),$rps{$u}{nick});
    }
    elsif ($tag eq 'b') {
        notice(msg('unique.b', level => $ulevel),$rps{$u}{nick});
    }
    elsif ($tag eq 'c') {
        notice(msg('unique.c', level => $ulevel),$rps{$u}{nick});
    }
    elsif ($tag eq 'd') {
        notice(msg('unique.d', level => $ulevel),$rps{$u}{nick});
    }
    elsif ($tag eq 'e') {
        notice(msg('unique.e', level => $ulevel),$rps{$u}{nick});
    }
    elsif ($tag eq 'f') {
        notice(msg('unique.f', level => $ulevel),$rps{$u}{nick});
    }
    elsif ($tag eq 'g') {
        notice(msg('unique.g', level => $ulevel),$rps{$u}{nick});
    }
    elsif ($tag eq 'h') {
        notice(msg('unique.h', level => $ulevel),$rps{$u}{nick});
    }
    else {
        notice(msg('item.better', level => $level, itemargs($type),
                   current => itemlevel($rps{$u}{item}{$type})),
               $rps{$u}{nick});
    }

    drop_item($u,$type,$rps{$u}{item}{$type});
    $rps{$u}{item}{$type} = $level;
}

sub find_item { # find item for argument player
    my $u = shift;
    my @items = ("ring","amulet","charm","weapon","helm","tunic",
                 "pair of gloves","set of leggings","shield","pair of boots");
    my $type = $items[rand(@items)];
    my $level = 1;
    my $ulevel;
    for my $num (1 .. int($rps{$u}{level}*1.5)) {
        if (rand(1.4**($num/4)) < 1) {
            $level = $num;
        }
    }
    if ($rps{$u}{level} >= 25 && rand(40) < 1) {
        $ulevel = 50+int(rand(25));
        if ($ulevel >= $level && $ulevel > itemlevel($rps{$u}{item}{helm})) {
            exchange_item($u,"helm",$ulevel."a");
            return;
        }
    }
    elsif ($rps{$u}{level} >= 25 && rand(40) < 1) {
        $ulevel = 50+int(rand(25));
        if ($ulevel >= $level && $ulevel > itemlevel($rps{$u}{item}{ring})) {
            exchange_item($u,"ring",$ulevel."h");
            return;
        }
    }
    elsif ($rps{$u}{level} >= 30 && rand(40) < 1) {
        $ulevel = 75+int(rand(25));
        if ($ulevel >= $level && $ulevel > itemlevel($rps{$u}{item}{tunic})) {
            exchange_item($u,"tunic",$ulevel."b");
            return;
        }
    }
    elsif ($rps{$u}{level} >= 35 && rand(40) < 1) {
        $ulevel = 100+int(rand(25));
        if ($ulevel >= $level && $ulevel > itemlevel($rps{$u}{item}{amulet})) {
            exchange_item($u,"amulet",$ulevel."c");
            return;
        }
    }
    elsif ($rps{$u}{level} >= 40 && rand(40) < 1) {
        $ulevel = 150+int(rand(25));
        if ($ulevel >= $level && $ulevel > itemlevel($rps{$u}{item}{weapon})) {
            exchange_item($u,"weapon",$ulevel."d");
            return;
        }
    }
    elsif ($rps{$u}{level} >= 45 && rand(40) < 1) {
        $ulevel = 175+int(rand(26));
        if ($ulevel >= $level && $ulevel > itemlevel($rps{$u}{item}{weapon})) {
            exchange_item($u,"weapon",$ulevel."e");
            return;
        }
    }
    elsif ($rps{$u}{level} >= 48 && rand(40) < 1) {
        $ulevel = 250+int(rand(51));
        if ($ulevel >= $level && $ulevel >
            itemlevel($rps{$u}{item}{"pair of boots"})) {
            exchange_item($u,"pair of boots",$ulevel."f");
            return;
        }
    }
    elsif ($rps{$u}{level} >= 52 && rand(40) < 1) {
        $ulevel = 300+int(rand(51));
        if ($ulevel >= $level && $ulevel > itemlevel($rps{$u}{item}{weapon})) {
            exchange_item($u,"weapon",$ulevel."g");
            return;
        }
    }
    if ($level > itemlevel($rps{$u}{item}{$type})) {
        exchange_item($u,$type,$level);
    }
    else {
        notice(msg('item.worse', level => $level, itemargs($type),
                   current => itemlevel($rps{$u}{item}{$type})),
               $rps{$u}{nick});
        drop_item($u,$type,$level);
    }
}

sub loaddb { # load the players and items database
    backup();
    my $l;
    %rps = ();
    if (!open(RPS,$opts{dbfile}) && -e $opts{dbfile}) {
        sts("QUIT :loaddb() failed: $!");
    }
    while ($l=<RPS>) {
        chomp($l);
        next if $l =~ /^#/; # skip comments
        my @i = split("\t",$l);
        print Dumper(@i) if @i != 32;
        if (@i != 32) {
            sts("QUIT: Anomaly in loaddb(); line $. of $opts{dbfile} has ".
                "wrong fields (".scalar(@i).")");
            debug("Anomaly in loaddb(); line $. of $opts{dbfile} has wrong ".
                "fields (".scalar(@i).")",1);
        }
        if (!$sock) { # if not RELOADDB
            if ($i[8]) { $prev_online{$i[7]}=$i[0]; } # log back in
        }
        ($rps{$i[0]}{pass},
        $rps{$i[0]}{isadmin},
        $rps{$i[0]}{level},
        $rps{$i[0]}{class},
        $rps{$i[0]}{next},
        $rps{$i[0]}{nick},
        $rps{$i[0]}{userhost},
        $rps{$i[0]}{online},
        $rps{$i[0]}{idled},
        $rps{$i[0]}{x},
        $rps{$i[0]}{y},
        $rps{$i[0]}{pen_mesg},
        $rps{$i[0]}{pen_nick},
        $rps{$i[0]}{pen_part},
        $rps{$i[0]}{pen_kick},
        $rps{$i[0]}{pen_quit},
        $rps{$i[0]}{pen_quest},
        $rps{$i[0]}{pen_logout},
        $rps{$i[0]}{created},
        $rps{$i[0]}{lastlogin},
        $rps{$i[0]}{item}{amulet},
        $rps{$i[0]}{item}{charm},
        $rps{$i[0]}{item}{helm},
        $rps{$i[0]}{item}{"pair of boots"},
        $rps{$i[0]}{item}{"pair of gloves"},
        $rps{$i[0]}{item}{ring},
        $rps{$i[0]}{item}{"set of leggings"},
        $rps{$i[0]}{item}{shield},
        $rps{$i[0]}{item}{tunic},
        $rps{$i[0]}{item}{weapon},
        $rps{$i[0]}{alignment}) = (@i[1..7],($sock?$i[8]:0),@i[9..$#i]);
    }
    close(RPS);
    debug("loaddb(): loaded ".scalar(keys(%rps))." accounts, ".
          scalar(keys(%prev_online))." previously online.");
    if (!open(ITEMS,$opts{itemdbfile}) && -e $opts{itemdbfile}) {
        sts("QUIT :loaddb() failed: $!");
    }
    my $cnt = 0;
    %mapitems = ();
    while ($l=<ITEMS>) {
        chomp($l);
        next if $l =~ /^#/; # skip comments
        my @i = split("\t",$l);
        print Dumper(@i) if @i != 5;
        if (@i != 5) {
            sts("QUIT: Anomaly in loaddb(); line $. of $opts{itemdbfile} has ".
                "wrong fields (".scalar(@i).")");
            debug("Anomaly in loaddb(); line $. of $opts{itemdbfile} has wrong ".
                "fields (".scalar(@i).")",1);
        }
        my $curtime = time();
        push(@{$mapitems{"$i[0]:$i[1]"}},{type=>$i[2],level=>$i[3],lasttime=>$curtime-$i[4]});
        $cnt++;
    }
    close(ITEMS);
    debug("loaddb(): loaded $cnt items.");
}

sub moveplayers {
    return unless $lasttime > 1;
    my $onlinecount = grep { $rps{$_}{online} } keys %rps;
    return unless $onlinecount;
    for (my $i=0;$i<$opts{self_clock};++$i) {
        # temporary hash to hold player positions, detect collisions
        my %positions = ();
        if ($quest{type} == 2 && @{$quest{questers}}) {
            my $allgo = 1; # have all users reached <p1|p2>?
            for (@{$quest{questers}}) {
                if ($quest{stage}==1) {
                    if ($rps{$_}{x} != $quest{p1}->[0] ||
                        $rps{$_}{y} != $quest{p1}->[1]) {
                        $allgo=0;
                        last();
                    }
                }
                else {
                    if ($rps{$_}{x} != $quest{p2}->[0] ||
                        $rps{$_}{y} != $quest{p2}->[1]) {
                        $allgo=0;
                        last();
                    }
                }
            }
            # all participants have reached point 1, now point 2
            if ($quest{stage}==1 && $allgo) {
                $quest{stage}=2;
                $allgo=0; # have not all reached p2 yet
            }
            elsif ($quest{stage} == 2 && $allgo) {
                chanmsg(clog(msg('quest.done2', plist(@{$quest{questers}}))));
                for (@{$quest{questers}}) {
                    $rps{$_}{next} = int($rps{$_}{next} * .75);
                }
                undef(@{$quest{questers}});
                $quest{qtime} = time() + 21600; # next quest starts in 6 hours
                $quest{type} = 1; # probably not needed
                writequestfile();
            }
            else {
                my(%temp,$player);
                # load keys of %temp with online users
                ++@temp{grep { $rps{$_}{online} } keys(%rps)};
                # delete questers from list
                delete(@temp{@{$quest{questers}}});
                while ($player = each(%temp)) {
                    $rps{$player}{x} += int(rand(3))-1;
                    $rps{$player}{y} += int(rand(3))-1;
                    # if player goes over edge, wrap them back around
                    if ($rps{$player}{x} > $opts{mapx}) { $rps{$player}{x}=0; }
                    if ($rps{$player}{y} > $opts{mapy}) { $rps{$player}{y}=0; }
                    if ($rps{$player}{x} < 0) { $rps{$player}{x}=$opts{mapx}; }
                    if ($rps{$player}{y} < 0) { $rps{$player}{y}=$opts{mapy}; }
                    
                    if (exists($positions{$rps{$player}{x}}{$rps{$player}{y}}) &&
                        !$positions{$rps{$player}{x}}{$rps{$player}{y}}{battled}) {
                        if ($rps{$positions{$rps{$player}{x}}{$rps{$player}{y}}{user}}{isadmin} &&
                            !$rps{$player}{isadmin} && rand(100) < 1) {
                            chanmsg(msg('bows', player => $player,
                               admin => $positions{$rps{$player}{x}}{$rps{$player}{y}}{user}));
                        }
                        if (rand($onlinecount) < 1) {
                            $positions{$rps{$player}{x}}{$rps{$player}{y}}{battled}=1;
                            collision_fight($player,
                                $positions{$rps{$player}{x}}{$rps{$player}{y}}{user});
                        }
                    }
                    else {
                        $positions{$rps{$player}{x}}{$rps{$player}{y}}{battled}=0;
                        $positions{$rps{$player}{x}}{$rps{$player}{y}}{user}=$player;
                    }
                }
                for (@{$quest{questers}}) {
                    if ($quest{stage} == 1) {
                        if (rand(100) < 1) {
                            if ($rps{$_}{x} != $quest{p1}->[0]) {
                                $rps{$_}{x} += ($rps{$_}{x} < $quest{p1}->[0] ?
                                                1 : -1);
                            }
                            if ($rps{$_}{y} != $quest{p1}->[1]) {
                                $rps{$_}{y} += ($rps{$_}{y} < $quest{p1}->[1] ?
                                                1 : -1);
                            }
                        }
                    }
                    elsif ($quest{stage}==2) {
                        if (rand(100) < 1) {
                            if ($rps{$_}{x} != $quest{p2}->[0]) {
                                $rps{$_}{x} += ($rps{$_}{x} < $quest{p2}->[0] ?
                                                1 : -1);
                            }
                            if ($rps{$_}{y} != $quest{p2}->[1]) {
                                $rps{$_}{y} += ($rps{$_}{y} < $quest{p2}->[1] ?
                                                1 : -1);
                            }
                        }
                    }
                }
            }
        }
        else {
            for my $player (keys(%rps)) {
                next unless $rps{$player}{online};
                $rps{$player}{x} += int(rand(3))-1;
                $rps{$player}{y} += int(rand(3))-1;
                # if player goes over edge, wrap them back around
                if ($rps{$player}{x} > $opts{mapx}) { $rps{$player}{x} = 0; }
                if ($rps{$player}{y} > $opts{mapy}) { $rps{$player}{y} = 0; }
                if ($rps{$player}{x} < 0) { $rps{$player}{x} = $opts{mapx}; }
                if ($rps{$player}{y} < 0) { $rps{$player}{y} = $opts{mapy}; }
                if (exists($positions{$rps{$player}{x}}{$rps{$player}{y}}) &&
                    !$positions{$rps{$player}{x}}{$rps{$player}{y}}{battled}) {
                    if ($rps{$positions{$rps{$player}{x}}{$rps{$player}{y}}{user}}{isadmin} &&
                        !$rps{$player}{isadmin} && rand(100) < 1) {
                        chanmsg(msg('bows', player => $player,
                           admin => $positions{$rps{$player}{x}}{$rps{$player}{y}}{user}));
                    }
                    if (rand($onlinecount) < 1) {
                        $positions{$rps{$player}{x}}{$rps{$player}{y}}{battled}=1;
                        collision_fight($player,
                            $positions{$rps{$player}{x}}{$rps{$player}{y}}{user});
                    }
                }
                else {
                    $positions{$rps{$player}{x}}{$rps{$player}{y}}{battled}=0;
                    $positions{$rps{$player}{x}}{$rps{$player}{y}}{user}=$player;
                }
            }
        }
        # pick up items lying around
        for my $u (keys(%rps)) {
            next unless $rps{$u}{online};
            my $x = $rps{$u}{x};
            my $y = $rps{$u}{y};
            next unless exists($mapitems{"$x:$y"});
            for $i (0..$#{$mapitems{"$x:$y"}}) {
                my $item = $mapitems{"$x:$y"}[$i];
                if (itemlevel($item->{level}) > itemlevel($rps{$u}{item}{$item->{type}})) {
                    exchange_item($u,$item->{type},$item->{level});
                    splice(@{$mapitems{"$x:$y"}},$i,1);
                }
            }
        }
    }
}

sub chanmsg { # send a message to the channel
    my $msg = shift or return undef;
    if ($silentmode & 1) { return undef; }
    privmsg($msg, $opts{botchan}, shift);
}

sub privmsg { # send a message to an arbitrary entity
    my $msg = shift or return undef;
    my $target = shift or return undef;
    my $force = shift;
    if (($silentmode == 3 || ($target !~ /^[\+\&\#]/ && $silentmode == 2))
        && !$force) {
        return undef;
    }
    while (length($msg)) {
        sts("PRIVMSG $target :".substr($msg,0,450),$force);
        substr($msg,0,450)="";
    }
}

sub notice { # send a notice to an arbitrary entity
    my $msg = shift or return undef;
    my $target = shift or return undef;
    my $force = shift;
    if (($silentmode == 3 || ($target !~ /^[\+\&\#]/ && $silentmode == 2))
        && !$force) {
        return undef;
    }
    while (length($msg)) {
        sts("NOTICE $target :".substr($msg,0,450),$force);
        substr($msg,0,450)="";
    }
}

sub help { # print help message
    (my $prog = $0) =~ s/^.*\///;

    print "
usage: $prog [OPTIONS]
  --help, -h           Print this message
  --verbose, -v        Print verbose messages
  --server, -s         Specify IRC server:port to connect to
  --botnick, -n        Bot's IRC nick
  --botuser, -u        Bot's username
  --botrlnm, -r        Bot's real name
  --botchan, -c        IRC channel to join
  --botident, -p       Specify identify-to-services command
  --botmodes, -m       Specify usermodes for the bot to set upon connect
  --botopcmd, -o       Specify command to send to server on successful connect
  --botghostcmd, -g    Specify command to send to server to regain primary
                       nickname when in use
  --doban              Advertisement ban on/off flag
  --okurl, -k          Bot will not ban for web addresses that contain these
                       strings
  --debug              Debug on/off flag
  --helpurl            URL to refer new users to
  --admincommurl       URL to refer admins to

  Timing parameters:
  --rpbase             Base time to level up
  --rpstep             Time to next level = rpbase * (rpstep ** CURRENT_LEVEL)
  --rppenstep          PENALTY_SECS=(PENALTY*(RPPENSTEP**CURRENT_LEVEL))

";
}

sub itemsum {
    my $user = shift;
    # is this for a battle? if so, good users get a 10% boost and evil users get
    # a 10% detriment
    my $battle = shift;
    return -1 unless defined $user;
    my $sum = 0;
    if ($user eq $primnick) {
        for my $u (keys(%rps)) {
            $sum = itemsum($u) if $sum < itemsum($u);
        }
        return $sum+1;
    }
    if (!exists($rps{$user})) { return -1; }
    $sum += itemlevel($rps{$user}{item}{$_}) for keys(%{$rps{$user}{item}});
    if ($battle) {
        return $rps{$user}{alignment} eq 'e' ? int($sum*.9) :
               $rps{$user}{alignment} eq 'g' ? int($sum*1.1) :
               $sum;
    }
    return $sum;
}

sub daemonize() {
    # win32 doesn't daemonize (this way?)
    if ($^O eq "MSWin32") {
        print debug("Nevermind, this is Win32, no I'm not.")."\n";
        return;
    }
    use POSIX 'setsid';
    $SIG{CHLD} = sub { };
    fork() && exit(0); # kill parent
    POSIX::setsid() || debug("POSIX::setsid() failed: $!",1);
    $SIG{CHLD} = sub { };
    fork() && exit(0); # kill the parent as the process group leader
    $SIG{CHLD} = sub { };
    open(STDIN,'/dev/null') || debug("Cannot read /dev/null: $!",1);
    open(STDOUT,'>/dev/null') || debug("Cannot write to /dev/null: $!",1);
    open(STDERR,'>/dev/null') || debug("Cannot write to /dev/null: $!",1);
    # write our PID to $opts{pidfile}, or return semi-silently on failure
    open(PIDFILE,">$opts{pidfile}") || do {
        debug("Error: failed opening pid file: $!");
        return;
    };
    print PIDFILE $$;
    close(PIDFILE);
}

sub calamity { # suffer a little one
    my @players = grep { $rps{$_}{online} } keys(%rps);
    return unless @players;
    my $player = $players[rand(@players)];
    if (rand(10) < 1) {
        my @items = ("amulet","charm","weapon","tunic","set of leggings",
                     "shield");
        my $type = $items[rand(@items)];
        if ($type eq "amulet") {
            chanmsg(clog(msg('calamity.amulet', player => $player)));
        }
        elsif ($type eq "charm") {
            chanmsg(clog(msg('calamity.charm', player => $player)));
        }
        elsif ($type eq "weapon") {
            chanmsg(clog(msg('calamity.weapon', player => $player)));
        }
        elsif ($type eq "tunic") {
            chanmsg(clog(msg('calamity.tunic', player => $player)));
        }
        elsif ($type eq "shield") {
            chanmsg(clog(msg('calamity.shield', player => $player)));
        }
        else {
            chanmsg(clog(msg('calamity.leggings', player => $player)));
        }
        my $suffix="";
        if ($rps{$player}{item}{$type} =~ /(\D)$/) { $suffix=$1; }
        $rps{$player}{item}{$type} = int(itemlevel($rps{$player}{item}{$type}) * .9);
        $rps{$player}{item}{$type}.=$suffix;
    }
    else {
        my $time = int(int(5 + rand(8)) / 100 * $rps{$player}{next});
        if (!open(Q,$opts{eventsfile})) {
            return chanmsg("ERROR: Failed to open $opts{eventsfile}: $!");
        }
        my($i,$actioned);
        while (my $line = <Q>) {
            chomp($line);
            if ($line =~ /^C (.*)/ && rand(++$i) < 1) { $actioned = $1; }
        }
        chanmsg(clog(msg('calamity', player => $player, event => $actioned,
                         time => duration($time),
                         level => $rps{$player}{level}+1)));
        $rps{$player}{next} += $time;
        chanmsg(msg('nextlevel', player => $player,
                    time => duration($rps{$player}{next})));
    }
}

sub godsend { # bless the unworthy
    my @players = grep { $rps{$_}{online} } keys(%rps);
    return unless @players;
    my $player = $players[rand(@players)];
    if (rand(10) < 1) {
        my @items = ("amulet","charm","weapon","tunic","set of leggings",
                     "shield");
        my $type = $items[rand(@items)];
        if ($type eq "amulet") {
            chanmsg(clog(msg('godsend.amulet', player => $player)));
        }
        elsif ($type eq "charm") {
            chanmsg(clog(msg('godsend.charm', player => $player)));
        }
        elsif ($type eq "weapon") {
            chanmsg(clog(msg('godsend.weapon', player => $player)));
        }
        elsif ($type eq "tunic") {
            chanmsg(clog(msg('godsend.tunic', player => $player)));
        }
        elsif ($type eq "shield") {
            chanmsg(clog(msg('godsend.shield', player => $player)));
        }
        else {
            chanmsg(clog(msg('godsend.leggings', player => $player)));
        }
        my $suffix="";
        if ($rps{$player}{item}{$type} =~ /(\D)$/) { $suffix=$1; }
        $rps{$player}{item}{$type} = int(itemlevel($rps{$player}{item}{$type}) * 1.1);
        $rps{$player}{item}{$type}.=$suffix;
    }
    else {
        my $time = int(int(5 + rand(8)) / 100 * $rps{$player}{next});
        my $actioned;
        if (!open(Q,$opts{eventsfile})) {
            return chanmsg("ERROR: Failed to open $opts{eventsfile}: $!");
        }
        my $i;
        while (my $line = <Q>) {
            chomp($line);
            if ($line =~ /^G (.*)/ && rand(++$i) < 1) {
                $actioned = $1;
            }
        }
        chanmsg(clog(msg('godsend', player => $player, event => $actioned,
                         time => duration($time),
                         level => $rps{$player}{level}+1)));
        $rps{$player}{next} -= $time;
        chanmsg(msg('nextlevel', player => $player,
                    time => duration($rps{$player}{next})));
    }
}
#
# initializes the quest
#
sub quest {
    @{$quest{questers}} = grep { $rps{$_}{online} && $rps{$_}{level} > 39 &&
                                 time()-$rps{$_}{lastlogin}>36000 } keys(%rps);
    if (@{$quest{questers}} < 4) { return undef(@{$quest{questers}}); }
    while (@{$quest{questers}} > 4) {
        splice(@{$quest{questers}},int(rand(@{$quest{questers}})),1);
    }
    if (!open(Q,$opts{eventsfile})) {
        return chanmsg("ERROR: Failed to open $opts{eventsfile}: $!");
    }
    my $i;
    while (my $line = <Q>) {
        chomp($line);
        if ($line =~ /^Q/ && rand(++$i) < 1) {
            if ($line =~ /^Q1 (.*)/) {
                $quest{text} = $1;
                $quest{type} = 1;
                $quest{qtime} = time() + 43200 + int(rand(43201)); # 12-24 hours
            }
            elsif ($line =~ /^Q2 (\d+) (\d+) (\d+) (\d+) (.*)/) {
                $quest{p1} = [$1,$2];
                $quest{p2} = [$3,$4];
                $quest{text} = $5;
                $quest{type} = 2;
                $quest{stage} = 1;
            }
        }
    }
    close(Q);
    if ($quest{type} == 1) {
        chanmsg(msg('quest.start1', plist(@{$quest{questers}}),
                    text => $quest{text},
                    time => duration($quest{qtime}-time())));
    }
    elsif ($quest{type} == 2) {
        chanmsg(msg('quest.start2', plist(@{$quest{questers}}),
                    text => $quest{text},
                    x1 => $quest{p1}->[0], y1 => $quest{p1}->[1],
                    x2 => $quest{p2}->[0], y2 => $quest{p2}->[1]).
                ($opts{mapurl}?" ".msg('quest.mapurl', url => $opts{mapurl}):""));
    }
    writequestfile();
}

sub questpencheck {
    my $k = shift;
    my ($quester,$player);
    for $quester (@{$quest{questers}}) {
        if ($quester eq $k) {
            chanmsg(clog(msg('quest.fail', player => $k)));
            for $player (grep { $rps{$_}{online} } keys %rps) {
                my $gain = int(15 * penttl($rps{$player}{level}) / $opts{rpbase});
                $rps{$player}{pen_quest} += $gain;
                $rps{$player}{next} += $gain;
            }
            undef(@{$quest{questers}});
            $quest{qtime} = time() + 43200; # 12 hours
        }
    }
}

sub clog {
    my $mesg = shift;
    open(B,">>$opts{modsfile}") or do {
        debug("Error: Cannot open $opts{modsfile}: $!");
        chanmsg("Error: Cannot open $opts{modsfile}: $!");
        return $mesg;
    };
    print B ts()."$mesg\n";
    close(B);
    return $mesg;
}

sub backup() {
    if (! -d ".dbbackup/") { mkdir(".dbbackup",0700); }
    if ($^O ne "MSWin32") {
        system("cp $opts{dbfile} .dbbackup/$opts{dbfile}".time());
        system("cp $opts{itemdbfile} .dbbackup/$opts{itemdbfile}".time());
    }
    else {
        system("copy $opts{dbfile} .dbbackup\\$opts{dbfile}".time());
        system("copy $opts{itemdbfile} .dbbackup\\$opts{itemdbfile}".time());
    }
}

sub penalize {
    my $username = shift;
    return 0 if !defined($username);
    return 0 if !exists($rps{$username});
    my $type = shift;
    my $pen = 0;
    questpencheck($username);
    if ($type eq "quit") {
        $pen = int(20 * penttl($rps{$username}{level}) / $opts{rpbase});
        if ($opts{limitpen} && $pen > $opts{limitpen}) {
            $pen = $opts{limitpen};
        }
        $rps{$username}{pen_quit}+=$pen;
        $rps{$username}{online}=0;
    }
    elsif ($type eq "nick") {
        my $newnick = shift;
        $pen = int(30 * penttl($rps{$username}{level}) / $opts{rpbase});
        if ($opts{limitpen} && $pen > $opts{limitpen}) {
            $pen = $opts{limitpen};
        }
        $rps{$username}{pen_nick}+=$pen;
        $rps{$username}{nick} = substr($newnick,1);
        $rps{$username}{userhost} =~ s/^[^!]+/$rps{$username}{nick}/e;
        notice(msg('penalty.nick', time => duration($pen)),
               $rps{$username}{nick});
    }
    elsif ($type eq "privmsg" || $type eq "notice") {
        $pen = int(shift(@_) * penttl($rps{$username}{level}) / $opts{rpbase});
        if ($opts{limitpen} && $pen > $opts{limitpen}) {
            $pen = $opts{limitpen};
        }
        $rps{$username}{pen_mesg}+=$pen;
        notice($type eq "privmsg" ?
               msg('penalty.privmsg', time => duration($pen)) :
               msg('penalty.notice', time => duration($pen)),
               $rps{$username}{nick});
    }
    elsif ($type eq "part") {
        $pen = int(200 * penttl($rps{$username}{level}) / $opts{rpbase});
        if ($opts{limitpen} && $pen > $opts{limitpen}) {
            $pen = $opts{limitpen};
        }
        $rps{$username}{pen_part}+=$pen;
        notice(msg('penalty.part', time => duration($pen)),
               $rps{$username}{nick});
        $rps{$username}{online}=0;
    }
    elsif ($type eq "kick") {
        $pen = int(250 * penttl($rps{$username}{level}) / $opts{rpbase});
        if ($opts{limitpen} && $pen > $opts{limitpen}) {
            $pen = $opts{limitpen};
        }
        $rps{$username}{pen_kick}+=$pen;
        notice(msg('penalty.kick', time => duration($pen)),
               $rps{$username}{nick});
        $rps{$username}{online}=0;
    }
    elsif ($type eq "logout") {
        $pen = int(20 * penttl($rps{$username}{level}) / $opts{rpbase});
        if ($opts{limitpen} && $pen > $opts{limitpen}) {
            $pen = $opts{limitpen};
        }
        $rps{$username}{pen_logout} += $pen;
        notice(msg('penalty.logout', time => duration($pen)),
               $rps{$username}{nick});
        $rps{$username}{online}=0;
    }
    $rps{$username}{next} += $pen;
    return 1; # successfully penalized a user! woohoo!
}

sub debug {
    (my $text = shift) =~ s/[\r\n]//g;
    $text = IRPG::Password::redact($text);
    my $die = shift;
    if ($opts{debug} || $opts{verbose}) {
        open(DBG,">>$opts{debugfile}") or do {
            chanmsg("Error: Cannot open debug file: $!");
            return;
        };
        print DBG ts()."$text\n";
        close(DBG);
    }
    if ($die) { die("$text\n"); }
    return $text;
}

sub finduser {
    my $nick = shift;
    return undef if !defined($nick);
    for my $user (keys(%rps)) {
        next unless $rps{$user}{online};
        if ($rps{$user}{nick} eq $nick) { return $user; }
    }
    return undef;
}

sub ha { # return 0/1 if username has access
    my $user = shift;
    if (!defined($user) || !exists($rps{$user})) {
        debug("Error: Attempted ha() for invalid username \"$user\"");
        return 0;
    }
    return $rps{$user}{isadmin};
}

sub checksplits { # removed expired split hosts from the hash
    my $host;
    while ($host = each(%split)) {
        if (time()-$split{$host}{time} > $opts{splitwait}) {
            $rps{$split{$host}{account}}{online} = 0;
            delete($split{$host});
        }
    }
}

sub collision_fight {
    my($u,$opp) = @_;
    my $mysum = itemsum($u,1);
    my $oppsum = itemsum($opp,1);
    my $myroll = int(rand($mysum));
    my $opproll = int(rand($oppsum));
    if ($myroll >= $opproll) {
        my $gain = int($rps{$opp}{level}/4);
        $gain = 7 if $gain < 7;
        $gain = int(($gain/100)*$rps{$u}{next});
        chanmsg(clog(msg('collision.won', player => $u, roll => $myroll,
                         sum => $mysum, opp => $opp, opproll => $opproll,
                         oppsum => $oppsum, time => duration($gain))));
        $rps{$u}{next} -= $gain;
        chanmsg(msg('nextlevel', player => $u,
                    time => duration($rps{$u}{next})));
        if (rand(35) < 1 && $opp ne $primnick) {
            $gain = int(((5 + int(rand(20)))/100) * $rps{$opp}{next});
            chanmsg(clog(msg('critical', player => $u, opp => $opp,
                             time => duration($gain))));
            $rps{$opp}{next} += $gain;
            chanmsg(msg('nextlevel', player => $opp,
                        time => duration($rps{$opp}{next})));
        }
        elsif (rand(25) < 1 && $opp ne $primnick && $rps{$u}{level} > 19) {
            my @items = ("ring","amulet","charm","weapon","helm","tunic",
                         "pair of gloves","set of leggings","shield",
                         "pair of boots");
            my $type = $items[rand(@items)];
            if (itemlevel($rps{$opp}{item}{$type}) > itemlevel($rps{$u}{item}{$type})) {
                chanmsg(msg('battle.item', opp => $opp,
                            opplevel => itemlevel($rps{$opp}{item}{$type}),
                            itemargs($type), player => $u,
                            level => itemlevel($rps{$u}{item}{$type})));
                my $tempitem = $rps{$u}{item}{$type};
                $rps{$u}{item}{$type}=$rps{$opp}{item}{$type};
                $rps{$opp}{item}{$type} = $tempitem;
            }
        }
    }
    else {
        my $gain = ($opp eq $primnick)?10:int($rps{$opp}{level}/7);
        $gain = 7 if $gain < 7;
        $gain = int(($gain/100)*$rps{$u}{next});
        chanmsg(clog(msg('collision.lost', player => $u, roll => $myroll,
                         sum => $mysum, opp => $opp, opproll => $opproll,
                         oppsum => $oppsum, time => duration($gain))));
        $rps{$u}{next} += $gain;
        chanmsg(msg('nextlevel', player => $u,
                    time => duration($rps{$u}{next})));
    }
}

sub writequestfile {
    return unless $opts{writequestfile};
    open(QF,">$opts{questfilename}") or do {
        chanmsg("Error: Cannot open $opts{questfilename}: $!");
        return;
    };
    # if no active quest, just empty questfile. otherwise, write it
    if (@{$quest{questers}}) {
        if ($quest{type}==1) {
            print QF "T $quest{text}\n".
                     "Y 1\n".
                     "S $quest{qtime}\n".
                     "P1 $quest{questers}->[0]\n".
                     "P2 $quest{questers}->[1]\n".
                     "P3 $quest{questers}->[2]\n".
                     "P4 $quest{questers}->[3]\n";
        }
        elsif ($quest{type}==2) {
            print QF "T $quest{text}\n".
                     "Y 2\n".
                     "S $quest{stage}\n".
                     "P $quest{p1}->[0] $quest{p1}->[1] $quest{p2}->[0] ".
                        "$quest{p2}->[1]\n".
                     "P1 $quest{questers}->[0] $rps{$quest{questers}->[0]}{x} ".
                         "$rps{$quest{questers}->[0]}{y}\n".
                     "P2 $quest{questers}->[1] $rps{$quest{questers}->[1]}{x} ".
                         "$rps{$quest{questers}->[1]}{y}\n".
                     "P3 $quest{questers}->[2] $rps{$quest{questers}->[2]}{x} ".
                         "$rps{$quest{questers}->[2]}{y}\n".
                     "P4 $quest{questers}->[3] $rps{$quest{questers}->[3]}{x} ".
                         "$rps{$quest{questers}->[3]}{y}\n";
        }
    }
    close(QF);
}

sub goodness {
    my @players = grep { $rps{$_}{alignment} eq "g" &&
                         $rps{$_}{online} } keys(%rps);
    return unless @players > 1;
    splice(@players,int(rand(@players)),1) while @players > 2;
    my $gain = 5 + int(rand(8));
    chanmsg(clog(msg('goodness', p1 => $players[0], p2 => $players[1],
                     gain => $gain)));
    $rps{$players[0]}{next} = int($rps{$players[0]}{next}*(1 - ($gain/100)));
    $rps{$players[1]}{next} = int($rps{$players[1]}{next}*(1 - ($gain/100)));
    chanmsg(msg('nextlevel', player => $players[0],
                time => duration($rps{$players[0]}{next})));
    chanmsg(msg('nextlevel', player => $players[1],
                time => duration($rps{$players[1]}{next})));
}

sub evilness {
    my @evil = grep { $rps{$_}{alignment} eq "e" &&
                      $rps{$_}{online} } keys(%rps);
    return unless @evil;
    my $me = $evil[rand(@evil)];
    if (int(rand(2)) < 1) {
        # evil only steals from good :^(
        my @good = grep { $rps{$_}{alignment} eq "g" &&
                          $rps{$_}{online} } keys(%rps);
        my $target = $good[rand(@good)];
        my @items = ("ring","amulet","charm","weapon","helm","tunic",
                     "pair of gloves","set of leggings","shield",
                     "pair of boots");
        my $type = $items[rand(@items)];
        if (itemlevel($rps{$target}{item}{$type}) > itemlevel($rps{$me}{item}{$type})) {
            my $tempitem = $rps{$me}{item}{$type};
            $rps{$me}{item}{$type} = $rps{$target}{item}{$type};
            $rps{$target}{item}{$type} = $tempitem;
            chanmsg(clog(msg('evil.steal', player => $me, target => $target,
                             level => itemlevel($rps{$me}{item}{$type}),
                             itemargs($type),
                             oldlevel => itemlevel($rps{$target}{item}{$type}))));
        }
        else {
            notice(msg('evil.fail', target => $target, itemargs($type)),
                   $rps{$me}{nick});
        }
    }
    else { # being evil only pays about half of the time...
        my $gain = 1 + int(rand(5));
        chanmsg(clog(msg('evil.forsaken', player => $me,
                         time => duration(int($rps{$me}{next} * ($gain/100))))));
        $rps{$me}{next} = int($rps{$me}{next} * (1 + ($gain/100)));
        chanmsg(msg('nextlevel', player => $me,
                    time => duration($rps{$me}{next})));
    }
}

sub writedb {
    # each file is written next to the old one and renamed over it, so a crash
    # or a full disk never leaves a cut-off database
    open(RPS,">$opts{dbfile}.tmp") or do {
        chanmsg("ERROR: Cannot write $opts{dbfile}.tmp: $!");
        return 0;
    };
    print RPS join("\t","# username",
                        "pass",
                        "is admin",
                        "level",
                        "class",
                        "next ttl",
                        "nick",
                        "userhost",
                        "online",
                        "idled",
                        "x pos",
                        "y pos",
                        "pen_mesg",
                        "pen_nick",
                        "pen_part",
                        "pen_kick",
                        "pen_quit",
                        "pen_quest",
                        "pen_logout",
                        "created",
                        "last login",
                        "amulet",
                        "charm",
                        "helm",
                        "boots",
                        "gloves",
                        "ring",
                        "leggings",
                        "shield",
                        "tunic",
                        "weapon",
                        "alignment")."\n";
    my $k;
    keys(%rps); # reset internal pointer
    while ($k=each(%rps)) {
        if (exists($rps{$k}{next}) && defined($rps{$k}{next})) {
            print RPS join("\t",$k,
                                $rps{$k}{pass},
                                $rps{$k}{isadmin},
                                $rps{$k}{level},
                                $rps{$k}{class},
                                $rps{$k}{next},
                                $rps{$k}{nick},
                                $rps{$k}{userhost},
                                $rps{$k}{online},
                                $rps{$k}{idled},
                                $rps{$k}{x},
                                $rps{$k}{y},
                                $rps{$k}{pen_mesg},
                                $rps{$k}{pen_nick},
                                $rps{$k}{pen_part},
                                $rps{$k}{pen_kick},
                                $rps{$k}{pen_quit},
                                $rps{$k}{pen_quest},
                                $rps{$k}{pen_logout},
                                $rps{$k}{created},
                                $rps{$k}{lastlogin},
                                $rps{$k}{item}{amulet},
                                $rps{$k}{item}{charm},
                                $rps{$k}{item}{helm},
                                $rps{$k}{item}{"pair of boots"},
                                $rps{$k}{item}{"pair of gloves"},
                                $rps{$k}{item}{ring},
                                $rps{$k}{item}{"set of leggings"},
                                $rps{$k}{item}{shield},
                                $rps{$k}{item}{tunic},
                                $rps{$k}{item}{weapon},
                                $rps{$k}{alignment})."\n";
        }
    }
    close(RPS) && rename("$opts{dbfile}.tmp",$opts{dbfile}) or do {
        chanmsg("ERROR: Cannot write $opts{dbfile}: $!");
        return 0;
    };
    open(ITEMS,">$opts{itemdbfile}.tmp") or do {
        chanmsg("ERROR: Cannot write $opts{itemdbfile}.tmp: $!");
        return 0;
    };
    print ITEMS join("\t","# x pos",
                        "y pos",
                        "type",
                        "level",
                        "age")."\n";
    my $curtime = time();
    for my $xy (keys(%mapitems)) {
        for my $i (0..$#{$mapitems{$xy}}) {
            my @coords = split(/:/,$xy);
            print ITEMS join("\t",$coords[0],
                                  $coords[1],
                                  $mapitems{$xy}[$i]{type},
                                  $mapitems{$xy}[$i]{level},
                                  $curtime-$mapitems{$xy}[$i]{lasttime})."\n";
        }
    }
    close(ITEMS) && rename("$opts{itemdbfile}.tmp",$opts{itemdbfile}) or do {
        chanmsg("ERROR: Cannot write $opts{itemdbfile}: $!");
        return 0;
    };
    writepublic();
}

sub npcs { # the characters the npc option marks as NPCs
    return split(/[\s,]+/,$opts{npc} // "");
}

sub ranking { # players by level, then by time to the next; NPCs aren't ranked
    my %npc = map { $_ => 1 } npcs();
    return sort { $rps{$b}{level} <=> $rps{$a}{level} ||
                  $rps{$a}{next}  <=> $rps{$b}{next} }
           grep { !$npc{$_} } keys(%rps);
}

sub topic { # the channel topic: the helpurl, or $text, and the top three
    my $text = shift;
    my @top = grep { defined } (ranking())[0..2];
    my $list;
    for my $i (0..$#top) {
        my $entry = msg('topic.entry', rank => $i+1, player => $top[$i],
                        level => $rps{$top[$i]}{level},
                        class => $rps{$top[$i]}{class});
        $list = defined($list) ? msg('topic.join', a => $list, b => $entry)
                               : $entry;
    }
    if (defined($text)) {
        return @top ? msg('topic.custom', text => $text, top => $list) : $text;
    }
    return @top ? msg('topic', url => $opts{helpurl}, top => $list)
                : msg('topic.none', url => $opts{helpurl});
}

sub writepublic { # the public part of the game, for the site
    return unless $opts{publicfile};
    my $data = IRPG::Public::build(rps => \%rps, mapitems => \%mapitems,
                                   quest => \%quest, modsfile => $opts{modsfile},
                                   npc => [npcs()]);
    eval { IRPG::Public::write_json($data,$opts{publicfile}); 1 } or
        warn(debug("Error: $@")."\n");
}

sub readconfig {
    if (! -e ".irpg.conf") {
        debug("Error: Cannot find .irpg.conf. Copy it to this directory, ".
              "please.",1);
    }
    else {
        open(CONF,"<.irpg.conf") or do {
            debug("Failed to open config file .irpg.conf: $!",1);
        };
        my($line,$key,$val);
        while ($line=<CONF>) {
            next() if $line =~ /^#/; # skip comments
            $line =~ s/[\r\n]//g;
            $line =~ s/^\s+//g;
            next() if !length($line); # skip blank lines
            ($key,$val) = split(/\s+/,$line,2);
            $key = lc($key);
            if (lc($val) eq "on" || lc($val) eq "yes") { $val = 1; }
            elsif (lc($val) eq "off" || lc($val) eq "no") { $val = 0; }
            if ($key eq "die") {
                die("Please edit the file .irpg.conf to setup your bot's ".
                    "options. Also, read the README file if you haven't ".
                    "yet.\n");
            }
            elsif ($key eq "server") { push(@{$opts{servers}},$val); }
            elsif ($key eq "okurl") { push(@{$opts{okurl}},$val); }
            else { $opts{$key} = $val; }
        }
    }
}
