package IO::Async::TransferFD;
# ABSTRACT: send handles between processes
use strict;
use warnings;

our $VERSION = '0.001';

=head1 NAME

IO::Async::TransferFD - support for transferring handles between
processes via socketpair

=head1 SYNOPSIS

 my $proc = IO::Async::Process->new(
   code => sub { },
   fd3 => { via => 'socketpair' },
 );
 my $control = IO::Async::TransferFD->new(
   loop => $loop,
   handle => $proc->fd(3)->write_handle,
   on_filehandle => sub {
     my $h = shift;
     say "New handle $h - " . join '', <$h>;
   }
 );
 $control->send(\*STDIN);

=head1 DESCRIPTION

Uses SCM_RIGHTS to pass an open handle from one process to another.
Typically used to hand a network socket off to another process, for
example an accept loop in one process dispatching incoming connections
to other active processes.

=cut

use Socket::MsgHdr qw(sendmsg recvmsg);
use Socket qw(AF_UNIX SOCK_STREAM PF_UNSPEC SOL_SOCKET SCM_RIGHTS);
use curry::weak;

# Not sure of a good value for this but 16 seems low enough
# to avoid problems, we'll split into multiple packets if
# we have more than this number of pending FDs to send.
# On linux the /proc/sys/net/core/optmem_max figure may be
# relevant here - it's 10240 on one test system.
use constant MAX_FD_PER_PACKET => 16;

=head1 METHODS

=cut

sub new {
	my $class = shift;
	my $self = bless {
		pending => [],
	}, $class;
	$self->configure(@_);
	$self
}

=head2 outgoing_packet

Convert a list of handles to a cmsghdr struct suitable for
transferring to another process.

Returns the encoded cmsghdr struct.

=cut

sub outgoing_packet {
	my $self = shift;
	# FIXME presumably this 512 figure should really be calculated,
	# also surely it'd be controllen rather than buflen?
	my $hdr = Socket::MsgHdr->new(buflen => 512);
	my $data = pack "i" x @_, map $_->fileno, @_;
	$hdr->cmsghdr(SOL_SOCKET, SCM_RIGHTS, $data);
	$hdr
}

=head2 recv_fds

Receive packet containing FDs.

Takes a single coderef which will be called with two
parameters.

Returns $self.

=cut

sub recv_fds {
	my $self = shift;
	my $handler = shift;
	# FIXME more magic numbers
	my $inHdr = Socket::MsgHdr->new(buflen => 8192, controllen => 256);
	$handler->($inHdr, sub {
		my ($level, $type, $data) = $inHdr->cmsghdr();
		unpack('i*', $data);
	});
	$self
}

sub handle { shift->{handle} }

=head2 send_queued

If we have any FDs queued for sending, bundle them into a packet
and send them over. Will close the FDs once the send is complete.

Returns $self.

=cut

sub send_queued {
	my $self = shift;
	# Send a single batch at a time
	if(@{$self->{pending}}) {
		warn "send Handle is now " . $self->{handle};
		sendmsg $self->handle, $self->outgoing_packet(
			my @fd = splice @{$self->{pending}}, 0, MAX_FD_PER_PACKET
		);
		$_->close for @fd;
	}
	# If we have any leftovers, we hope to be called next time around
	$self->{h}->want_writeready(0) unless @{$self->{pending}};
	$self
}

=head2 read_pending

Reads any pending messages, converting to FDs
as appropriate and calling the on_filehandle callback.

Returns $self.

=cut

sub read_pending {
	my $self = shift;
	$self->recv_fds($self->curry::accept_fds);
}

sub accept_fds {
	my $self = shift;
	my $hdr = shift;
	my $code = shift;
	warn "accepting";
		warn "Handle is now " . $self->{handle};
	recvmsg $self->handle, $hdr;
	my @fd = $code->();
	warn "had @fd";
	foreach my $fileno (@fd) {
		open my $fh, '+<&=', $fileno or die $!;
		$self->on_filehandle($fh);
	}
}

sub on_filehandle {
	my $self = shift;
	my $fh = shift;
	$self->{on_filehandle}->($fh) if $self->{on_filehandle};
	$self
}

sub configure {
	my $self = shift;
	my %args = @_;

	my $loop = delete $args{loop} || $self->{loop};
	Scalar::Util::weaken($self->{loop} = $loop);
	$self->{on_filehandle} = delete $args{on_filehandle} if exists $args{on_filehandle};

	if(exists $args{handle}) {
		$self->{handle} = delete $args{handle};
		warn "Handle is now " . $self->{handle};
		$loop->add(my $h = IO::Async::Handle->new(
			handle => $self->handle,
			on_write_ready => $self->curry::weak::send_queued,
			on_read_ready => $self->curry::weak::read_pending,
		));
		$h->want_writeready(1);
		$h->want_readready(1);
		Scalar::Util::weaken($self->{h} = $h);
	};
	$self
}

sub send {
	my $self = shift;
	push @{$self->{pending}}, @_;
	$self->{h}->want_writeready(1) if $self->{h};
	$self
}


1;

__END__

=head1 SEE ALSO

=over 4

=item * L<Socket::MsgHdr> - we use this to do all the real work

=item * L<File::FDpasser> - another implementation

=back

=head1 AUTHOR

Tom Molesworth <cpan@entitymodel.com>

=head1 LICENSE

Copyright Tom Molesworth 2011. Licensed under the same terms as Perl itself.

