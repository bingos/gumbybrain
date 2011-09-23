#!/usr/bin/perl -w

use strict;
use warnings;
use Data::Dumper;
use Storable;

# Comment out the following line.
die "You must edit this file before use\n";

my $hashref = { 'irc.network.local' => 
		  { 
			channels => [ '#channel1', '#channel2', '#channel3' ],
		  },
		'settings' => 
		  {
			nick => "Flibble$$",
#			localaddr => 'whatever',
#			port => 6697,
#			UseSSL => 1,
		  },
		};

store( $hashref, 'GumbyBRAIN.sto' );
my $hashref2 = retrieve('GumbyBRAIN.sto');
print Dumper( $hashref2 );
exit 0;

