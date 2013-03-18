package IO::Async::Process::Wrapper::TransferFD;
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

use IO::Handle;
use IO::Async::Process;
use IO::Async::TransferFD;
use curry::weak;

=head1 METHODS

=cut

=head2 new

Takes the following (named) parameters:

=over 4

=item * loop - the L<IO::Async::Loop> instance we'll attach to.
The child process will get a new instance of the same class.

=back

Example:

 my $loop = IO::Async::Loop->new;
 my $tfd = IO::Async::Process::Wrapper::TransferFD->new(
   loop => $loop,
   code => sub {
     my %args = @_;
	 $args{control}->configure(
	   on_filehandle => sub {
	     warn "we have a new FD: @_\n";
       }
	 );
	 $args{loop}->run;
   }
 );
 $tfd->send(\*STDIN);

Returns $self.

=cut

sub new {
	my $class = shift;
	my %args = @_;
	my $self = bless {}, $class;

	my $loop = delete $args{loop};
	my $code = delete $args{code};
	my $on_filehandle = delete $args{on_filehandle};

	my $loop_class = ref $loop;
	my $proc = IO::Async::Process->new(
		code => sub {
			my $loop = $loop_class->new;
			my $io = IO::Handle->new;
			die "Failed to open control channel - $!" unless $io->fdopen(3, 'r+');

			my $control = IO::Async::TransferFD->new(
				loop => $loop,
				handle => $io,
			);
			$code->(
				loop => $loop,
				control => $control,
			);
		},
		fd3 => {
			via => 'socketpair',
			# don't really want to pass this, but seems to be required
			on_read => sub {
				my ( $stream, $buffref ) = @_;
				$$buffref = '';
				return 0;
			},
		},
		on_finish => sub { },
		%args,
	);
	$loop->add($proc);
	my $control = IO::Async::TransferFD->new(
		loop => $loop,
		handle => $io,
		$on_filehandle ? (on_filehandle => $on_filehandle) : (),
	);
	$self->{process} = $proc;
	$self->{control} = $control;
	$self
}

sub process { shift->{process} }
sub control { shift->{control} }

sub send {
	my $self = shift;
	$self->control->send(@_);
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


