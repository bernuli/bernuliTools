package Baselines;

use strict;
use warnings;


my $verbose = 0;




sub createOutputDir {

	# Creates a directory branch.  Returns path to lowest directory as string.
	#
	# for example baselines/hwswb/2.9
	#
	# Inputs
	# 	0 outputRoot
	# 	1 .. Remaining inputs as path to outputDir.
	
	

	unless ($_[1] ) {
	
		warn "WARN: Invalid input to createOutputDir";
		
		return;
	
	}
	
	
	my $outputRoot = shift @_;
		
	my @outputDir; # path breakdown of outputDir.


	
	my @invalidPaths = grep m/[^\w\-\.]/, @_ ;

	if (@invalidPaths) {
	
		warn "WARN invalid input supplied to createOutputDir [@invalidPaths].";
	
		return;
	
	}
	
	
	unless ($outputRoot) {
	
		$outputRoot = $ENV{HOME} 						if $ENV{HOME};
		
		$outputRoot = $ENV{SYSTEMDRIVE}.$ENV{HOMEPATH}	if $ENV{SYSTEMDRIVE} && $ENV{HOMEPATH};

		$outputRoot = '.' 								unless $outputRoot;

	}


	unless ( -d $outputRoot ) {
	
		unless (mkdir $outputRoot) {
		
			warn "WARN Could not create $outputRoot.  Create [$outputRoot] and try again. $!";
			
			return;
		}
		
	}

	
	unless ( -w $outputRoot) {
	
		warn "WARN outputRoot is not writeable. [$outputRoot]";
		
		return;
			
	}

	
# /[^\w\-\.]/ 

	print "Will create dirs under $outputRoot\n" if $verbose > 5;
	
	push @outputDir, "$outputRoot/" . shift @_;
		
	for (@_) {
	
		push @outputDir, "$outputDir[$#outputDir]/$_";
	
	}
	
	
	for my $dirToCreate ( @outputDir ) {
		
		if (-d $dirToCreate) {
		
			print "Already exists [$dirToCreate]\n" if $verbose > 5;

			next;
			
		}

		if (-f $dirToCreate) {
		
			warn "WARN Plain file where directory should go. Not valid for all OSs. [$dirToCreate]";
			
			return;
		
		}
		
		print "mkdir [$dirToCreate]\n" if $verbose > 5;
		
		unless (mkdir $dirToCreate) { 
		
			warn "WARN mkdir failed on [$dirToCreate] $!";
			
			return;
			
		}
	
	}
	

	return $outputDir[$#outputDir]; 

}









sub createOutputSubDirs {

	my $outputDir = shift @_;
	
	return unless ($outputDir && -d $outputDir && -w $outputDir);
	

	my @outputSubDirs;
		
	for (@_) {
	
		my $dirToCreate = "$outputDir/$_";
		
		print "Creating $dirToCreate\n" if $verbose > 5;

		if (-d $dirToCreate) {
		
			push @outputSubDirs, $dirToCreate;
			
			next;
		
		}
					
		if (mkdir $dirToCreate) {
		
			push @outputSubDirs, $dirToCreate;

		} else {
		
			warn "WARN mkdir failed on $dirToCreate $!";

		}
	
	
	}
	
	return @outputSubDirs;

};













sub runWriteOutputV4_1 {

	# runWriteOutput( $command, \@args, \@pathList, program, ".fnx", 6 );
	#
	#	0	STRING		REQUIRED	commandName
	#	1	ARRAYREF	optional	commandArgs
	#	2	ARRAYREF	optional	pathList
	#	3	STRING		optional	outFileName (override default)
	#	4	STRING		optional	outFileExt (override default)
	#	5	STRING		optional	timeout (override default)
	#
	#
	# Run given command and write it's STDOUT and STDERR to separate files in 
	# the current working directory.
	#
	# If pathList given then search each path for executable commandName. First
	# match is the one that is executed. If no executable file found in pathList
	# then assume commandName is a builtin and run as is with no preceding path.
	#
	# If pathList is empty then assume commanName is a builtin and run as is 
	# with no preceding path.
	#
	# If file name extension given to append to stdout file.
	#
	# If timeout given, will override the default timeout for command 
	# to run.
	#
	#
	# Output is written to current directory.
	#
	# Note: The only way to get STDERR is with shell redirection within the 
	# open call. So the STDERR file name must be shell friendly. Open function
	# is required so we can timeout and kill zombie PID if timeout reached.
	#
	# Returns: 
	#	0	Program exit status. 
	#	1	The commandString.
	#	2	pid from open.
	#	3	Location of file containing STDOUT from command.
	#	4	Command timeout situation.
	
	
	
	
	#
	# Input validation:
	
	my $commandName	= $_[0];		# Required
	
	my $commandArgs	= $_[1] || [];	# Can be undef.
	
	my $pathList	= $_[2] || [];	# Can be undef.
	
	my $outFileName	= $_[3] || '';	# override default. Can be undef.

	my $outFileExt	= $_[4] || '';	# override default. Can be undef.

	my $timeout		= $_[5];		# Can be undef. Positive value required in order to run with timeout.
	
	
	if (defined $commandName) {
	
		if ($commandName =~ m/[\\\/]/ ) {
		
			warn "WARN Slashes not allowed in commandName [$commandName]";
		
			return;
		
		}
	
	} else {
	
		warn "WARN no command specified.";
		
		return;
	
	}

	
	if (defined $commandArgs && ref $commandArgs ne 'ARRAY') {
		
		warn "WARN Invalid input. commandArgs must be ARRAYREF";
		
		return;
	
	}
	
	
	if (defined $pathList && ref $pathList ne 'ARRAY') {
		
		warn "WARN Invalid input. pathList must be ARRAYREF";
		
		return;
	
	}


	if ($outFileName){
	
		if ($outFileName =~ /[^\w -\.]/) {
	
			warn "WARN Illegal character in outFileName.";
		
			return;
		}
	
	} else {
	
		$outFileName = $commandName;
	
	}
	
	
	if ($outFileExt) {

		if ($outFileExt =~ /[^\w \-\.]/) {
	
			warn "WARN Illegal character in outFileExt.";

			$outFileExt = '';

		}
		
	} else {
	
		$outFileExt = '.txt';
	
	}
	
	
	
	
	if (defined $timeout) {
		
		if ($timeout =~ m/\D/) {
		
			warn "WARN Invalid input. Only digits allowed.";
		
			return;

		}
	
	} else {
	
		$timeout = 300; # Default timeout.
	
	}
	
	
	
	
	# 
	# Define or declare variables.
	
 	# my $commandNameQuoted	= quotemeta($commandName);
	
	my @outDirs				= ("cmd-stdout", "cmd-stderr");

	my @outFiles 			= ("$outDirs[0]/$outFileName$outFileExt", "$outDirs[1]/$outFileName.txt");

	my @outTmpFiles 		= ("$outFiles[0].tmp", "$outFiles[1].tmp");

	my %searchedAlready;	# If pathList has duplicates do not -x again.

	my $FHI;				# Filehandle from command STDOUT
	
	my $openPID;			# Capture the pid returned from open function.

	my $exitStatus;			# Save exit status after closing $FHI.
	
	my $command;			# Full path to command.

	my $commandString; 		# Used in open function.
	
	my $timedOut			= ''; # If command ened up timing out set to string describing situation.
	
	my $commandStartTime;	# Timestamp from when command started.
	
	
	# 
	# Create directories for output.
	
	for my $newDir (@outDirs) {
			
		next if -d $newDir;
	
		unless (mkdir $newDir) {
		
			warn "WARN mkdir failed on [$newDir] $!";
			
			return;
			
		}

	}
	
	
	
	
	#
	# Search path list for executable.
	
	for ( @{ $pathList } ) {
		
		print "Searching for '$commandName' in $_\n" if $verbose > 3;
		
		$command = "$_/$commandName";
		
		next if $searchedAlready{$command};
		
		last if -x $command;
		
		$searchedAlready{$command} = 1;
		
		$command = '';


	}
	
	$command = $commandName unless $command;
	
	print "$command\n" if $verbose > 3;
	
	
	
	
	#
	# Make sure not overwriting any existing files before running command.
	
	for my $file (@outTmpFiles, @outFiles) {

		if (-e $file) {
		
			warn "WARN File exists. Will not overwrite [$file]";
			
	 		return;
		
		}
	
	}
	
	
	
	
	#
	# Run command and write it's output using a timeout.
	
	$commandString = "$command @{$commandArgs} 2>$outTmpFiles[1]";
	
	$commandStartTime = time;

	open ( my $FHO, ">", $outTmpFiles[0] );

	print "Running [$commandString] with timeout: $timeout " if $verbose > 2;

	eval {
	
		local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required

		alarm $timeout;
		
		# system or backticks are no good because after timeout the process may
		# continue to run.  Need to use open instead so that PID can be 
		# captured.  system( "$command @{$args} 1>/dev/null 2>x$outFiles[1]" ); 
		
		$openPID = open ( $FHI, "-|", $commandString );
		
		print "openPID $openPID\n" if $verbose > 2;
		
 		# while (<$FHI>) {}; # read but don't write.  For testing.
		
		print $FHO $_ while <$FHI>;
		
		alarm 0;

	};

	if ($@) {
	
		die unless $@ eq "alarm\n";   # Propagate unexpected errors.
	
		#
		# Timed out
		

		print "\a" . "\a" . "\a"; sleep 3;  # Notify user with bell sound.

		warn "WARN Timed out, terminating $openPID";
				
		kill 'TERM', $openPID;
		
		sleep 3; # Wait for process to terminate.
				
		close $FHI; # Need to close to get exit status from open.
	
		$exitStatus = $?;
		
		$timedOut = "Command timed out after " . (time - $commandStartTime) . " seconds.";
		
		print $FHO "\nDATA MAY BE INCOMPLETE. $timedOut\n";
				
	} else {
		
		#
		# Did not time out.
		
		close $FHI;	# Need to close to get exit status from open.
	
		$exitStatus = ($? >> 8);

	}


	close $FHO or warn "WARN Could not close filehandle FHO $!";
	
	
	
	
	#
	# Command run is done.  Rename tmp files.
	
	for my $i (0 .. $#outTmpFiles) {
	
		rename $outTmpFiles[$i], $outFiles[$i] or warn "WARN Could not rename [$outTmpFiles[$i]] ";

	}


	return $exitStatus, $commandString, $openPID, $outFiles[0], $timedOut;

}









sub timestamp_log {

	# Return a time value in the form yyyymmdd-hhmmss.

	my $timeValue = $_[0] || time;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime ($timeValue);
	
	return (
	
		($year += 1900) 		. 
		sprintf("%02d",$mon+1)	.
		sprintf("%02d",$mday)	.
		'-' 					.  
		sprintf("%02d",$hour)	. 
		sprintf("%02d",$min) 	.  
		sprintf("%02d",$sec)	

	);  

}









sub parseARGV_v1_1 {

	# Read through ARGV and return reference to hash.
	
	my %argv;
	
	my $legalArgsRef = $_[0];
	
	
	for (@ARGV) {
	
		if (/=/) {

			my ($key,$value) = split /=/,$_,2;
			
			die "Illegal argument [$key=].\nUse 'help' for manual."		unless $legalArgsRef->{"$key="};
			
			die "Arg requires value [$_].\nUse 'help' for manual."		unless $value =~ /./;		

			$argv{$key} = $value;

		} else {
		
			die "Illegal arg [$_].\nUse 'help' for manual."				unless $legalArgsRef->{$_};
				
			$argv{$_}++;
		}

	}


	return \%argv;

}




sub sendManual {

	# Send user manual to stdout.

	my $scriptGroup			= $_[0];
	my $scriptName 			= $_[1];
	my $scriptVersionString	= $_[2];
	my $manualSections		= $_[3];
	my $legalArgsRef 		= $_[4];
	
	unless (ref $manualSections eq 'HASH' && ref $legalArgsRef eq 'HASH') {
	
		warn "Illegal inputs, could not send manual.";
		
		return;
	
	}

	
	my $topSpacer = " " x ( ( (80 - length $scriptName x 2) - (length $scriptGroup)  ) / 2 );
	
	print "\n" . $scriptName . $topSpacer . $scriptGroup . $topSpacer. $scriptName . "\n\n";
	print "NAME\n    $manualSections->{NAME}\n\n";
	print "SYNOPSIS\n    $manualSections->{SYNOPSIS}\n\n";
	print "DESCRIPTION\n    $manualSections->{DESCRIPTION}\n\n";
	print "ARGUMENTS\n";
	
	
	# Find the number of characters of the longest key.
	
	my $longestKeyLength = 0;
	
	for my $key (keys %{$legalArgsRef}) {
		
		$longestKeyLength = length $key if length $key > $longestKeyLength;
	
	}
		
	
	for my $key (sort keys %{$legalArgsRef}) {
	
		my $spaces = " " x ( $longestKeyLength - length $key) ;
	
		print "    $key  $spaces$legalArgsRef->{$key}\n";
	
	}	

	print "\n";

	return;

}







1;

