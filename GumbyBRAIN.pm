package GumbyBRAIN;

use strict;
use warnings;
use Data::Dumper;
use Qauth;
use POEKnee;
use POE::Component::AI::MegaHAL;
use POE qw(Wheel::Run Filter::Line);
use POE::Component::IRC::State;
use POE::Component::IRC::Common qw(:ALL);
use POE::Component::IRC::Plugin qw( :ALL );
use POE::Component::IRC::Plugin::BotAddressed;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Plugin::CTCP;

our $VERSION = '1.10';

sub spawn {
  my $package = shift;

  my $self = bless { @_ }, $package;

  my $settings = delete $self->{config}->{settings};
  die "No settings specified\n" unless $settings or ref( $settings ) eq 'HASH';
  $self->{nickname} = delete $settings->{nick};
  die "No nickname specified\n" unless $self->{nickname};

  $self->{fucktards} = { };

  $self->{initial} = __PACKAGE__ . "-" . $VERSION;

  foreach my $network ( keys %{ $self->{config} } ) {
     $self->{irc}->{ $network } = POE::Component::IRC::State->spawn( alias => $network, nick => $self->{nickname}, server => $network, ircname => $self->{initial}, password => $self->{config}->{ $network }->{password} ); 
  }
  $self->{megahal} = POE::Component::AI::MegaHAL->spawn( alias => 'megahal', autosave => 1, options => { trace => 0 } );

  POE::Session->create(
        object_states => [
                $self => [ qw(_brain_saved _sig_int _sig_hup _start child_closed child_error child_stderr child_stdout irc_plugin_add
			      irc_msg irc_public irc_bot_addressed irc_ctcp_action _reply_addressed _reply_notice _reply_ctcp_action) ],
        ],
	options => { trace => 0 },
  );

  $poe_kernel->run();
}

sub _start {
  my $self = $_[OBJECT];

  $_[KERNEL]->sig( HUP => '_sig_hup' );
  $_[KERNEL]->sig( INT => '_sig_int' );

  foreach my $network ( keys %{ $self->{irc} } ) {
     my $irc = $self->{irc}->{ $network };
     $irc->yield( register => 'all' );
     $irc->plugin_add( 'MehSelf', $self );
     $irc->plugin_add( 'Connector', POE::Component::IRC::Plugin::Connector->new() );
     $irc->plugin_add( 'BotAddressed', POE::Component::IRC::Plugin::BotAddressed->new() );
     $irc->plugin_add( 'CTCP', POE::Component::IRC::Plugin::CTCP->new( version => join(" ", $self->{initial}, "POE::Component::IRC-$POE::Component::IRC::VERSION", "POE-$POE::VERSION" ) ) );
     $irc->plugin_add( 'POEKnee', POEKnee->new() );
     if ( $network =~ /quakenet\.org$/ ) {
       $irc->plugin_add( 'Qauth', Qauth->new( qauth => $self->{config}->{ $network }->{qauth}, qpass => $self->{config}->{ $network }->{qpass} ) );
     }
  }

  #$self->_launch_wheel();
  undef;
}

sub _launch_wheel {
  my $self = shift;

  $self->{wheel} = POE::Wheel::Run->new(
	Program => './newsagg.pl',
	ErrorEvent  => 'child_error',
	CloseEvent  => 'child_closed',
	StdioFilter => POE::Filter::Line->new(),
	StderrFilter => POE::Filter::Line->new(),
	StdoutEvent => 'child_stdout',
	StderrEvent => 'child_stderr',
  );
  undef;
}

sub child_closed {
  my $self = $_[OBJECT];

  delete $self->{wheel};
  print STDERR "Child closed\n";
  undef;
}

sub child_error {
  my $self = $_[OBJECT];

  delete $self->{wheel};
  print STDERR "Child error\n";
  undef;
}

sub child_stdout {
  my ($self,$input) = @_[OBJECT,ARG0];

  print STDERR "$input\n";
  $poe_kernel->post( 'megahal' => do_reply => { text => $input, event => '_blank' } );
  undef;
}

sub child_stderr {
  my ($self,$input) = @_[OBJECT,ARG0];

  print STDERR "$input\n";
  undef;
}

sub _sig_int {
  my ($kernel,$self) = @_[KERNEL,OBJECT];

  foreach my $network ( keys %{ $self->{irc} } ) {
     my $irc = $self->{irc}->{ $network };
     $irc->plugin_del( 'Connector' );
     $irc->plugin_del( 'BotAddressed' );
     $irc->plugin_del( 'Qauth' );
     $irc->plugin_del( $self );
     $irc->yield( unregister => 'all' );
     $irc->yield( 'quit' => 'Caught a SIGNAL, brain saved, l8rz' );
     $irc->yield( 'shutdown' );
  }
  $kernel->post( 'megahal' => _cleanup => { event => '_brain_saved' } );
  $self->{wheel}->kill() if $self->{wheel};
  $kernel->sig( 'HUP' );
  $kernel->sig( 'INT' );
  $kernel->sig_handled();
}

