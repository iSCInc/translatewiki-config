#!/usr/bin/perl
=head1 NAME

fetch-i18n-files.pl used to fetch i18n files list WMF repository
=cut

use strict;
use warnings;

use Getopt::Long;
use LWP;
use Pod::Usage;
use Compress::Zlib;
use File::Path qw( make_path );
use File::Basename qw( dirname );

=head1 SYNOPSIS

fetch-i18n-files.pl [options]

 Options:
  -help   brief help
  -man    man page
  -verbose Verbose messages :-)

  -gitweb gitweb root URL
          Default: 'https://gerrit.wikimedia.org/r/gitweb'

  -list   File containing a list of files to fetch
          Default: i18nfiles.list

  -wmf    File containing extensions on Gerrit
          Default: wmf.list

  -cached Skip fetching i18n files for which have a copy which
          is less than one day old.

  -to     path to write i18n files to
          Default: import

=cut

my $opt_list   = 'i18nfiles.list';
my $opt_wmf    = 'wmf.list';
my $opt_gitweb = 'https://gerrit.wikimedia.org/r/gitweb';
my $opt_to     = 'import';
my $opt_cached = 0;
my $opt_help   = 0;
my $opt_man    = 0;
my $verbose    = 0;

GetOptions(
	 'list=s'     => \$opt_list
	,'wmf=s'      => \$opt_wmf
	,'gitweb=s'   => \$opt_gitweb
	,'to=s' => \$opt_to
	,'cached'     => \$opt_cached
	,'help'       => \$opt_help
 	,'man'        => \$opt_man
	,'verbose'    => \$verbose
) or pod2usage(2);
pod2usage(1) if $opt_help;
pod2usage( -verbose => 2 ) if $opt_man;

# Initialization

my $browser = LWP::UserAgent->new;

#######################################################################
# Given an extension name, returns the gitweb URL pointing to the raw
# i18n file for that extension.
#######################################################################
sub URLfor($) {
	my $resource = shift;

	(my $extension, my $file ) = split m{/}, $resource, 2;

	my $url = "${opt_gitweb}?p=<EXT>;a=blob_plain;f=<FILE>;hb=HEAD";
	$url =~ s%<EXT>%mediawiki/extensions/${extension}.git% ;
	$url =~ s%<FILE>%${file}% ;

	return $url;
}

#######################################################################
# Wrapper to print a message when using --verbose
#######################################################################
sub verbose($) {
	my $msg = shift;
	print "VERBOSE> $msg" if $verbose;
}

#######################################################################
# Wrapper to print nice (?) error message
#######################################################################
sub error {
	warn "ERROR> ", @_ ;
}
sub fatalerror {
	error(@_);
	exit 1;
}


#######################################################################
# Read the configuration file given by --list
#######################################################################
sub readConf($) {
	my $filename = shift;

	my @lines;
	verbose( "Reading configuration file '$filename'\n" );
	open LIST, "<$filename" or die("Could not read configuration file '$filename'.\n");
	while( <LIST> ) {
		chop $_;
		next if ( $_ =~ /^#/ || $_ =~ /^$/ );
		push( @lines, $_ );
	}
	close LIST;
	verbose( "Found " . @lines. " entries in $filename\n" );
	return @lines;
}

#######################################################################
######## MAIN #########################################################
#######################################################################

# All i18n files available:
my @files = readConf( $opt_list );
# All MediaWiki extensions hosted by the WMF
my %wmfexts = map { $_ => 1 } (readConf( $opt_wmf ) );

my @wmffiles;
# Filter input files to only retains WMF hosted ones
foreach( @files ) {
	my $file = $_;
	(my $ext) = ($file =~ m{^(.*?)/});
	next unless $ext;

	# Keep file if it is part of a WMF extension
	if( $wmfexts{$ext} ) {
		push @wmffiles, $file;
	}
}


foreach( @wmffiles ) {

	my $resource = $_;
	next unless $resource =~ /\.php$/;

	my $filename = "${opt_to}/${resource}";

	if( $opt_cached && -e $filename ) {
		my $age = -M $filename;
		if( $age < 1) {
			verbose( "Skip fresh $filename\n" );
			next;
		}
	}

	print "Fetching $resource\n";

	# Get URL and fetch its content
	my $response = $browser->get( URLfor($resource) );
	unless( $response->is_success ) {
		error( "did not fetch i18n file for $resource: ", $response->status_line, "\n" );
		next;
	}

	# Write content to i18n file
	print "Writing $filename\n" ;

	my $dir = dirname( $filename );
	unless( -d $dir ) {
		make_path( $dir )
		or fatalerror("Could not create directory $dir");
	}

	open FILE, ">$filename" or die("Could not open file $filename\n");
	print FILE $response->content or die("Could not write to $filename\n");
	close FILE;

}

verbose( "Script completed.\n" );

__END__

=head1 DESCRIPTION

i18nfiles.list (for --list) is generated by the Translate extension using:

 scripts/list-mwext-i18n-files.php


The list of wmf extension is available on gerrit at https://gerrit.wikimedia.org/mediawiki-extensions.txt
