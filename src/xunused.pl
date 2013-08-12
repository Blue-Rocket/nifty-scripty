#!/usr/bin/perl -w
#
# Search for unused resource files within a source code project.
# 
# The general idea is that some project resources like image files
# may no longer actually be used in a project. To determine if a
# resource is unused, this script looks for refereneces to each
# resource's file name within a set of "source" files, for example
# C or HTML files. If a resource's file name can't be found, it
# is assumed to be unused and a candidate for deleting.
# 
# This script will also report if it finds duplicate resources,
# based on file name. Duplicate resources can indicate one or more
# resources can be deleted.
# 
# This script was written on OS X with Xcode projects in mind,
# but might be useful for other source projects as well.
# 
# Copyright (c) 2013 Blue Rocket. Distributable under the terms of
# the Apache License, Version 2.0.


package xunused;

use strict;

use Getopt::Long;
use File::Find;
use Cwd 'abs_path';
use File::Spec;
use IO::File;

my $VERSION = do { q$Revision: 6419 $ =~ m/(\d+)/; $1; };
my $AUTHOR = 'Matt Magoffin (matt@bluerocket.us)';
my $DATE = do { q$Date: 2011-05-27 11:14:32 +1200 (Fri, 27 May 2011) $ =~ m/^Date: (.*)\s+$/; $1; };

sub new {
	my $that = shift;
	my %params = @_;
	my $this = {
		rsrc		=> $params{'rsrc'},
		source		=> $params{'source'},
		mod			=> $params{'mod'},
		ignore		=> {},
		verbose		=> $params{'verbose'},
		rm			=> $params{'rm'},
		rmcmd		=> $params{'rmcmd'},
		
		rexp		=> join('|', @{$params{'rsrc'}}),
		sexp		=> join('|', @{$params{'source'}}),
		mexp		=> join('|', @{$params{'mod'}}),
		ss			=> [],
		nf			=> {},
		nfe			=> {},
		dup			=> {},
		wasted		=> 0,
	};
	
	for my $ignore (@{$params{'ignore'}}) {
		$this->{'ignore'}->{$ignore} = 1;
	}
	
	$this->{'svnescape'} = '';
	if ( $this->{'rmcmd'} =~ m/^svn/ ) {
		# for SVN to handle @ in a filename, we have to make sure an @ is appended to end of name
		$this->{'svnescape'} = '@';
	}
	
	my $class = ref($that) || $that;
	bless $this, $class;
	
	return $this;
}

sub go {
	my ($this, $dir) = @_;
	print "Searching directory '$dir' ...\n";
	
	my $baseDir = abs_path();
	
	# collect list of source file absolute paths to search through
	
	find(sub {
		if ( $this->{'ignore'}->{$_} ) {
			$File::Find::prune = 1;
			return;
		}
		return unless m/\.($this->{'sexp'})$/;
		push(@{$this->{'ss'}}, File::Spec->canonpath(
			File::Spec->catfile($baseDir, $File::Find::name)));
	}, $dir);
	
	print "\n", '=' x 79, "\nGot source files:\n\n", 
		map {$_."\n"} @{$this->{'ss'}}, "\n" if $this->{'verbose'};
	
	my %examined = ();
	my %unused = ();
	
	# iterate over every resource now, and try to find a reference to that
	# file name in any source file collected
	
	find(sub {
		if ( $this->{'ignore'}->{$_} ) {
			$File::Find::prune = 1;
			return;
		}
		return unless m/\.($this->{'rexp'})$/;
		my $absPath = File::Spec->canonpath(
			File::Spec->catfile($baseDir, $File::Find::name));
		my $resourceName = $_;
		
		# remove file modifiers from resource name, with assumption that
		# code refers to un-modified names only
		$resourceName =~ s/($this->{'mexp'})\././;
		
		my $dup = $examined{$resourceName};
		if ( $dup ) {
			print "Skipping duplicate resource $_\n" if $this->{'verbose'};
			$this->{'dup'}->{$resourceName}->{$absPath} = 1;
			$this->{'dup'}->{$resourceName}->{$examined{$resourceName}} = 1;
			if ( exists $unused{$resourceName} ) {
				# we need to set this here, so unfound duplicate resources deleted
				$this->{'nf'}->{$File::Find::name} = 1;
			}
			return;
		}
		$examined{$resourceName} = $absPath;
		
		# also remove file extension, and look for that, with assumption that
		# some resources loaded by name and extension coded separately
		my $resourceKey = $resourceName;
		$resourceKey =~ s/(.*)\..*/$1/;
		my $foundKey = '';
		
		print "Examining resource $resourceName ($resourceKey)\n" if $this->{'verbose'};
		foreach my $s (@{$this->{'ss'}}) {
			# don't search self
			next if $absPath eq $s;
			
			my $in = new IO::File($s, 'r');
			if ( !defined $in ) {
				print "Error opening file $s\n";
				die;
			}
			while (<$in>) {
				if ( m/$resourceName/ ) {
					print "Found resource ", $File::Find::name,
						" referenced by ", $s, "\n" if $this->{'verbose'};
					return;
				} elsif ( m/$resourceKey/ ) {
					$foundKey = $s;
					last;
				}
			}
			last if ( length $foundKey > 0 );
		}

		$this->{(length $foundKey > 0 ? 'nfe' : 'nf')}->{$File::Find::name} = 1;
		if ( length $foundKey > 0 ) {
			print "Found resource key ", $File::Find::name,
				" referenced by ", $foundKey, "\n" if $this->{'verbose'};
		} else {
			$unused{$resourceName} = 1;
			my $size = -s $resourceName;
			$this->{'wasted'} += $size if $size;

			if ( $this->{'rm'} && $this->{'rmcmd'} ) {
				system "$this->{'rmcmd'} \"$absPath".$this->{'svnescape'}."\"" 
					|| die "Error executing --delete-cmd";
			}
		}
		
	}, $dir);
}

