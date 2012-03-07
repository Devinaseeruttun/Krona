# Copyright © 2011, Battelle National Biodefense Institute (BNBI);
# all rights reserved. Authored by: Brian Ondov, Nicholas Bergman, and
# Adam Phillippy
#
# See the LICENSE.txt file included with this software for license information.

use strict;

package KronaTools;

use Getopt::Long;
use File::Basename;
use File::Path;


use base 'Exporter';
use Cwd 'abs_path';

# public subroutines
#
our @EXPORT = qw
(
	addByEC
	addByLineage
	addByTaxID
	classifyBlast
	default
	getKronaOptions
	getOption
	getOptionString
	getScoreName
	getScriptName
	getTaxDepth
	getTaxName
	getTaxParent
	getTaxRank
	getTaxIDFromGI
	htmlFooter
	htmlHeader
	ktDie
	ktWarn
	loadEC
	loadMagnitudes
	loadTaxonomy
	newTree
	parseDataset
	printColumns
	printHeader
	printOptions
	printUsage
	setOption
	taxContains
	taxLowestCommonAncestor
	taxIDExists
	writeTree
);


###########
# Options #
###########

# The container for option values, initialized with global defaults.
#
my %options =
(
	'collapse' => 1,
	'color' => 0,
	'ecCol' => 2,
	'hueBad' => 0,
	'hueGood' => 120,
	'queryCol' => 1,
	'factor' => 10,
	'scoreCol' => 3,
	'key' => 1,
	'taxCol' => 2,
	'url' => 'http://krona.sourceforge.net'
);

# Option format codes to pass to GetOptions (and to be parsed for display).
# Multiple options can use the same option letter, as long as they don't
# conflict within any given script.
#
my %optionFormats =
(
	'bitScore' =>
		'b',
	'combine' =>
		'c',
	'depth' =>
		'd=i',
	'ecCol' =>
		'e=i',
	'factor' =>
		'e=f',
	'include' =>
		'i',
	'local' =>
		'l',
	'magCol' =>
		'm=i',
	'minConfidence' =>
		'm=f',
	'name' =>
		'n=s',
	'out' =>
		'o=s',
	'percentIdentity' =>
		'p',
	'phymm' =>
		'p',
	'noMag' =>
		'q',
	'queryCol' =>
		'q=i',
	'random' =>
		'r',
	'scoreCol' =>
		's=i',
	'summarize' =>
		's',
	'taxCol' =>
		't=i',
	'url' =>
		'u=s',
	'verbose' =>
		'v',
	'hueBad' =>
		'x=i',
	'hueGood' =>
		'y=i'
);

# how option arguments should be displayed based on format codes in %optionFormats
#
my %optionTypes =
(
	's' => 'string',
	'f' => 'number',
	'i' => 'integer'
);

# option descriptions to show in printOptions()
#
my %optionDescriptions =
(
	'bitScore' => 'Use bit score for average scores instead of log[10] e-value.',
	'combine' => 'Combine data from each file, rather than creating separate datasets within the chart.',
	'depth' => 'Maximum depth of wedges to include in the chart.',
	'ecCol' => 'Column of input files to use as EC number.',
	'factor' => 'E-value factor for determining "best" hits. Hits with e-values that are within this factor of the highest scoring hit will be included when computing the lowest common ancestor (or picking randomly if -r is specified).',
	'hueBad' => 'Hue (0-360) for "bad" scores.',
	'hueGood' => 'Hue (0-360) for "good" scores.',
	'percentIdentity' => 'Use percent identity for average scores instead of log[10] e-value.',
	'include' => 'Include a wedge for queries with no hits.',
	'local' => 'Create a local chart, which does not require an internet connection to view (but will only work on this computer).',
	'magCol' => 'Column of input files to use as magnitude. If magnitude files are specified, their magnitudes will override those in this column.',
	'minConfidence' => 'Minimum confidence. Each query sequence will only be added to taxa that were predicted with a confidence score of at least this value.',
	'name' => 'Name of the highest level.',
	'noMag' => 'Files do not have a field for quantity.',
	'out' => 'Output file name.',
	'phymm' => 'Input is phymm only (no confidence scores).',
	'queryCol' => 'Column of input files to use as query ID. Required if magnitude files are specified.',
	'random' => 'Pick from the best hits randomly instead of finding the lowest common ancestor.',
	'scoreCol' => 'Column of input files to use as score.',
	'summarize' => 'Summarize counts and average scores by taxonomy ID.',
	'taxCol' => 'Column of input files to use as taxonomy ID.',
	'url' => 'URL of Krona resources.',
	'verbose' => 'Verbose.'
);


#############
# Arguments #
#############

# how common arguments should be displayed
#
our %argumentNames =
(
	'blast' => 'blast_output',
	'magnitude' => 'magnitudes',
	'metarep' => 'metarep_folder',
	'name' => 'name',
);

# how common arguments should be described
#
our %argumentDescriptions =
(
	'blast' =>
'File containing BLAST results in tabular format ("Hit table (text)" when
downloading from NCBI).  If running BLAST locally, subject IDs in the local
database must contain GI numbers in "gi|12345" format.',
	'magnitude' =>
