package CPAN::Reporter::Smoker::Safer;

use strict;
use warnings;
use base qw(CPAN::Reporter::Smoker);
use CPAN;
use POSIX qw/mktime/;

use Exporter;
our @ISA = 'Exporter';
our @EXPORT = qw/ start /;

our $VERSION = '0.01';

our $MIN_REPORTS  = 10;
our $MIN_DAYS_OLD = 14;
our @RE_EXCLUSIONS = (
  qr#/perl-5\.#,
  qr#/mod_perl-\d#,
);

our $OUTPUT = '';


sub start {              # Overload of CPAN::Reporter::Smoker::start()
  my $self = __PACKAGE__;
  my $args = { @_ };
  my $mask      = delete($args->{safer__mask});
  my $filter    = delete($args->{safer__filter});
  my $dists = $self->__installed_dists( $mask, $filter );

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

  if( $MIN_DAYS_OLD ){
    if( my $upload_date = $dist->upload_date ){
      my @d = split /-/, $upload_date, 3;  # YYYY-MM-DD
      my $t = POSIX::mktime( 0, 0, 0, $d[2], $d[1]-1, $d[0]-1900 );
      return 0 if time - $t < $MIN_DAYS_OLD*24*60*60;
    }else{
      printf "Smoker::Safer: WARNING -- no upload_date for '%s'\n", $d;
    }
  }

  if( $MIN_REPORTS ){
    my $n = eval {   # eval this, so that ->reports die'ing doesn't kill everything.
	# HACK -- it fudges it so that CPAN::Distribution writes to our $OUTPUT package var. Then parse that to get the actual reports lines.
      local $OUTPUT = '';
      local $CPAN::Frontend = $self;
      my $reports = $dist->reports;
      scalar grep { /^[ *]/ } split /\n/, $reports;
    };
    if( $@ || !defined $n ){
      printf "Smoker::Safer: WARNING -- couldn't retrieve reports for '%s': %s\n", $d, $@;
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

########################
# These my*() subs are a hack so that we can get the output from CPAN::Distribution->reports.
sub myprint {
  my($self,$what) = @_;
  $OUTPUT .= $what;
}
sub myexit {
  my($self,$what) = @_;
  $self->myprint($what);
  exit;
}
sub mywarn {
  my($self,$what) = @_;
  warn $what;
}
sub mydie {
  my($self,$what) = @_;
  die $what;
}
########################

1;# End of CPAN::Reporter::Smoker::Safer

__END__

=pod

=head1 NAME

CPAN::Reporter::Smoker::Safer - Turnkey smoking of installed distros

=head1 VERSION

Version 0.01


=head1 SYNOPSIS

  perl -MCPAN::Reporter::Smoker::Safer -e start


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

This is an overload of L<CPAN::Reporter::Smoker>::start, and supports the same arguments, with the exception of C<list> which is set internally.  In addition, the following arguments are support:

=head3 safer__mask

Scalar; Defaults to C<'/./'>; Value is passed to C<CPAN::Shell::expand()> for filtering the module list (applies to I<module> names, not distro names).

=head3 safer__filter

Code ref; Defaults to L<"__filter">. First argument is the CPAN::Reporter::Smoker::Safer class/object; Second argument is a L<CPAN::Distribution> object.  Return value should be C<1> to accept, and C<0> to reject the distribution.

	safer__filter => sub {
	  my ($safer, $dist) = @_;
	  ...
          return 1; 
	},


=head1 INTERNAL METHODS

=head2 __filter

Used as the default L<"safer__filter"> code ref.

=over 2

=item *

Excludes any distro who's name (e.g. A/AU/AUTHOR/Foo-Bar-1.23.tar.gz) matches one of the regexes in C<@RE_EXCLUSIONS>.

=item *

Exclude any distro that was uploaded to CPAN less than C<MIN_DAYS_OLD> days ago.

=item *

Exclude any distro that has less than C<MIN_REPORTS> CPAN Testers reports.

=back

These rely on the following package variables:

=head3 MIN_REPORTS

Scalar; Defaults to 10

=head3 MIN_DAYS_OLD

Scalar; Defaults to 14

=head3 RE_EXCLUSIONS

Array of regexes.  Defaults to C<( qr#/perl-5\.#, qr#/mod_perl-\d# )>.  Any I<distribution> names that match any of the items will be excluded.

Note that the F<disabled.yml> functionality might be more suitable.  See L<CPAN::Reporter::Smoker>, L<CPAN>, and L<CPAN::Distroprefs> for more details.

=head2 __installed_dists

Returns an array ref of dist names (e.g. 'ANDK/CPAN-1.9301.tar.gz' ).

	CPAN::Reporter::Smoker::Safer->__installed_dists( $mask, $filter );

C<mask> is optional, and is same value as L<"safer__mask">. C<filter> is optional, and is same value as L<"safer__filter">.

=head2 myprint, myexit, mywarn, mydie

These are included as a hack, so that C<$CPAN::Frontend> can be set to C<CPAN::Reporter::Smoker::Safer> so that the output of C<CPAN::Distribution::reports()> can be trapped and parsed.


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
