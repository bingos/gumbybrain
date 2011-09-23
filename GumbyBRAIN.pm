package GumbyBRAIN;

use strict;
use warnings;
use Qauth;
use POEKnee;
use POE qw(Wheel::Run Filter::Line Component::Hailo);
use POE::Component::IRC::State;
use POE::Component::IRC::Common qw(:ALL);
use POE::Component::IRC::Plugin qw( :ALL );
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Plugin::CTCP;
use POE::Component::IRC::Plugin::Hailo;

our $VERSION = '2.00';

sub spawn {
  my $package = shift;

  my $self = bless { @_ }, $package;

  my $settings = delete $self->{config}->{settings};
  die "No settings specified\n" unless $settings or ref( $settings ) eq 'HASH';
  $self->{nickname} = delete $settings->{nick};
  die "No nickname specified\n" unless $self->{nickname};

  $self->{initial} = __PACKAGE__ . "-" . $VERSION;

  $self->{hailo} = POE::Component::Hailo->spawn(
     alias      => 'hailo',
     Hailo_args => {
       storage_class  => 'SQLite',
       brain_resource => 'hailo.sqlite',
     },
  );


  foreach my $network ( keys %{ $self->{config} } ) {
     $self->{irc}->{ $network } = POE::Component::IRC::State->spawn( alias => $network, nick => $self->{nickname}, server => $network, ircname => $self->{initial}, password => $self->{config}->{ $network }->{password}, %$settings); 
  }

  POE::Session->create(
    object_states => [
       $self => [ qw(_start irc_plugin_add)],
    ],
  );

  $poe_kernel->run();
}

sub _start {
  my $self = $_[OBJECT];

  foreach my $network ( keys %{ $self->{irc} } ) {
     my $irc = $self->{irc}->{ $network };
     $irc->yield( register => 'all' );
     $irc->plugin_add( 'MehSelf', $self );
     $irc->plugin_add( 'Connector', POE::Component::IRC::Plugin::Connector->new() );
     $irc->plugin_add( 'CTCP', POE::Component::IRC::Plugin::CTCP->new( version => join(" ", $self->{initial}, "POE::Component::IRC-$POE::Component::IRC::VERSION", "POE-$POE::VERSION" ) ) );
     $irc->plugin_add( 'POEKnee', POEKnee->new() );
     if ( $network =~ /quakenet\.org$/ ) {
       $irc->plugin_add( 'Qauth', Qauth->new( qauth => $self->{config}->{ $network }->{qauth}, qpass => $self->{config}->{ $network }->{qpass} ) );
     }
     $irc->plugin_add('Hailo', POE::Component::IRC::Plugin::Hailo->new(
          Hailo => $self->{hailo},
          Own_channel => '#gumbybrain',
          Method => 'privmsg',
     ) );
  }
  undef;
}

sub irc_plugin_add {
  my ($self,$name) = @_[OBJECT,ARG0];

  print STDOUT "$name\n";

  if ( $name eq 'MehSelf' ) {
     $poe_kernel->post( $_[SENDER] => connect => { debug => 0, partfix => 1 } );
  }
  undef;
}

sub PCI_register {
  my ($self,$irc) = splice @_, 0, 2;

  $irc->plugin_register( $self, 'SERVER', qw(all) );
  return 1;
}

sub PCI_unregister {
  return 1;
}

sub S_001 {
  my ($self,$irc) = splice @_, 0, 2;

  print STDOUT "Connected to ", ${ $_[0] }, "\n";
  my $alias = ( $poe_kernel->alias_list( $irc->{session_id} ) )[0];
  $irc->yield( join => "#" . $self->{nickname} );
  $irc->yield( join => $_ ) for @{ $self->{config}->{ $alias }->{channels} };
  return PCI_EAT_NONE;
}

sub irc_kick {
  my $kickee = $_[ARG2];
  my $channel = $_[ARG1];
  my $mynick = $_[SENDER]->get_heap()->nick_name();
  if ( u_irc( $kickee ) eq u_irc( $mynick ) ) {
	$poe_kernel->post( $_[SENDER], 'join', $channel );
  }
  return;
}

sub S_qnet_authed {
  my ($self,$irc) = splice @_, 0, 2;

  my $alias = ( $poe_kernel->alias_list( $irc->{session_id} ) )[0];
  foreach my $channel ( @{ $self->{config}->{ $alias }->{channels} } ) {
    $irc->yield( join => $channel );
  }
  return PCI_EAT_NONE;
}

sub fix_text {
  my $text = shift || return;
  while ( length( $text ) > 500 ) {
	$text = substr( $text, 0, rindex( $text, '.' ) );
  }
  return $text;
}

1;
