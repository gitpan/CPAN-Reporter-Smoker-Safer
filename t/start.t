#!perl

use strict;
use warnings;
use Test::More tests => 25;
use Test::Differences;
use CPAN::Reporter::Smoker::Safer;
$|=1;

sub check_args {
  my $label = shift;
  my $rc = start(
	foo => 1,
	safer => {
		preview => 1,
		min_reports => 0,
		min_days_old => 0,
		@_
	},
  );
  is( ref($rc), 'HASH', "$label got hash" );
  eq_or_diff( [sort keys %$rc], [qw/foo list/], "$label hashkeys" );
  my $dists = $rc->{list};
  is( ref($dists), 'ARRAY', "$label got array ref" );
  ok( scalar(@$dists), "$label got dists" );
  ok( grep(m#/CPAN-Reporter-\d#,@$dists), "$label got CPAN-Reporter" );
}

check_args(	'CPAN::Reporter',
	mask  => '/^CPAN::Reporter$/',
);

check_args(	'CPAN',
	mask  => '/CPAN/',
);


check_args(	'CPAN-1-1',
	min_reports => 1,
	min_days_old => 1,
	mask  => '/CPAN/',
);

check_args(	'P-exclusions',
	mask => '/P/',
	exclusions => [ qr#/(?!CPAN)# ],
);


check_args(	'P-filter',
	mask => '/P/',
	filter => sub { $_[1]->pretty_id =~ /CPAN/ },
);



