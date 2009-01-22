package CPAN::Reporter::Smoker::Safer;

use strict;
use warnings;
use base qw(CPAN::Reporter::Smoker);
use CPAN;
use LWP::Simple();
use URI();

use Exporter;
our @ISA = 'Exporter';
our @EXPORT = qw/ start /;

our $VERSION = '0.02';

our $MIN_REPORTS  = 10;
our $MIN_DAYS_OLD = 14;
our @RE_EXCLUSIONS = (
  qr#/perl-5\.#,
  qr#/mod_perl-\d#,
);


sub start {              # Overload of CPAN::Reporter::Smoker::start()
  my $self = __PACKAGE__;
  my $args = { @_ };
  my $saferOpts = delete( $args->{safer} ) || {};
  $MIN_REPORTS   =   $saferOpts->{min_reports}  if exists $saferOpts->{min_reports};
  $MIN_DAYS_OLD  =   $saferOpts->{min_days_old} if exists $saferOpts->{min_days_old};
  @RE_EXCLUSIONS = @{$saferOpts->{exclusions}}  if exists $saferOpts->{exclusions};
  my $dists = $self->__installed_dists( @$saferOpts{qw/mask filter/} );

  printf "Smoker::Safer: Found %d suitable distributions.\n", scalar @$dists;
  return CPAN::Reporter::Smoker::start( %$args, list => $dists );
}

sub __filter {
  my $self = shift;
  my $dist = shift;
  my $d = $dist->pretty_id;
  foreach my $re ( @RE_EXCLUSIONS ){
    return 0 if $d =~ m/$re/;
  }

  my $uri = URI->new('http://www.cpantesters.org/cgi-bin/reports-text.cgi');
  my %params = (
	distvers => $dist->base_id,
	agent => ref($self)||$self,
  );

  if( $MIN_DAYS_OLD ){
    $uri->query_form( %params, act => 'uploaded', epoch => 1 );
    if( my $t = LWP::Simple::get($uri) ){
      return 0 if time - $t < $MIN_DAYS_OLD*24*60*60;
    }else{
      printf "Smoker::Safer: WARNING -- no upload_date for '%s'\n", $d;
      return 0;
    }
  }

  if( $MIN_REPORTS ){
    $uri->query_form( %params, act => 'reports' );
    my ($n) = LWP::Simple::get($uri) =~ /ALL\((\d+)\)/;
    if( !defined $n ){
      printf "Smoker::Safer: WARNING -- couldn't retrieve reports for '%s'\n", $d;
      return 0;
    }elsif( $n < $MIN_REPORTS ){
      return 0;
    }
  }

  return 1;
}

sub __installed_dists {
  my $self   = shift;
  my $mask   = shift || '/./';
  my $filter = shift || \&__filter;

  my %dists;
  foreach my $mod ( CPAN::Shell->expand('Module',$mask) ){
    my $d = $mod->distribution or next;
    my $k = $d->pretty_id;
    next if exists $dists{$k};
    next if ! $mod->inst_file;
    $dists{$k} = $d;
  };
  my @dists;
  foreach my $dist ( sort keys %dists ){
    if( ! &$filter($self, $dists{$dist}) ){
      printf "Smoker::Safer: EXCLUDING '%s'.\n", $dist;
      next;
    }
    push @dists, $dist;
  }
  return \@dists;
}


1;# End of CPAN::Reporter::Smoker::Safer

__END__

=pod

=head1 NAME

CPAN::Reporter::Smoker::Safer - Turnkey smoking of installed distros

=head1 VERSION

Version 0.02


=head1 SYNOPSIS

  # Default usage
  perl -MCPAN::Reporter::Smoker::Safer -e start

  # Control the 'trust' params for the default filter
  perl -MCPAN::Reporter::Smoker::Safer -e 'start( safer=>{min_reports=>0, min_days_old=>2} )'

  # Smoke all installed modules from a specific namespace
  perl -MCPAN::Reporter::Smoker::Safer -e 'start( safer=>{min_reports=>0, min_days_old=>0, mask=>"/MyFoo::/"} )'

  # Custom filter (in this case, specific authorid)
  perl -MCPAN::Reporter::Smoker::Safer -e 'start( safer=>{filter=>sub{$_[1] =~ m#/DAVIDRW/#}} )'


=head1 DESCRIPTION