'Optional file listing query IDs with magnitudes, separated by tabs.  This can
be used to account for read length or contig depth to obtain a more accurate
representation of abundance.  By default, query sequences without specified
magnitudes will be assigned a magnitude of 1.  Magnitude files for assemblies in
ACE format can be created with ktGetContigMagnitudes.',
	'metarep' =>
'Unpacked METAREP data folder.',
	'name' =>
'A name to show in the list of datasets in the Krona chart (if multiple input
files are present and ' . getOptionString('combine') . ' is not specified). By
default, the basename of the file will be used.',
);


####################
# Global constants #
####################

my $libPath = `ktGetLibPath`;
my $taxonomyDir = "$libPath/../taxonomy";
my $ecFile = "$libPath/../data/ec.tsv";

my $javascriptVersion = '2.0';
my $javascript = "src/krona-$javascriptVersion.js";
my $image = "img/hidden.png";
my $favicon = "img/favicon.ico";
my $taxonomyHrefBase = 'http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?mode=info&id=';
my $ecHrefBase = 'http://www.chem.qmul.ac.uk/iubmb/enzyme/EC';

our $minEVal = -450;


#################
# Lookup tables #
#################

my @taxDepths;
my @taxParents;
my @taxRanks;
my @taxNames;
my %ecNames;


############
# Exported #
############


sub addByEC
{
	# add based on an EC number string
	#
	# Options used:
	# depth
	my
	(
		$node, # hash ref
		$set, # integer
		$ec, # array ref of ec number components (no dots)
		$queryID, # (optional) string
		$magnitude, # (optional) number
		$score, # (optional) number
		
		# for recursion only
		#
		$depth
	) = @_;
	
	if ( ! %ecNames )
	{
		ktDie('EC data not loaded. "loadEC()" must be called first.');
	}
	
	$magnitude = default($magnitude, 1);
	
	$node->{'magnitude'}[$set] += $magnitude;
	$node->{'count'}[$set]++;
	
	if ( ! @$ec )
	{
		$node->{'children'}{'No hits'}{'magnitude'}[$set] += $magnitude;
		$node->{'children'}{'No hits'}{'count'}[$set]++;
		
		if ( ! defined $node->{'children'}{'No hits'}{'scoreCount'} )
		{
			$node->{'children'}{'No hits'}{'scoreCount'}[0] = 0;
		}
		
		if ( $queryID )
		{
			addMember($node->{'children'}{'No hits'}, $set, $queryID);
		}
		
		return;
	}
	
	if
	(
		$depth < @$ec &&
		( ! $options{'depth'} || $depth < $options{'depth'} )
	)
	{
		my $ecString = join '.', @$ec[0..$depth];
		my $name = $ecNames{$ecString};
		my $child;
		
		if ( defined $node->{'children'}{$name} )
		{
			$child = $node->{'children'}{$name};
		}
		else
		{
			my %newChild = ();
			
			$node->{'children'}{$name} = \%newChild;
			$child = $node->{'children'}{$name};
			
			$child->{'ec'}[0] = $ecString;
		}
		
		if ( defined $score )
		{
			${$child->{'scoreTotal'}}[$set] += $score * $magnitude;
			${$child->{'scoreCount'}}[$set] += $magnitude;
		}
		
		addByEC($child, $set, $ec, $queryID, $magnitude, $score, $depth + 1);
	}
	else
	{
		if ( $queryID )
		{
			addMember($node, $set, $queryID);
		}
		
		$node->{'unassigned'}[$set]++;
	}
}

sub addByLineage
{
	# add based on an explicit lineage
	#
	# Options used:
	# depth, minConfidence, leafAdd
	
	my
	(
		$node, # hash ref
		$dataset, # integer
		$lineage, # array ref
		$queryID, # (optional) string
		$magnitude, # (optional) number
		$scores, # (optional) number or array ref
		$ranks, # (optional) array ref
		
		# for recursion only
		#
		$index, # current index of input arrays
		$depth # our node depth (since input array elements can be skipped)
	) = @_;
	
	$magnitude = default($magnitude, 1);
	
	if ( $options{'leafAdd'} )
	{
		# magnitudes are already summarized; instead of adding magnitude to
		# ancestors, directly set it for the lowest level of the lineage and
		# for any ancestors whose magnitude is undefined (in case they are
		# never specified)
		
		if ( ! defined $node->{'magnitude'}[$dataset] || $index == @$lineage )
		{
			$node->{'magnitude'}[$dataset] = $magnitude;
		}
	}
	else
	{
		$node->{'magnitude'}[$dataset] += $magnitude;
	}
	
	$node->{'count'}[$dataset]++;
	
	# skip nameless nodes
	#
	while ( $$lineage[$index] eq '' && $index < @$lineage )
	{
		$index++;
	}
	
	my $score;
	
	if ( ref($scores) eq 'ARRAY' )
	{
		$score = $$scores[$index];
	}
	else
	{
		$score = $scores;
	}
	
	if
	(
		$index < @$lineage &&
		( ! $options{'depth'} || $depth < $options{'depth'} ) &&
		(
			! defined $options{'minConfidence'} ||
			! defined $score ||
			$score >= $options{'minConfidence'}
		)
	)
	{
		my $name = $$lineage[$index];
		my $child;
		
		if ( defined ${$node}{'children'}{$name} )
		{
			$child = ${$node}{'children'}{$name};
		}
		else
		{
			my %newHash = ();
			${$node}{'children'}{$name} = \%newHash;
			$child = ${$node}{'children'}{$name};
			
			if ( $ranks )
			{
				$child->{'rank'}[0] = $$ranks[$index];
			}
		}
		
		if ( defined $score )
		{
			if ( $options{'leafAdd'} )
			{
				# instead of averaging score for ancestors, directly set it
				# for the lowest level of the lineage and for any ancestors
				# whose score is undefined (in case they are never
				# specified)
				
				if
				(
					! defined $child->{'scoreTotal'}[$dataset] ||
					$index == @$lineage - 1
				)
				{
					$child->{'scoreTotal'}[$dataset] = $score;
					$child->{'scoreCount'}[$dataset] = 1;
				}
			}
			else
			{
				$child->{'scoreTotal'}[$dataset] += $score * $magnitude;
				$child->{'scoreCount'}[$dataset] += $magnitude;
			}
		}
		
		addByLineage
		(
			$child,
			$dataset,
			$lineage,
			$queryID,
			$magnitude,
			$scores,
			$ranks,
			$index + 1,
			$depth + 1
		);
	}
	else
	{
		if ( $queryID )
		{
			addMember($node, $dataset, $queryID);
		}
		
		$node->{'unassigned'}[$dataset]++;
	}
}

