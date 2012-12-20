use strict;
use warnings;
use POE qw[Component::Hailo Wheel::ReadWrite];

POE::Session->create(
     package_states => [
         (__PACKAGE__) => [ qw(_start hailo_learned hailo_replied _input _error) ],
     ],
);

POE::Kernel->run;
exit 0;

sub _start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  POE::Component::Hailo->spawn(
      alias      => 'hailo',
      Hailo_args => {
           storage_class  => 'SQLite',
           brain_resource => 'hailo.sqlite',
      },
  );

  $heap->{stdin} = POE::Wheel::ReadWrite->new(
    Handle => \*STDIN,
    InputEvent => '_input',
    ErrorEvent => '_error',
  );

  return;
}

sub _error {
  my ($operation, $errnum, $errstr, $id) = @_[ARG0..ARG3];
  warn "Wheel $id encountered $operation error $errnum: $errstr\n";
  delete $_[HEAP]{stdin}; # shut down that wheel
  POE::Kernel->post(hailo => reply => ['This']);
  return;
}

sub _input {
  my ($heap,$input) = @_[HEAP,ARG0];
  return if $input =~ m!^#!;
  $poe_kernel->post( 'hailo', 'learn', [$input] );
  return;
}

sub hailo_learned {
  print "Hailo learned shit\n";
  return;
}

sub hailo_replied {
  my $reply = $_[ARG0]->[0];
  die "Didn't get a reply" if !defined $reply;
  print "Got reply: $reply\n";
  POE::Kernel->post(hailo => 'shutdown');
  return;
}
