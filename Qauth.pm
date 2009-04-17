package Qauth;

use POE::Component::IRC::Plugin qw( :ALL );

our ($QBOT) = 'Q@CServe.quakenet.org';
our ($LBOT) = 'L@lightweight.quakenet.org';
our ($QFULL) = 'Q!TheQBot@CServe.quakenet.org';
our ($LFULL) = 'L!TheLBot@lightweight.quakenet.org';

sub new {
  my ($package) = shift;

  return bless { @_ }, $package;
}

sub PCI_register {
  my ($self,$irc) = splice @_, 0, 2;

  $self->{irc} = $irc;
  $irc->plugin_register( $self, 'SERVER', qw(all) );
  return 1;
}

sub PCI_unregister {
  my ($self,$irc) = splice @_, 0, 2;

  delete ( $self->{irc} );
  return 1;
}

sub S_001 {
  my ($self,$irc) = splice @_, 0, 2;
  
  if ( $irc->server_name() =~ /quakenet\.org$/i ) {
	if ( $self->{qauth} and $self->{qpass} ) {
		$irc->yield( privmsg => $QBOT => 'AUTH' => $self->{qauth} => $self->{qpass} );
	}
  }
  return PCI_EAT_NONE;
}

sub S_notice {
  my ($self,$irc) = splice @_, 0, 2;
  my ($who) = lc ${ $_[0] };
  my ($what) = ${ $_[2] };

  if ( $who eq lc $QFULL ) {
        $self->_qbot_notice( $what );
        return PCI_EAT_NONE;
  }
  return PCI_EAT_NONE;
}

sub _qbot_notice {
  my ($self,$what) = splice @_, 0, 2;

   SWITCH: {
     if ( $what =~ /^AUTH\'d/i ) {
        $self->{authed} = 1;
        $self->{irc}->_send_event( 'irc_qnet_authed' );
        last SWITCH;
     }
   }
}

1;