sub addByTaxID
{
	# add based on NCBI taxonomy ID
	#
	# Options used:
	# depth
	
	my
	(
		$node, # hash ref
		$set, # integer
		$taxID, # integer
		$queryID, # string (optional)
		$magnitude, # number (optional)
		$score, # number (optional)
		
		# recusive only
		#
		$assigned
	) = @_;
	
	$magnitude = default($magnitude, 1);
	
	if ( $taxID == 0 )
	{
		$node->{'count'}[$set]++;
		$node->{'children'}{'No hits'}{'count'}[$set]++;
		
		my $child = $node->{'children'}{'No hits'};
		
		$node->{'magnitude'}[$set] += $magnitude;
		$child->{'magnitude'}[$set] += $magnitude;
		
		if ( ! defined $child->{'scoreCount'} )
		{
			$child->{'scoreCount'}[0] = 0;
		}
		
		if ( $queryID )
		{
			addMember($child, $set, $queryID);
		}
		
		return;
	}
	
	# move up to depth and skip unranked taxonomy nodes
	#
	while
	(
		$taxID > 1 && $taxRanks[$taxID] eq 'no rank' ||
		$options{'depth'} && $taxDepths[$taxID] > $options{'depth'}
	)
	{
		$taxID = $taxParents[$taxID];
	}
	
	# get parent recursively
	#
	my $parent;
	#
	if ( $taxParents[$taxID] != 1 )#$taxID )
	{
		$parent = addByTaxID($node, $set, $taxParents[$taxID], undef, $magnitude, $score, 1);
	}
	else
	{
		$parent = $node;
		$parent->{'count'}[$set]++;
		$parent->{'magnitude'}[$set] += $magnitude;
	}
	
	# add this node to parent
	#
	if ( $taxID == 1 )
	{
		if ( $queryID )
		{
			addMember($parent, $set, $queryID);
		}
		
		$parent->{'unassigned'}[$set]++;
	}
	else
	{
		my $name = $taxNames[$taxID];
		
		my $child;
		
		if ( defined $parent->{'children'}{$name} )
		{
			$child = $parent->{'children'}{$name};
		}
		else
		{
			my %newChild = ();
			
			$parent->{'children'}{$name} = \%newChild;
			$child = $parent->{'children'}{$name};
			
			$child->{'rank'}[0] = $taxRanks[$taxID];
			$child->{'taxon'}[0] = taxonLink($taxID);
		}
		
		if ( $queryID )
		{
			addMember($child, $set, $queryID);
		}
		
		${$child->{'count'}}[$set]++;
		
		if ( ! $assigned )
		{
			$child->{'unassigned'}[$set]++;
		}
		
		${$child->{'magnitude'}}[$set] += $magnitude;
		
		if ( defined $score )
		{
			$magnitude = default($magnitude, 1);
			${$child->{'scoreTotal'}}[$set] += $score * $magnitude;
			${$child->{'scoreCount'}}[$set] += $magnitude;
		}
		
		return $child;
	}
}

