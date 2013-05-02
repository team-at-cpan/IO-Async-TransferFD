#!/usr/bin/perl 
use strict;
use warnings;
use IO::Async::Process::Wrapper::TransferFD;
use IO::Async::Listener;
use IO::Async::Loop;
use Scalar::Util;
use feature qw(say);

++$|;
my $loop = IO::Async::Loop->new;
my $wrapped = IO::Async::Process::Wrapper::TransferFD->new(
	loop => $loop,
	code => sub {
		my %args = @_;
		Scalar::Util::weaken(my $loop = $args{loop});
		$args{control}->configure(
			on_filehandle => sub {
				say "We have a new handle: @_";
				$loop->stop;
			}
		);
		say 'Starting loop';
		$args{loop}->run;
	},
	stdin => { from => 'starting' },
	stdout => {
		on_read => sub {
			my ( $stream, $buffref ) = @_;
			say 'read for stdout';
			print $$buffref;
			$$buffref = '';
			return 0;
		},
	},
	stderr => {
		on_read => sub {
			my ( $stream, $buffref ) = @_;
			say 'read for stderr';
			print $$buffref;
			$$buffref = '';
			return 0;
		},
	},
	on_finish => sub { say "done" },
	on_exception => sub { say "error: @_" },
);

$loop->later(sub {
	my $srv = IO::Async::Listener->new(
		on_stream => sub {
			say "Stream starts: @_";
		},
	);
	$loop->add($srv);
	$srv->listen(
		addr => { family => "inet", socktype => "stream", port => 0 },
		socktype => 'stream',
		on_listen => sub {
			say "Listening: @_";
		},
		on_resolve_error => sub { print STDERR "Cannot resolve - $_[0]\n"; },
		on_listen_error  => sub { print STDERR "Cannot listen\n"; },
	);
	open my $fh, '>', 'test.out' or die $!;
	$fh->print("test data");
	$wrapped->send($fh);
});
$loop->run;