# spit out result info
sub status {
	my ($this, $dir) = @_;
	my $baseDir = abs_path();
	if ( scalar(%{$this->{'dup'}}) || scalar(%{$this->{'nf'}}) || scalar(%{$this->{'nfe'}}) ) {
		print "\n", '=' x 79, "\n";
		if ( scalar(%{$this->{'dup'}}) ) {
			print "The following ", scalar(keys %{$this->{'dup'}}), 
				" resources were found more than once:\n";
			foreach my $key (keys(%{$this->{'dup'}})) {
				print "\n", $key, ":\n";
				foreach my $dup (keys(%{$this->{'dup'}->{$key}})) {
					print "  ", File::Spec->abs2rel($dup, $baseDir), "\n";
				}
			}
		}
		if ( scalar(%{$this->{'nfe'}}) ) {
			if ( scalar(%{$this->{'dup'}}) ) {
				print "\n", '=' x 79, "\n";
			}
			print "The following ", scalar(keys %{$this->{'nfe'}}),
				" resources were not referenced exactly, but matched ignoring\n",
				"their file extensions. These are thus NOT considered unused:\n\n",
				map {$_."\n"} keys %{$this->{'nfe'}}, "\n";
		}
		if ( scalar(%{$this->{'nf'}}) ) {
			if ( scalar(%{$this->{'dup'}}) || scalar(%{$this->{'nfe'}}) ) {
				print "\n", '=' x 79, "\n";
			}
			print "The following ", scalar(keys %{$this->{'nf'}}), " resources were not referenced:\n\n",
				map {$_."\n"} keys %{$this->{'nf'}}, "\n";
		}
		printf "Total wasted space: %.2f Kb\n", $this->{'wasted'} / 1024 if $this->{'wasted'};
	}
	
}

# ----------------------------------------------------------------------------

my @DEFAULT_SOURCE = qw/h c m xib html plist/;
my @DEFAULT_RSRC = qw/jpg png/;
my @DEFAULT_MOD = qw/@2x/;
my @DEFAULT_IGNORE = qw/themes Animation/;
my $DEFAULT_RMCMD = 'svn rm';
my ($HELP, $VERBOSE, @RSRC, @SOURCE, @MOD, @IGNORE, $RM, $RMCMD);

GetOptions( 
			'help' 			=> \$HELP,
			'rsrc=s'		=> \@RSRC,
			'src=s'			=> \@SOURCE,
			'mod=s'			=> \@MOD,
			'ignore=s'		=> \@IGNORE,
			'delete'		=> \$RM,
			'delete-cmd'	=> \$RMCMD,
			'verbose'		=> \$VERBOSE,
			);

if ( $HELP or not scalar(@ARGV) ) {
	print <<HELP;
$0 
    [options]
    <directory>
    
Typical usage pattern is to run the script like

$0 . >output.txt

or

$0 --verbose . |tee output.txt

Then, after examining the output, run

$0 --delete

to delete the found resources from version control.

--rsrc:        comma-delimited list of resource file extensions
               defaults to (png, jpg)
--src:         comma-delimited list of source file extensions
               defaults to (h c m xib html)
--mod:         comma-delimited list of file modifiers
               defaults to (\@2x)
--ignore:      comma-delimited list of directories to ignore
               defaults to (themes, Animation)
--delete:	   if set, also execute a version control delete on unused files
--delete-cmd:  the command to use to delete, defaults to "svn rm"
--verbose:     print out verbose details
--help:        print this help out

Version $VERSION, by $AUTHOR. Updated $DATE.
HELP
	$HELP = 1;
}

if ( $HELP ) {
	exit 0;
}

@SOURCE = @DEFAULT_SOURCE unless scalar(@SOURCE);
@SOURCE = split(',', join(',', @SOURCE));
@RSRC = @DEFAULT_RSRC unless scalar(@RSRC);
@RSRC = split(',', join(',', @RSRC));
@MOD = @DEFAULT_MOD unless scalar(@MOD);
@MOD = split(',', join(',', @MOD));
@IGNORE = @DEFAULT_IGNORE unless scalar(@IGNORE);
@IGNORE = split(',', join(',', @IGNORE));
$RMCMD = $DEFAULT_RMCMD unless $RMCMD;

print "Source files: ", join(', ', @SOURCE), "\n" if $VERBOSE;
print "Resource files: ", join(', ', @RSRC), "\n" if $VERBOSE;
print "Modification suffixes: ", join(', ', @MOD), "\n" if $VERBOSE;
print "Ignore: ", join(', ', @IGNORE), "\n" if $VERBOSE;

my $cmd = new xunused( 
	rsrc 		=> \@RSRC, 
	source		=> \@SOURCE, 
	mod			=> \@MOD,
	ignore		=> \@IGNORE,
	rm			=> $RM,
	rmcmd		=> $RMCMD,
	verbose 	=> $VERBOSE,
);
if ( !$cmd ) {
	exit 1;
}

foreach my $dir (@ARGV) {
	$cmd->go($dir);
	$cmd->status();
}