sub classifyBlast
{
	# taxonomically classifies BLAST results based on LCA (or random selection)
	# of 'best' hits.
	#
	# Options used: bitScore, factor, include, percentIdentity, random, score
	
	my # parameters
	(
		$fileName, # file with tabular BLAST results
		
		# hash refs to be populated with results (keyed by query ID)
		#
		$taxIDs,
		$scores
	) = @_;
	
	open BLAST, "<$fileName" or ktDie("Could not open $fileName\n");
	
	my $lastQueryID;
	my $topScore;
	my $topEVal;
	my $ties;
	my $taxID;
	my $totalScore;
	my $zeroEVal;
	
	while ( 1 )
	{
		my $line = <BLAST>;
		
		chomp $line;
		
		if ( $line =~ /^#/ )
		{
			if ( $line =~ /Query: ([\S]+)/ )
			{
				# Initialize taxID and score in case this query has no hits
				
				$taxIDs->{$1} = -1;
				$scores->{$1} = 0;
			}
			
			next;
		}
		
		my
		(
			$queryID,
			$hitID,
			$identity,
			$length,
			$mismatches,
			$gaps,
			$queryStart,
			$queryEnd,
			$subjectStart,
			$subjectEnd,
			$eVal,
			$bitScore
		) = split /\t/, $line;
		
		if ( $queryID ne $lastQueryID )
		{
			if
			(
				! defined $lastQueryID &&
				! defined $taxIDs->{$queryID} &&
				$options{'include'}
			)
			{
				ktWarn("-i specified but $fileName does not contain comment lines. Queries with no hits will not be included for this file."); 
			}
			if (  defined $taxID )
			{
				# add the chosen hit from the last queryID
				
				$taxIDs->{$lastQueryID} = $taxID;
				$scores->{$lastQueryID} = $totalScore / $ties;
			}
			$ties = 0;
			$totalScore = 0;
		}
		
		if ( ! defined $hitID )
		{
			last; # EOF
		}
		
		$hitID =~ /gi\|(\d+)/;
		
		my $gi = $1;
		
		if # this is a 'best' hit if...
		(
			$queryID ne $lastQueryID || # new query ID (including null at EOF)
			$eVal <= $options{'factor'} * $topEVal # within e-val factor
		)
		{
			# add score for average
			#
			if ( $options{'percentIdentity'} )
			{
				$totalScore += $identity;
			}
			elsif ( $options{'bitScore'} )
			{
				$totalScore += $bitScore;
			}
			else
			{
				if ( $eVal > 0 )
				{
					$totalScore += (log $eVal) / log 10;
				}
				else
				{
					$totalScore += $minEVal;
					$zeroEVal = 1;
				}
			}
			#
			$ties++;
			
			if # use this hit if...
			(
				! $options{'random'} || # using LCA
				$queryID ne $lastQueryID || # new query ID
				int(rand($ties)) == 0 # randomly chosen to replace other hit
			)
			{
				my $newTaxID = getTaxIDFromGI($gi);
				
				if ( ! $newTaxID )
				{
					$newTaxID = 1;
				}
				
				if ( $queryID ne $lastQueryID || $options{'random'} )
				{
					$taxID = $newTaxID;
				}
				else
				{
					$taxID = taxLowestCommonAncestor($taxID, $newTaxID);
				}
			}
		}
		
		if ( $queryID ne $lastQueryID )
		{
			$topScore = $bitScore;
			$topEVal = $eVal;
		}
		
		$lastQueryID = $queryID;
	}
	
	if ( $zeroEVal )
	{
		ktWarn("\"$fileName\" had e-values of 0. Approximated log[10] of 0 as $minEVal.");
	}
}	

sub default
{
	# Use a variable if it is defined or return a default value if it is not.
	
	my ($value, $default) = @_;
	
	if ( defined $value )
	{
		return $value;
	}
	else
	{
		return $default;
	}
}

sub getKronaOptions
{
	# Parse command line arguments and set options using Getopt::Long
	
	my @options = @_;
	
	my %params;
	
	foreach my $option ( @options )
	{
		$params{$optionFormats{$option}} = \$options{$option};
	}
	
	if ( ! GetOptions(%params) )
	{
		exit;
	}
	
	validateOptions();
}

sub getOption
{
	my ($option) = @_;
	
	return $options{$option};
}

sub getOptionString
{
	# Make a string from the option format to show as the command line option
	
	my ($option) = @_;
	
	my ($short, $type) = split /=/, $optionFormats{$option};
	my $string = "[-$short";
	
	if ( defined $type )
	{
		$string .= " <$optionTypes{$type}>";
	}
	
	$string .= ']';
	
	return $string;
}

sub getScoreName
{
	if ( getOption('bitScore') )
	{
		return 'Avg. bit score';
	}
	elsif ( getOption('percentIdentity') )
	{
		return 'Avg. % identity';
	}
	else
	{
		return 'Avg. log e-value';
	}
}

sub getScriptName
{
	return fileparse($0);
}

sub getTaxDepth
{
	my ($taxID) = @_;
	checkTaxonomy();
	return taxDepths[$taxID];
}

sub getTaxName
{
	my ($taxID) = @_;
	checkTaxonomy();
	return $taxNames[$taxID]
}

sub getTaxParent
{
	my ($taxID) = @_;
	checkTaxonomy();
	return $taxParents[$taxID];
}

sub getTaxRank
{
	my ($taxID) = @_;
	checkTaxonomy();
	return $taxRanks[$taxID];
}

sub getTaxIDFromGI
{
	my ($gi) = @_;
	
	if ( ! open GI, "<$taxonomyDir/gi_taxid.dat" )
	{
		print "ERROR: GI to TaxID data not found.  Was updateTaxonomy.sh run?\n";
		exit 1;
	}
	
	seek GI, $gi * 4, 0;
	
	my $data;
	
	read GI, $data, 4;
	
	my $taxID = unpack "L", $data;
	
	close GI;
	
	if ( 0 && $taxID == 0 )
	{
		return 1;
	}
	else
	{
		return $taxID;
	}
}

sub htmlFooter
{
	return "</div></body></html>\n";
}

sub htmlHeader
{
	my $javascriptPath;
	my $imagePath;
	my $faviconPath;
	my $path;
	my $notFound;
	
	if ( $options{'local'} )
	{
		$path = "$libPath/../";
		$notFound = "This is a local chart and must be viewed on the computer it was created with.";
	}
	else
	{
		$path = "$options{'url'}/";
		$notFound = "Could not get resources from \\\"$options{'url'}\\\".";
	}
	
	return
		'<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">' . "\n" .
		'<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">' . "\n" .
		indent(1) . "<head>\n" .
			indent(2) . "<meta charset=\"utf-8\"/>\n" .
#			indent(2) . "<base href=\"$path\" target=\"_blank\"/>\n" .
			indent(2) . "<link rel=\"shortcut icon\" href=\"$path$favicon\"/>\n" .
			indent(2) . "<script id=\"notfound\">window.onload=function(){document.body.innerHTML=\"$notFound\"}</script>\n" .
			indent(2) . "<script src=\"$path$javascript\"></script>\n" .
		indent(1) . "</head>\n" .
		indent(1) . "<body>\n" .
			indent(2) . "<img id=\"hiddenImage\" src=\"$path$image\" style=\"display:none\"/>\n" .
			indent(2) . "<noscript>Javascript must be enabled to view this page.</noscript>\n" .
			indent(2) . "<div style=\"display:none\">\n";
}

sub ktDie
{
	my ($error) = @_;
	
	*STDOUT = *STDERR;
	printColumns('[ ERROR ]', $error);
	exit 1;
}

sub ktWarn
{
	my ($warning) = @_;
	
	printColumns('   [ WARNING ]', $warning);
}

sub loadEC
{
	open EC, "<$ecFile" or die "$ecFile not found.";
	
	<EC>; # eat header
	
	while ( <EC> )
	{
		chomp;
		my ($ec, $name) = split /\t/;
		$ecNames{$ec} = $name;
	}
	
	close EC;
}

sub loadMagnitudes
{
	# load magnitudes from a tab-delimited file listing query IDs and magnitudes
	
	my
	(
		$magFile, # file name
		$magnitudes # hash ref (to be populated)
	) = @_;
	
	open MAG, "<$magFile" or die "Couldn't load $magFile";
	
	while ( my $line = <MAG> )
	{
		chomp $line;
		my ( $id, $mag ) = split /\t/, $line;
		$magnitudes->{$id} = $mag;
	}
	
	close MAG;
}

sub loadTaxonomy
{
	open INFO, "<$taxonomyDir/taxonomy.tab" or die
		"Taxonomy not found.  Was updateTaxonomy.sh run?";
	
	while ( my $line = <INFO> )
	{
		chomp $line;
		my ($id, $depth, $parent, $rank, $name) = split /\t/, $line;
		
		$taxParents[$id] = $parent;
		$taxDepths[$id] = $depth;
		$taxRanks[$id] = $rank;
		$taxNames[$id] = $name;
	}
	
	close INFO;
}

sub newTree
{
	my %tree = ();
	return \%tree;
}

sub parseDataset
{
	my ($input) = @_;
	
	$input =~ /([^:,]+)(:([^,]+))?(,"?([^"]+)"?)?/;
	
	my ($file, $mag, $name) = ($1, $3, $5);
	
	if ( ! defined $name )
	{
		$name = fileparse($file, qr/\.[^.]*/); # get dataset name from file
	}
	
	$name =~ s/</&amp;lt;/g;
	$name =~ s/>/&amp;gt;/g;
	
	return ($file, $mag, $name);
}