This is a subclass of L<CPAN::Reporter::Smoker> that will limit the set of tested distributions to ones that are already installed on the system (and their dependencies).  This is based on the assumption that, having been installed, the distributions and their dependencies are trusted. This can be used to run partial smoke testing on a box that normally wouldn't be desired for full smoke testing (i.e. isn't a dedicated/isolated environment). Another potential use is to vet everything before upgrading.


=head2 WARNING -- smoke testing is risky

While in theory this is much safer than full CPAN smoke testing, ALL of the same risks (see L<CPAN::Reporter::Smoker>) still apply:

Smoke testing will download and run programs that other people have uploaded to
CPAN.  These programs could do *anything* to your system, including deleting
everything on it.  Do not run CPAN::Reporter::Smoker unless you are prepared to
take these risks.  


=head1 USAGE

=head2 start()

This is an overload of L<CPAN::Reporter::Smoker>::start, and supports the same arguments, with the exception of C<list> which is set internally.  In addition, supports the following argument:

=head3 safer

Hashref with the following possible keys:

=over 2

=item mask

Scalar; Defaults to C<'/./'>; Value is passed to C<CPAN::Shell::expand()> for filtering the module list (applies to I<module> names, not distro names).

=item filter

Code ref; Defaults to L<"__filter">. First argument is the CPAN::Reporter::Smoker::Safer class/object; Second argument is a L<CPAN::Distribution> object.  Return value should be C<1> (true) to accept, and C<0> (false) to reject the distribution.

	filter => sub {
	  my ($safer, $dist) = @_;
	  ...
          return 1; 
	},

=item min_reports

Defaults to 10. This is used by the default filter -- distros are 'trusted' if they have at least this many CPAN testers reports already.

=item min_days_old

Defaults to 10. This is used by the default filter -- distros are 'trusted' unless they were uploaded to CPAN at least this many days ago.

=item exclusions

Defaults to C<[ qr#/perl-5\.#, qr#/mod_perl-\d# ]>.  This is used by the default filter to exclude
any distro whose name (e.g. A/AU/AUTHOR/Foo-Bar-1.23.tar.gz) matches one of these regexes.

Note that the F<disabled.yml> functionality might be more suitable.  See L<CPAN::Reporter::Smoker>, L<CPAN>, and L<CPAN::Distroprefs> for more details.

=back

=head1 INTERNAL METHODS

=head2 __filter

Used as the default L<"filter"> code ref.

=over 2

=item *

Excludes any distro who's name (e.g. A/AU/AUTHOR/Foo-Bar-1.23.tar.gz) matches a list of L<"exclusions">.

=item *

Exclude any distro that was uploaded to CPAN less than L<"min_days_old"> days ago.

=item *

Exclude any distro that has less than L<"min_reports"> CPAN Testers reports.

=back


=head2 __installed_dists

Returns an array ref of dist names (e.g. 'ANDK/CPAN-1.9301.tar.gz' ).

	CPAN::Reporter::Smoker::Safer->__installed_dists( $mask, $filter );

C<mask> is optional, and is same value as L<"mask">. C<filter> is optional, and is same value as L<"filter">.


=head1 AUTHOR

David Westbrook (CPAN: davidrw), C<< <dwestbrook at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-cpan-reporter-smoker-safer at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CPAN-Reporter-Smoker-Safer>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CPAN::Reporter::Smoker::Safer

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=CPAN-Reporter-Smoker-Safer>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/CPAN-Reporter-Smoker-Safer>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/CPAN-Reporter-Smoker-Safer>

=item * Search CPAN

L<http://search.cpan.org/dist/CPAN-Reporter-Smoker-Safer>

=back

=head1 SEE ALSO

=over 4

=item *

L<http://cpantesters.org> - CPAN Testers site

=item *

L<http://groups.google.com/group/perl.cpan.testers.discuss/browse_thread/thread/4ae7f4960beda1d4> - The 1/2009 thread with initial discussion for this module.

=item *

L<CPAN>

=item *

L<CPAN::Reporter>

=item *

L<CPAN::Reporter::Smoker>

=back

=head1 ACKNOWLEDGEMENTS

The cpan-testers-discuss mailling list for supporting and enhancing the concept.

=head1 COPYRIGHT & LICENSE

Copyright 2009 David Westbrook, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
