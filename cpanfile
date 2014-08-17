requires 'parent', 0;
requires 'curry', 0;
requires 'Future', '>= 0.29';
requires 'Future::Utils', '>= 0.29';
requires 'Socket', '>= 2.000';
requires 'Socket::MsgHdr', 0;
requires 'IO::Async', '>= 0.60';

on 'test' => sub {
	requires 'Test::More', '>= 0.98';
	requires 'Test::Fatal', '>= 0.010';
};