sub printColumns
{
	# Prints headers and descriptions in two columns. Even indeces of the
	# parameters should be headers (left column); odd indeces should be
	# descriptions (right column).
	
	my @columns = @_;
	
	my $maxHeaderLength;
	
	for ( my $i = 0; $i < @columns; $i += 2 )
	{
		if ( length $columns[$i] > $maxHeaderLength )
		{
			$maxHeaderLength = length $columns[$i];
		}
	}
	
	for ( my $i = 0; $i < @columns; $i += 2 )
	{
		if ( $i > 0 )
		{
			print "\n";
		}
		
		printHangingIndent
		(
			$columns[$i],
			$columns[$i + 1],
			$maxHeaderLength + 2
		);
	}
}

sub printHeader
{
	# Prints a string with decoration
	
	my ($header) = @_;
	
	my $width = length($header) + 2;
	
	print ' ', '_' x $width, "\n";
	print '/ ', $header, " \\\n";
	print '\\', '_' x $width, "/\n\n";
}

sub printOptions
{
	# Takes a list of standard KronaTools options (defined in
	# %optionDescriptions) and prints them with their descriptions in columns.
	
	my @options = @_;
	
	my @optionColumns;
	
	foreach my $option ( @options )
	{
		my $header = '   ' . getOptionString($option);
		my $description = $optionDescriptions{$option};
		
		if ( defined $options{$option} )
		{
			$description .= " [Default: '$options{$option}']";
		}
		
		push @optionColumns, $header, $description;
	}
	
	printHeader('Options');
	printColumns(@optionColumns);
	print "\n";
}

