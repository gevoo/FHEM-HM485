#!/usr/bin/perl

=head1 NAME

XMLHelper.pl

=head1 SYNOPSIS

XMLHelper.pl -inputFile </input/path> -outputPath </output/path> [-indentStyle <0..2>]

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-imputFile>

The path to the input xml file

=item B<-outputPath>

The path to the output pm file

=item B<-indentStyle>

Controls the style of indentation. It can be set to 0, 1, 2.
0: spews output without any newlines, indentation, or spaces between list items. It is the most compact format possible that can still be called valid perl.
1: (the default) outputs a readable form with newlines but no fancy indentation (each level in the structure is simply indented by a fixed amount of whitespace).
2: outputs a very readable form which takes into account the length of hash keys (so the hash value lines up).

=back

=head1 DESCRIPTION

This is the helper to convert and translate the device xml files to device pm files 
 used by the HM485 FHEM module.
 
Contributed by Dirk Hoffmann 2014

=cut

package main;

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename;
use Getopt::Long;
use Pod::Usage;
use XML::Simple;
use FindBin;
use lib abs_path("$FindBin::Bin/..");
use Data::Dumper;

my $indentStyle = 2;

sub main();
sub convertFiles($$);
sub dumperSortkey($);
sub printDump($$$);
sub reMap($);

################################################

sub main() {
	my $scriptPath = '';
	$scriptPath = dirname(abs_path($0)) . '/';

	my $inputFile = '';
	my $outputPath = '';
	my $help = 0;
	my $man = 0;
	GetOptions (
		'inputFile=s'  => \$inputFile,
		'outputPath=s' => \$outputPath,
		'indentStyle:1' => \$indentStyle,
		'help|?'       => \$help,
		'man'          => \$man
	);

	pod2usage(1) if ($help);
	pod2usage(-verbose => 2) if ($man);

	if (!$inputFile || !$outputPath || $indentStyle < 0 || $indentStyle > 2) {
		pod2usage()
	} else {
		if (-d $outputPath) {
			my @inputFiles = @ARGV;
			push (@inputFiles, $inputFile);
			if (scalar(@inputFiles) > 0) {
				print "\n" . 'processing file' . ((scalar(@inputFiles) > 1) ? 's' : '') . ":\n";
				foreach my $item (@inputFiles){
					convertFile($item, $outputPath . '/', $indentStyle);
				}			
			} 
		} else {
			print 'The output path must be a directory.' . "\n";
		}
	}
}

sub convertFile($$) {
	my ($inputFile, $outputPath) = @_;
	my $outputFile = $outputPath . substr(basename($inputFile),0,-4) . '.pm';
	$outputFile=~ s/\/\//\//g;
	
	print $inputFile . ' -> ' . $outputFile . "\n";
	
	my $xml = XMLin($inputFile);
	$xml = reMap($xml);
	$xml->{'frames'} = $xml->{'frames'}->{'frame'};
	$xml->{'channels'} = $xml->{'channels'}->{'channel'};
	
	$xml->{'channels'} = fixChannelPeerAdresses($xml->{'channels'});
	
	my $defKey = uc(substr(basename($inputFile),0,-4));
	$defKey =~ s/-/_/g;

	$Data::Dumper::Terse = 1;
	$Data::Dumper::Indent = $indentStyle;
	$Data::Dumper::Quotekeys = 0;
	$Data::Dumper::Useqq = 1;

	my $tab = "\t";
	if ($indentStyle != 0) {
		$Data::Dumper::Quotekeys = 1;
		$Data::Dumper::Pad = $tab;
	}
	
	$Data::Dumper::Sortkeys = \&dumperSortkey;

	my $content = 'package HM485::Devicefile;' . "\n";
	my $lf = ($indentStyle != 0) ? "\n" : '';

	$content.= 'our %definition = (' . ($lf ? $lf . $tab : '') . '\'' . $defKey . '\' => {' . $lf;

	$content.= lc(printDump('version', $xml->{'version'}, 2));
	$content.= lc(printDump('eep_size', $xml->{'eep_size'}, 2));
	$content.= printDump('supported_types', $xml->{'supported_types'}, 2);
	$content.= lc(printDump('paramset', $xml->{'paramset'}, 2));
	$content.= lc(printDump('frames', $xml->{'frames'}, 2));
	$content.= lc(printDump('channels', $xml->{'channels'}, 2));
	$content.=  $tab . '}' . $lf. ');	' . $lf;
	
	$content =~ s/(\s*=>\s*)(0x[0-9])([a-z])(.*)/$1.$2.uc($3).$4/ge;	# hex Kleinbuchstaben in hex Großbuchstaben
	$content =~ s/(\s*=>\s*)(0x)([a-z]{1,4})(.*)/$1.$2.uc($3).$4/ge;	# hex Kleinbuchstaben in hex Großbuchstaben
	
	open(FH, ">$outputFile") or die('Error opening "' . $outputFile . '"');
	print FH $content;
	#print FH "@{[ %($xml) ]}\n";
	#foreach my $key (keys %{$xml}) {
	#	if (ref($xml->{$key}) eq 'HASH') {
	#		my $x1 = $xml->{$key};
	#		print FH "$key -->\n";
	#		foreach my $k1 (keys %{$x1}) {
	#			print FH "$k1 => $x1->{$k1}\n";
	#		}
	#	} else {
	#		print FH "$key => $xml->{$key}\n";
	#	}
	#}
	close(FH);
}

sub dumperSortkey($) {
	my ($hash) = @_;
	return [(sort keys %$hash)];
}