sub _sig_hup {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $kernel->post( 'megahal' => _cleanup => { event => '_brain_saved' } );
  $kernel->sig_handled();
}

sub irc_plugin_add {
  my ($self,$name) = @_[OBJECT,ARG0];

  print STDOUT "$name\n";

  if ( $name eq 'MehSelf' ) {
     $_[KERNEL]->post( $_[SENDER] => connect => { debug => 0, partfix => 1 } );
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

sub irc_msg {
  my $who = ( split /!/, $_[ARG0] )[0];
  my $what = $_[ARG2];

  print STDERR "<$who> $what\n";
  $poe_kernel->post( 'megahal' => do_reply => { text => $what, event => '_reply_notice', _irc => $_[SENDER]->ID(), _who => $who } );
  undef;
}

sub _brain_saved {
  my ($kernel,$self,$reply) = @_[KERNEL,OBJECT,ARG0];

  print STDOUT "Brain saved.\n";
  undef;
}

sub _reply_notice {
  my ($self,$reply) = @_[OBJECT,ARG0];

  my $text = delete $reply->{reply};
  $text = fix_text( $text );
  my $who = delete $reply->{_who};
  my $irc = delete $reply->{_irc};
  if ( $text and $who and $irc ) {
	$text =~ s/DCC send/cock badger/gi;
	$poe_kernel->post( $irc => notice => $who => $text );
  }
  undef;
}

sub _reply_addressed {
  my ($self,$reply) = @_[OBJECT,ARG0];

  my $text = delete $reply->{reply};
  $text = fix_text( $text );
  my $who = delete $reply->{_who};
  return if ( lc ( $who ) eq 'purl' );
  my $where = delete $reply->{_where};
  my $irc = delete $reply->{_irc};
  if ( $who and $where ) {
	my $key = "$irc,$where,$who";
	my $last = delete $self->{fucktards}->{ $key };
	$self->{fucktards}->{ $key } = time();
	return if $last and ( time() - $last < 60 );
  }
  if ( $text and $who and $irc ) {
	if ( $text =~ m/^.+?:\s(.*)$/i ) {
		$text = $1;
	}
	$text =~ s/DCC send/cock badger/gi;
	$poe_kernel->post( $irc => privmsg => $where => $text );
  }
  undef;
}

sub _reply_ctcp_action {
  my ($self,$reply) = @_[OBJECT,ARG0];

  my $text = delete $reply->{reply};
  $text = fix_text( $text );
  my $who = delete $reply->{_who};
  my $where = delete $reply->{_where};
  my $irc = delete $reply->{_irc};
  if ( $who and $where and ( uc( $where ) ne uc( "#" . $self->{nickname} ) ) ) {
	my $key = "$irc,$where,$who";
	my $last = delete $self->{fucktards}->{ $key };
	$self->{fucktards}->{ $key } = time();
	return if $last and ( time() - $last < 60 );
  }
  if ( $text and $who and $irc ) {
	if ( $text =~ m/^.+?:\s(.*)$/i ) {
		$text = $1;
	}
	$text =~ s/DCC send/cock badger/gi;
	$poe_kernel->post( $irc => privmsg => $where => "$text" );
  }
  undef;
}

sub irc_public {
  my $self = $_[OBJECT];
  my $who = ( split /!/, $_[ARG0] )[0];
  my $where = $_[ARG1]->[0];
  my $input = $_[ARG2];
  my $channel = "#" . $self->{nickname};

  if ( uc( $channel ) eq uc( $where ) ) {
  	$poe_kernel->post( 'megahal' => do_reply => { text => $input, event => '_reply_ctcp_action' , _irc => $_[SENDER]->ID(), _who => $who, _where => $where } );
  } else {
  	$poe_kernel->post( 'megahal' => do_reply => { text => $input, event => '_blank' } );
  }
  undef;
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

sub irc_bot_addressed {
  my $who = ( split /!/, $_[ARG0] )[0];
  my $where = $_[ARG1]->[0];
  my $input = $_[ARG2];

  $poe_kernel->post( 'megahal' => do_reply => { text => $input, event => '_reply_addressed' , _irc => $_[SENDER]->ID(), _who => $who, _where => $where } );
  undef;
}

sub irc_ctcp_action {
  my $self = $_[OBJECT];
  my $who = ( split /!/, $_[ARG0] )[0];
  my $addressed = $_[ARG1]->[0];
  my $what = $_[ARG2];
  my $event = '_blank';
  my $mynick = $_[SENDER]->get_heap()->nick_name();

  if ( $addressed !~ /^#/ ) {
	$event = '_reply_notice';
	print STDERR "* $who $what";
  }

  if ( $addressed =~ /^#/ and $what =~ /\Q$mynick\E/i ) {
	$event = '_reply_ctcp_action';
  }

  $poe_kernel->post( 'megahal' => do_reply => { text => "$who $what", event => $event, _irc => $_[SENDER]->ID(), _who => $who, _where => $addressed } );
  undef;
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