sub printUsage
{
	my
	(
		$description, # script description
		$argumentName,
		$argumentDescription,
		$useMagnitude, # show optional magnitude argument
		$useName, # show optional name argument
		$options # array ref of option names, defined in %option*
	) = @_;
	
	my $scriptName = getScriptName();
	
	printHeader($scriptName);
	printHangingIndent('', $description);
	printHeader('Usage');
	print "$scriptName \\\n";
	print "   [options] \\\n";
	print
		'   ', 
		argumentString($argumentName, $useMagnitude, $useName, 1),
		" \\\n";
	print
		'   ',
		argumentString($argumentName, $useMagnitude, $useName, 2),
		" \\\n";
	print "   ...\n\n";
	
	my $combineString;
	
	foreach my $option ( @$options )
	{
		if ( $option eq 'combine' )
		{
			$combineString =
' By default, separate datasets will be created for each input (see ' .
getOptionString('combine') . ').'
		}
	}
	
	my @columns =
	(
		"   $argumentName",
		$argumentDescription . $combineString
	);
	
	if ( $useMagnitude )
	{
		push @columns,
			"   $argumentNames{'magnitude'}",
			$argumentDescriptions{'magnitude'};
	}
	
	if ( $useName )
	{
		push @columns,
			"   $argumentNames{'name'}",
			$argumentDescriptions{'name'};
	}
	
	printColumns(@columns);
	printOptions(@$options);
}

sub setOption
{
	my ($option, $value) = @_;
	
	$options{$option} = $value;
}

sub taxContains
{
	# determines if $parent is an ancestor of (or equal to) $child
	
	my ($parent, $child) = @_;
	
	my $depthParent = $taxDepths[$parent];
	
	while ( $taxDepths[$child] > $taxDepths[$parent] )
	{
		$child = $taxParents[$child];
	}
	
	return $parent == $child;
}

sub taxLowestCommonAncestor
{
	my ($a, $b) = @_;
	
	# degenerate case optimizations
	#
	if ( $a == $b )
	{
		return $a;
	}
	#
	if ( $a == 1 || $b == 1 )
	{
		return 1;
	}
	
	checkTaxonomy();
	
	# walk the nodes up to an equal depth
	#
	my $depthA = $taxDepths[$a];
	my $depthB = $taxDepths[$b];
	#
	while ( $depthA > $depthB )
	{
		$a = $taxParents[$a];
		$depthA--;
	}
	#
	while ( $depthB > $depthA )
	{
		$b = $taxParents[$b];
		$depthB--;
	}
	
	# now walk both up until they are equal
	#
	while ( $a != $b )
	{
		if ( $a == 1 || $b == 1 )
		{
			# one reached to top first; this shouldn't happen
			
			warn "No common ancestor found for $a and $b; $depthA $depthB";
			return 1;
		}
		
		$a = $taxParents[$a];
		$b = $taxParents[$b];
	}
	
	return $a;
}

sub taxIDExists
{
	my ($taxID) = @_;
	checkTaxonomy();
	return defined $taxDepths[$taxID];
}

sub writeTree
{
	# Writes a Krona chart from a tree created with "addBy..." functions.
	#
	# Uses options: collapse, color, local, name, out, showKey, url
	
	my
	(
		$tree, # hash ref to head node of tree
		$attributes, # array ref with names of attributes to display
		$attributeDisplayNames, # array ref with display names for $attributes
		$datasetNames, # array ref with names of datasets
		$hueStart, # (optional) hue at the start of the gradient for score
		$hueEnd # (optional) hue at the end of the gradient for score
	) = @_;
	
	my %attributeHash;
	
	for ( my $i = 0; $i < @$attributes; $i++ )
	{
		$attributeHash{$$attributes[$i]} = $$attributeDisplayNames[$i];
	}
	
	my ($valueStart, $valueEnd);
	
	if ( defined $hueStart && defined $hueEnd )
	{
		($valueStart, $valueEnd) = setScores($tree);
	}
	
	print "Writing $options{'out'}...\n";
	
	open OUT, ">$options{'out'}";
	print OUT htmlHeader();
	print OUT dataHeader
	(
		defined $attributeHash{'magnitude'} ? 'magnitude' : 'count',
		$attributes,
		$attributeDisplayNames,
		$datasetNames,
		'unassigned',
		'count',
		defined $hueStart ? 'score' : undef,
		$hueStart,
		$hueEnd,
		$valueStart,
		$valueEnd
	);
	my $nodeID = 0;
	print OUT toStringXML($tree, $options{'name'}, 0, \%attributeHash, \$nodeID);
	print OUT dataFooter();
	print OUT htmlFooter();
	close OUT;
}


################
# Not exported #
################