sub printDump($$$) {
	my ($key, $value, $tiefe) = @_;

	my $retVal = '';
	if ($value) {
		$retVal = Dumper($value);
		
		chop ($retVal);
		my $tab = "\t";
		$retVal = '\'' . $key . '\' => ' . $retVal . ',';
		if ($indentStyle != 0) {
			my @ar = split( "\n", $retVal);
			$retVal = '';
			foreach (@ar){
				$_ =~ s/^\s+//; # Leerzeichen am Anfang entfernen
				my $c = substr( $_, -1);
				if ( $c eq '{' && substr( $_, -2) ne '{}' && substr( $_, -3) ne '{},') {
					$retVal .= $tab x $tiefe . $_ . "\n";
					$tiefe++;
				} elsif ( ( $c eq '}' || substr( $_, -2) eq '},') && substr( $_, -2) ne '{}' && substr( $_, -3) ne '{},') {
					$tiefe--;
					$retVal .= $tab x $tiefe . $_ . "\n";
				} else {
					$retVal .= $tab x $tiefe . $_ . "\n";
				}
			}
		}
		# convert strings in values  
		$retVal =~ s/(\s*=>\s*)(")(0x[0-9a-fA-F]*)(")(.*)/$1$3$5/g;						# string to hex
		$retVal =~ s/(\s*=>\s*)(")([0-9]*\.[0-9]*)(")(.*)/$1$3$5/g;						# string to float
		$retVal =~ s/(\s*=>\s*)("#)([a-zA-Z])(")(.*)/$1.sprintf('0x%02X',ord($3)).$5/ge;	# char to hex
		$retVal =~ s/(\s*=>\s*)(")(true|false)(")(.*)/$1$3$5/g;							# true / false to 1/0
		$retVal =~ s/(\s*=>\s*)("\+)([0-9]*\.{0,1}[0-9]*)(")(.*)/$1$3$5/g;					# +1 -> 1
	
	}

	return $retVal;
}

sub reMap($) {
	my ($hash) = @_;
	
	foreach my $param (keys %{$hash}) {

		if (ref($hash->{$param}) eq 'HASH') {

			if ($param eq 'type' && $hash->{$param}->{'id'}) {
				my $idField = ($hash->{$param}->{'type'}) ? 'type' : 'id';
				my $id = $hash->{$param}->{$idField};

				delete ($hash->{$param}->{$idField});

				$id =~ s/-/_/g;

				$hash->{$id} = reMap($hash->{$param});
				delete ($hash->{$param});

			} else {
				if (defined($hash->{$param}{'type'}) && ($hash->{$param}{'type'} eq 'array')) {
					#delete ($hash->{$param}{'type'});	
					$hash->{$param} = $hash->{$param}{$param};
				} else {
					$hash->{$param} = reMap($hash->{$param});
				};

			}
			
		} elsif (ref($hash->{$param}) eq 'ARRAY') {

			my $newHash;
			my $id;
			foreach my $item (@{$hash->{$param}}){
				my $idField = ($item->{'id'}) ? 'id' : 'index';
			
				if ($item->{'type'} && $param eq 'channel') {
					$idField = 'type';
				}

				if (defined($item->{$idField})) {
					$id = $item->{$idField};
					delete ($item->{$idField});
				} else {
					$id ++;
				}

				$newHash->{$id} = $item;
			}

			$hash->{$param} = reMap($newHash);
		}
		
	}

	return $hash;
}

sub fixChannelPeerAdresses($) {
	my ($hash) = @_;

	foreach my $param (keys %{$hash}) {
		# first we convert long keys into short. E.g. hmw_input_ch_link -> link
		if ($param ne 'MAINTENANCE') {
			foreach my $param2 (keys %{$hash->{$param}{'paramset'}}) {
				my @paramArray = split('_', $param2);
				my $newParam2 = pop (@paramArray);

				$hash->{$param}{'paramset'}{$newParam2} = $hash->{$param}{'paramset'}{$param2};
				delete ($hash->{$param}{'paramset'}{$param2});
			}
			
			if (defined ($hash->{$param}{'paramset'}{'link'}{'channel_param'})){
#				my $channelParam = $hash->{$param}{'paramset'}{'link'}{'channel_param'};
#				$hash->{$param}{'paramset'}{'link'}{'channel_offset'}      = $hash->{$param}{'paramset'}{'link'}{'parameter'}{$channelParam}{'physical'}{'address'}{'index'};

#				my $peerParam = $hash->{$param}{'paramset'}{'link'}{'peer_param'};
#				$hash->{$param}{'paramset'}{'link'}{'peer_address_offset'} = $hash->{$param}{'paramset'}{'link'}{'parameter'}{$peerParam}{'physical'}[0]{'address'}{'index'};
#				$hash->{$param}{'paramset'}{'link'}{'peer_address_size'}   = $hash->{$param}{'paramset'}{'link'}{'parameter'}{$peerParam}{'physical'}[0]{'size'};
#				$hash->{$param}{'paramset'}{'link'}{'peer_channel_offset'} = $hash->{$param}{'paramset'}{'link'}{'parameter'}{$peerParam}{'physical'}[1]{'address'}{'index'};
#				$hash->{$param}{'paramset'}{'link'}{'peer_channel_size'}   = $hash->{$param}{'paramset'}{'link'}{'parameter'}{$peerParam}{'physical'}[1]{'size'};
#
#				delete ($hash->{$param}{'paramset'}{'link'}{'parameter'}); 
#				delete ($hash->{$param}{'paramset'}{'link'}{'channel_param'}); 
#				delete ($hash->{$param}{'paramset'}{'link'}{'peer_param'}); 
			}
		}
	}
	
	return $hash;
}

################################################################################

main();

exit(0);

1;
