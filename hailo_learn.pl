use strict;
use warnings;
use Hailo;

$|=1;

my $hailo = Hailo->new(
           storage_class  => 'SQLite',
           brain_resource => 'hailo.sqlite',
);

while (<>) {
  chomp;
  $hailo->learn($_);
}

print $hailo->reply("hello good sir."), "\n";