sub addMember
{
	my ($node, $set, $member) = @_;
	
#	$member =~ s/,/\\,/g;
#	$member =~ s/ /&#32;/g;
#	$member =~ s/"/&quot;/g;
	
	push @{$node->{'members'}[$set]}, $member;
}

sub argumentString
{
	my
	(
		$argumentName,
		$useMagnitude,
		$useName,
		$number
	) = @_;
	
	my $return;
	
	my $numberString;
	
	if ( $number > 0 )
	{
		$numberString = "_$number";
	}
	
	if ( $number > 1 )
	{
		$return .= '[';
	}
	
	$return .= "$argumentName$numberString";
	
	if ( $useMagnitude )
	{
		$return .= "[:$argumentNames{'magnitude'}$numberString]";
	}
	
	if ( $useName )
	{
		$return .= "[,$argumentNames{'name'}$numberString]";
	}
	
	if ( $number > 1 )
	{
		$return .= ']';
	}
	
	return $return;
}

sub checkTaxonomy
{
	if ( ! @taxParents )
	{
		die 'Taxonomy not loaded. "loadTaxonomy()" must be called first.';
	}
}

sub dataFooter
{
	return indent(2) . "</krona>\n";
}

sub dataHeader
{
	my
	(
		$magName,
		$attributes,
		$attributeDisplayNames,
		$datasetNames,
		$assignedName,
		$summaryName,
		$hueName,
		$hueStart,
		$hueEnd,
		$valueStart,
		$valueEnd
	) = @_;
	
	my $header =
	indent(2) . '<krona collapse="' . ($options{'collapse'} ? 'true' : 'false') .
	'" key="' . ($options{'key'} ? 'true' : 'false') . "\">\n" .
	indent(3) . "<attributes magnitude=\"$magName\">\n";
	
	# members
	#
	my $assignedText;
	my $summaryText;
	#
	if ( $assignedName && $summaryName )
	{
		$header .= indent(4) . "<list>members</list>\n";
		$assignedText = " listNode=\"members\"";
		$summaryText = " listAll=\"members\"";
		
		my $outDir = "$options{'out'}.files";
		
		if ( -e $outDir )
		{
			rmtree $outDir or die $!;
		}
		
		mkdir $outDir or die $!;
	}
	
	# attributes
	#
	for ( my $i = 0; $i < @$attributes; $i++ )
	{
		my $attributeText;
		my $name = $$attributes[$i];
		
		if ( $$attributeDisplayNames[$i] )
		{
			$attributeText .= " display=\"$$attributeDisplayNames[$i]\"";
		}
		
		if ( $name eq 'count' )
		{
			# attach to list of members as summary of children
			
			$attributeText .= $summaryText;
		}
		elsif ( $name eq 'unassigned' )
		{
			# attach to list of members as node list
			
			$attributeText .= $assignedText;
		}
		elsif ( $name eq 'taxon' )
		{
			$attributeText .= " hrefBase=\"$taxonomyHrefBase\" target=\"taxonomy\"";
		}
		elsif ( $name eq 'ec' )
		{
			$attributeText .= " hrefBase=\"$ecHrefBase\" target=\"ec\"";
		}
		
		if
		(
			$name eq 'taxon' ||
			$name eq 'ec' ||
			$name eq 'rank'
		)
		{
			$attributeText .= ' mono="true"';
		}
		
		$header .= indent(4) . "<attribute$attributeText>$$attributes[$i]</attribute>\n";
	}
	
	$header .= indent(3) . "</attributes>\n";
	
	if ( @$datasetNames )
	{
		$header .= indent(3) . "<datasets>\n";
		
		foreach my $dataset ( @$datasetNames )
		{
			$dataset =~ s/</&lt;/g;
			$dataset =~ s/>/&gt;/g;
			
			$header .= indent(4) . "<dataset>$dataset</dataset>\n";
		}
		
		$header .= indent(3) . "</datasets>\n";
	}
	
	# hue
	#
	if ( defined $hueName )
	{
		my $colorDefault = $options{'color'} ? 'true' : 'false';
		
		$header .=
			indent(3) . "<color attribute=\"$hueName\" " .
			"hueStart=\"$hueStart\" hueEnd=\"$hueEnd\" " .
			"valueStart=\"$valueStart\" valueEnd=\"$valueEnd\" " .
			"default=\"$colorDefault\" " .
			"></color>\n";
	}
	
	return $header;
}

