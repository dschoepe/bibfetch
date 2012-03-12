#!/usr/bin/env perl

use strict;
use warnings;

use URI;
use URI::Escape;
use Web::Scraper;
use WWW::Mechanize;
use String::Random;
use Pod::Usage;
use Getopt::Long;
use List::Util qw(min);
use v5.10;

our $verbose;

sub gscholar {

  my ($query, $limit, $fulltext) = @_;
  my $mech = WWW::Mechanize->new();

  # Generate a random string consisting of 16 hex characters for the
  # google ID.  This is needed to make google scholar output bibtex
  # links for some reason.
  my $gid = (new String::Random)->randregex("[0-9a-f]{16}");

  $mech->agent_alias("Linux Mozilla");
  $mech->add_header(Cookie => "GSP=ID=$gid:CF=4");

  $query = "allintitle: ".$query unless $fulltext;
  $query = uri_escape($query);

  my $url = "http://scholar.google.com/scholar?hl=en&q=".$query."&num=".$limit;

  print STDERR "Query URL: $url\n" if $verbose;

  my $linkscraper = scraper {
    process 'div.gs_r', "entries[]" =>
      scraper {
        process "a[href]", "links[]" => { href => '@href', text => 'TEXT' };
        result 'links';
      };
    result 'entries';
  };

  my $response = $mech->get($url);

  my $raw_results = $linkscraper->scrape($response);
  my @results;
  for my $entry (@$raw_results) {
    my %data = ();
    my ($biblink) = grep { $_->{text} =~ /import into bibtex/i } @$entry;
    # We don't want articles without bibtex entries:
    next unless $biblink;
    $response = $mech->get($biblink->{href});
    if ($response->is_success) {
      $data{bibtex} = $response->decoded_content;
      given ($data{bibtex}) {
        # Chop off extra whitespace
        s/^\s+//m;
        s/\s+$//m;
      }
    } else { next; }
    my @pdflinks = grep { $_->{text} =~ /^\[pdf\] from/i } @$entry;
    if (@pdflinks) {
      $data{pdf} = $pdflinks[0]->{href};
    }
    push @results, \%data;
  }

  return @results;
}


my ($help, $pdfs, $fulltext);
my $limit = 5;

binmode STDOUT, ":utf8";

GetOptions("h|help" => \$help,
           "l|limit=i" => \$limit,
           "v|verbose" => \$verbose,
           "f|fulltext" => \$fulltext,
           "p|pdf" => \$pdfs)
  or pod2usage(1);

pod2usage(1) if ($help);

pod2usage(-message => "No query given", -verbose => 1)
  if (@ARGV == 0);

my $query = join(" ", @ARGV);

my @results = gscholar($query, $limit, $fulltext);

for my $result (@results[0..min($#results, $limit-1)]) {
  print $result->{bibtex};
  if ($pdfs && exists $result->{pdf}) {
    print "PDF: ", $result->{pdf}, "\n\n";
  }
}

__END__

=head1 bibfetch.pl

Script to fetch bibtex entries from Google Scholar.

=head1 SYNOPSIS

bibfetch.pl [-h] [-l LIMIT] [-v] [-f] [-p] QUERY

Search for QUERY using Google Scholar, and print at most LIMIT
matching bibtex entries. The resulting entries are separated by
newlines. If -p or --pdf is given, each entry may be followed by a
link to a pdf, preceded by "PDF: ".

  Options:
    -h|--help            This help message
    -v|--verbose         Print more information on stderr
    -l|--limit=LIMIT     Maximum number of entries to print (default: 5)
    -p|--pdf             Include PDF links in output (if any)
    -f|--fulltext        Search full article text, not just the title (default)

QUERY can contain anything Google Scholar accepts, such as
author:YourFavoriteResearcher.

=head1 BUGS

At the moment, this script only supports Google Scholar, but support
for some other search engines would be nice, too.

=head1 AUTHOR

Daniel Schoepe <daniel at schoepe.org>

=head1 LICENSE

This program is free software, licensed under the (3-clause) BSD license; see
the LICENSE file for details.

