#!/usr/bin/perl -w

use lib '.';
use GumbyBRAIN;
use Storable;

die "Run genconfig.pl before attempting to bootstrap, kthnxbye\n" unless -e 'GumbyBRAIN.sto';
open (PIDFILE,">GumbyBRAIN.pid" ) or die "Couldn\'t open PID file: $!\n";
print PIDFILE "$$\n";
close(PIDFILE);

my $hashref = retrieve('GumbyBRAIN.sto');

GumbyBRAIN->spawn( config => $hashref );
exit 0;