sub ecLink
{
	my ($ec) = @_;
	
	my $path = $ec;
	
	my $count = ($path =~ s/\./\//g);
	
	if ( $count == 3 )
	{
		$path .= ".html";
	}
	
	return $path;
}

sub ecText
{
	my ($ec) = @_;
	
	return "EC $ec";
}

sub indent
{
	my ($depth) = @_;
	
	return ' ' x $depth;
}

sub printHangingIndent
{
	my ($header, $text, $tab) = @_;
	
	my @words = split /\s+/, $text;
	
	my $col;
	
	if ( $header )
	{
		print $header, ' ' x ($tab - (length $header) - 1);
		$col = $tab;
	}
	else
	{
		my $word = shift @words;
		print $word;
		$col = length $word;
	}
	
	foreach my $word ( @words )
	{
		my $wordLength = length $word;
		
		if ( $col + $wordLength + 1 >= 80 )
		{
			print "\n", ' ' x $tab, $word;
			$col = $tab + $wordLength;
		}
		else
		{
			print " $word";
			$col += $wordLength + 1;
		}
	}
	
	print "\n";
}

sub setScores
{
	my ($node) = @_;
	
	my $min;
	my $max;
	
	if ( defined $node->{'scoreCount'} )
	{
		$node->{'score'} = ();
		
		for ( my $i = 0; $i < @{$node->{'scoreCount'}}; $i++ )
		{
			my $score;
			
			if ( ${$node->{'scoreCount'}}[$i] )
			{
				$score =
					${$node->{'scoreTotal'}}[$i] /
					${$node->{'scoreCount'}}[$i];
				
				if ( $options{'logScore'} )
				{
					if ( $score > 0 )
					{
						$score = (log $score) / log 10;
					}
					else
					{
						$score = $minEVal;
					}
				}
				
				if ( ! defined $min || $score < $min )
				{
					$min = $score;
				}
				
				if ( ! defined $max || $score > $max )
				{
					$max = $score;
				}
			}
			else
			{
				$score = 0;
			}
			
			${$node->{'score'}}[$i] = sprintf("%g", $score);
		}
	}
	
	if ( defined $node->{'children'} )
	{
		foreach my $child (keys %{$node->{'children'}})
		{
			my ($childMin, $childMax) =
				setScores($node->{'children'}{$child});
			
			if ( ! defined $min || $childMin < $min )
			{
				$min = $childMin;
			}
			
			if ( ! defined $max || $childMax > $max )
			{
				$max = $childMax;
			}
		}
	}
	
	return ($min, $max);
}

sub taxonLink
{
	my ($taxID) = @_;
	
	return $taxID;
}

sub toStringXML
{
	my ($node, $name, $depth, $attributeHash, $nodeIDRef) = @_;
	
	my $string;
	my $href;
	
	if ( $node->{'href'} )
	{
		$href = " href=\"$node->{'href'}\"";
	}
	
	$string = indent($depth) . "<node name=\"$name\" id=\"$$nodeIDRef\"$href>\n";
	
	foreach my $key ( keys %$node )
	{
		##
		if ( $key eq 'members' )
		{
			$string .= '<members>';
			
			my $i = 0;
			foreach my $set ( @{$node->{$key}} )
			{
				if ( @$set > 0 )
				{
					my $file = "node$$nodeIDRef.members.$i";
					
					$string .= "<val>$file</val>";
					
					open SUPP, ">$options{'out'}.files/$file" or die;
					$i++;
					
					#print SUPP "var node$$nodeIDRef = '";
					print SUPP "window.nodeData.push('";
					#print SUPP "document.body.innerHTML += '";
					foreach my $value ( @$set )
					{
						print SUPP "$value<br/>\\\n";
					}
					print SUPP "');";
					
					close SUPP;
				}
			}
			
			$string .= '</members>';
		}
		##
		elsif
		(
			$key ne 'children' &&
			$key ne 'scoreCount' &&
			$key ne 'scoreTotal' &&
			$key ne 'href' &&
			( keys %{$node->{'children'}} || $key ne 'unassigned' ) &&
			( $key eq 'members' || defined $$attributeHash{$key} )
		)
		{
			$string .= indent($depth + 1) . "<$key>";
			
			foreach my $value ( @{$node->{$key}} )
			{
				if ( $key eq 'members' )
				{
					$string .= "\n" . indent($depth + 2) . "<vals>";
					
					foreach my $member ( @$value )
					{
						$member =~ s/</&lt;/g;
						$member =~ s/>/&gt;/g;
						
						$string .= "<val>$member</val>";
					}
					
					$string .= "</vals>";
				}
				else
				{
					my $href;
					
					if ( $key eq 'taxon' )
					{
						$href = ' href="' . taxonLink($value) . '"';
					}
					elsif ( $key eq 'ec' )
					{
						$href = ' href="' . ecLink($value) . '"';
						$value = ecText($value);
					}
					
					$value =~ s/</&lt;/g;
					$value =~ s/>/&gt;/g;
					
					$string .= "<val$href>$value</val>";
				}
			}
			
			if ( $key eq 'members' )
			{
				$string .= "\n" . indent($depth + 1);
			}
			
			$string .= "</$key>\n";
		}
	}
	
	$$nodeIDRef++;
	
	if ( defined $node->{'children'} )
	{
		foreach my $child (keys %{$node->{'children'}})
		{
			$string .= toStringXML($node->{'children'}{$child}, $child, $depth + 1, $attributeHash, $nodeIDRef);
		}
	}
	
#	print "$string\n";
	return $string . indent($depth) . "</node>\n";
}

sub validateOptions
{
	if ( $options{'factor'} < 1 )
	{
		my $factor = getOptionString('factor');
		ktDie("E-value factor ($factor) must be at least 1.");
	}
	
	if ( $options{'percentIdentity'} && $options{'bitScore'} )
	{
		my $pi = getOptionString('percentIdentity');
		my $bs = getOptionString('bitScore');
		
		ktDie("Cannot use $bs and $pi together.");
	}
}


1;
