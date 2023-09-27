#! /usr/bin/perl

use warnings;
use strict;

my $scriptName		= "hwswBaselines.pl";

my @scriptVersion	= (2,7,3);	# Must be 3 elements and all must be digits.

if (scalar @scriptVersion != 3 || grep m/\D/, @scriptVersion ) {

	die "Invalid scriptVersion [@scriptVersion]";

}

my $scriptVersionString = "$scriptVersion[0].$scriptVersion[1].$scriptVersion[2]";




my $description = "
DESCRIPTION

hwswBaselines.pl gathers up hardware and software info using commands already 
installed or (shell builtins) and writes each program's output to separate 
files.

";


# 
# Most of the commands executed via this script are specific to macOS.
#
# Some version history:
#	2.0.2 Added sysctl.
#	2.0.2 Changed sub outputToFile.  Now writing data directly to file handle vs collecting in variable.
#	2.0.2 Added an output file to include this script itself.
#	2.0.3 Added: ioreg -l
#	2.0.3 Added: /usr/libexec/remotectl get-property localbridge HWModel
#	2.1.0 Changed [remotectl get-property localbridge HWModel] to simply [remotectl dumpstate]
#	2.2.0 Use mkdir to create output directory instead of backticks.  Still using backticks to mkdir on parent directories.
#	2.2.0 Chdir to ENV{'HOME'} before `mkdir` to avoid potential special characters in path name.
#	2.3.0 Added variable $sleepBetween so as to easily skip sleeping.
#	2.3.0 Modified outputToFile.  Redirecting STDERR of each command to a file in errors subdirectory.
#	2.4.0 Changed output directory structure
#	2.5.0 Changes to $outputDir
#	2.5.0 Added ioreg -a
#	2.5.0 Added command line processing in parseArgs
#	2.5.0 Added -h command line option
#	2.6.0 Bit of a re write. Also now using alarm to timeout command if gets hung. 
#	2.6.0 Code cleanup. 
#	2.6.1 Code cleanup. Added uname -a as a command.
#	2.7.1 Code cleanup. Added separate @command arrays that are OS specific.
#	2.7.2 Cleaned up ending verbage.
#	2.7.2 Added tar of launchd directories for darwin.
#	2.7.3 Version bump.




##############################################################################
#### Global variables.
##

my $baseTimestamp = timestamp_log($^T);
my $outputRoot; 
my $sleepBetween = 1;  
my $notes = "None given.";
my $verbose = 1;
my @defaultPathList	= (
	'/usr/local/sbin',
	'/usr/local/bin',
	'/usr/bin',
	'/bin',
	'/usr/sbin',
	'/sbin',
	'/Applications/VMware Fusion.app/Contents/Public',
	'',
);
my $timeout = 333;
my $anonymous = 0;

##
#### Global variables.
##############################################################################



my $argsHashRef = parseARGV();  # Organize ARGV into hash.



# Process and validate ARGVs.
#

my %legalArgs;

$legalArgs{'h'} = '       (Flag)    Display help.';
$legalArgs{'a'} = '       (Flag)    Anonomyous mode. Attempt is made to exclude privacy related machine and user info in output.'; 
$legalArgs{'n'} = '       (String)  Notes added to the runlog file.'; 
$legalArgs{'r'} = '       (String)  Specify outputRoot for writing report files.  Default is home dir if defined otherwise current dir.'; 
$legalArgs{'V'} = '       (String)  Change verbose level.'; 
$legalArgs{'noSleep'} = ' (Flag)    Do not sleep between command runs.'; 

for my $name (keys %{$argsHashRef}) {

	unless ($legalArgs{$name}) {
	
		usage(\%legalArgs);

		die "ERROR: Illegal ARGV [$name].";
	
	}
	
}




if ( $argsHashRef->{'h'} ) { 

	usage(\%legalArgs);
	
	exit;
	
}


$verbose = $argsHashRef->{'V'} if defined $argsHashRef->{'V'} ; 

die "Invlaid verbose." if $verbose =~ /\D/;






$anonymous = 1 if $argsHashRef->{'a'};

$notes = $argsHashRef->{'n'} if $argsHashRef->{'n'};

$sleepBetween = 0 if $argsHashRef->{'noSleep'};

$outputRoot = $argsHashRef->{'r'} if $argsHashRef->{'r'};








print "Started $scriptName $scriptVersionString at $baseTimestamp\n" if $verbose > 0;









# 
# Create output directories and change to top level directory.

unless ($outputRoot) {

	if ( $ENV{SYSTEMDRIVE} && $ENV{HOMEPATH} ) {

		$outputRoot = "$ENV{SYSTEMDRIVE}$ENV{HOMEPATH}"; 

	}

	$outputRoot = "$ENV{'HOME'}" if $ENV{'HOME'}; 

}

$outputRoot = '.' unless $outputRoot;


unless ( -d $outputRoot ) { print "outputRoot does not exist. [$outputRoot]  Connot continute.\n"; exit;}
unless ( -w $outputRoot ) { print "outputRoot is not writeable. [$outputRoot]  Connot continute.\n"; exit;}


my @outputDirs = (

	"$outputRoot/baselines",																		# 0
	"$outputRoot/baselines/$scriptName",															# 1
	"$outputRoot/baselines/$scriptName/$scriptVersion[0].$scriptVersion[1]",						# 2
	"$outputRoot/baselines/$scriptName/$scriptVersion[0].$scriptVersion[1]/$baseTimestamp",			# 3 < - use this for outputSubDir
	"$outputRoot/baselines/$scriptName/$scriptVersion[0].$scriptVersion[1]/$baseTimestamp/runlog",	# 4
	"$outputRoot/baselines/$scriptName/$scriptVersion[0].$scriptVersion[1]/$baseTimestamp/stdout",	# 5
	"$outputRoot/baselines/$scriptName/$scriptVersion[0].$scriptVersion[1]/$baseTimestamp/stderr",	# 6

);

 
for my $path (@outputDirs) {

	unless ( -d $path ) {
		
		print "Creating directory at $path\n" if $verbose > 1; 
		
		mkdir $path or die "Could not mkdir $path $!";
	
	}

}


my $outputSubDir = $outputDirs[3];

chdir $outputSubDir or die "Could not cd to $outputSubDir\n";

print "Will save results in:\n$outputSubDir\n\n" if $verbose;








#
# Open $runlogFHO to write status to.

my $logFile = "$outputSubDir/runlog/runlog-$baseTimestamp.txt";

die "Willnot overwrite $logFile" if -e $logFile;

open (my $runlogFHO, ">", $logFile) or die "Could not open file for writing [$logFile] $!";

print $runlogFHO "Started $scriptName $scriptVersionString at $baseTimestamp\n\nNotes: $notes\n\n";
















# Define commands we will run;
#
my @commands;




if ($^O =~ /darwin/i) { # darwin commands

	my $system_profiler_detail = 'full';

	$system_profiler_detail = 'mini' if $anonymous;
	
	my @launchdDirs = (
	
		'/System/Library/LaunchAgents', 
		'/System/Library/LaunchDaemons', 
		'/Library/LaunchAgents', 
		'/Library/LaunchDaemons', 
		"$ENV{HOME}/Library/LaunchAgents",
		"$ENV{HOME}/Library/LaunchDaemons",
	);
	
	my @launchdDirsValid;
	
	foreach (@launchdDirs){
	
		push @launchdDirsValid, $_ if -d $_;
	
	}
	
	
	
	
	@commands = ( 

	# 	[ 
	# 		'',		# 1 SCALAR The name of command.
	# 		[],		# 2 ARRREF List of paths where command might be installed.
	# 		[],		# 3 ARRREF List of command args.
	# 		'',		# 4 SCALAR Alternate file extension.
	# 		'',		# 5 SCALAR Seconds to wait before timeout.	
	# 	],


		[ # 1
			'ps', 
			['/bin'],
			[ ('axu') ],
			'.txt',
			'',
		],
	
	
		[ # 2
			'uptime',
			['/usr/bin', @defaultPathList],
			[], 		
			'.txt',
			'',
		],


		[ # 3
			'top',
			['/usr/bin', @defaultPathList],
			['-l', '1'],
			'.txt',
			'',
		],


		[ # 4
			'uname',
			['/usr/bin', @defaultPathList],
			['-a'],
			'.txt',
			'',
		],


		[ # 5
			'kextstat',
			['/usr/sbin', @defaultPathList],
			[],
			'.txt',
			'',
		],


		[ # 6
			'lsof',
			['/usr/sbin', @defaultPathList],
			['-n'],
			'.txt',
			'',
		],


		[ # 7
			'lsof',
			['/usr/sbin', @defaultPathList],
			[],
			'.txt',
			'',
		],


		[ # 8
			'vm_stat',
			['/usr/bin', @defaultPathList],
			[],
			'.txt',
			'',
		],


		[ # 9
			'system_profiler',
			['/usr/zbin', @defaultPathList],
			['-detailLevel', $system_profiler_detail ],
			'.txt',	
			'',
		],


		[ # 10
			'system_profiler',
			['/usr/sbin', @defaultPathList],
			['-detailLevel', $system_profiler_detail, '-xml'],
			'.spx',
			'',
		],


		[ # 11
			'nvram',
			['/usr/sbin', @defaultPathList],
			['-x', '-x', '-p'],
			'.txt',
			'',
		],


		[ # 12
			'sysctl',
			['/usr/sbin', @defaultPathList],
			['-a'],
			'.txt',
			'',
		],


		[ # 13
			'ioreg',
			['/usr/sbin', @defaultPathList],
			['-l'],
			'.txt',
			'',
		],


		[ # 14
			'ioreg',
			['/usr/sbin', @defaultPathList],
			['-a'],
			'.txt',
			'',
		],


		[ # 15
			'remotectl',
			['/usr/libexec'],
			['dumpstate'],
			'.txt',
			'',
		],


		[ # 16
			'tar',
			['/usr/bin'],
			['-cz', @launchdDirsValid],
			'.tgz',
			'',
		],


		[ # 17
			'iostat',
			['/usr/sbin'],
			['-n', '11', '-w', '10', '-c', '6'],
			'.txt',
			'',
		],


		[ # 18
			'diskutil',
			['/usr/sbin'],
			['list'],
			'.txt',
			'',
		],
		
	);
	
	

	if (-x "/Applications/Utilities/HardwareMonitor.app/Contents/MacOS/hwmonitor") {
	
		push @commands, 

			[ # 
				'hwmonitor',
				['/Applications/Utilities/HardwareMonitor.app/Contents/MacOS'],
				[],
				'.txt',
				'',
			],

	
	}

} # darwin commands




if ($^O =~ /mswin32/i ) { # MSWin32 commands

	@commands = (

			[ # 1
			'wmic',
			[],
			['cpu', 'get'],
			'.txt',
			'',
		],

	);

} # MSWin32 commands




unless (@commands) { # Default commands.  Not Darwin or Windows.

	@commands = (		
	
		[ # 1
			'ps', 
			['/bin',  @defaultPathList],
			[ ('axu') ],
			'.txt',
			'',
		],
	
	
		[ # 2
			'uptime',
			['/usr/bin', @defaultPathList],
			[], 		
			'.txt',
			'',
		],


		[ # 3
			'uname',
			['/usr/bin', @defaultPathList],
			['-a'],
			'.txt',
			'',
		],


		[ # 4
			'lsof',
			['/usr/sbin', @defaultPathList],
			['-n'],
			'.txt',
			'',
		],


		[ # 5
			'lsof',
			['/usr/sbin', @defaultPathList],
			[],
			'.txt',
			'',
		],


		[ # 6
			'vmstat',
			['/usr/bin', @defaultPathList],
			[],
			'.txt',
			'',
		],


		[ # 7
			'sysctl',
			['/usr/sbin', @defaultPathList],
			['-a'],
			'.txt',
			'',
		],
		
	);

} # Fall back to default commands.














#
# Sleep for 5 minutes to let things stabilize before running commands.

if ($sleepBetween) {

	my $currentTime = timestamp_log(time);
 
	print STDOUT      "Sleeping for 5 minutes to let things stabilize. Started sleeping at: $currentTime\n" if $verbose > 0;

	print $runlogFHO  "Sleeping for 5 minutes to let things stabilize. Started sleeping at: $currentTime\n";

	sleep 300;

}









#
# Run each command.

print "Progress:\n";
print "Seq   Time [command] [args] Timeout PID\n";


for my $i (0 .. $#commands) {

	my $commandName			= "$commands[$i]->[0]";
	
	my $pathList			= $commands[$i][1];
	
	my $argsList			= $commands[$i][2];
		
	my $altFileExtension	= $commands[$i][3] || '';
	
	my $timeout				= $commands[$i][4] || $timeout;



	my ($lastRun) = runCommandWriteOutputV3(
	
		$i, 				# 0 
		
		$commandName, 		# 1
		
		$pathList, 			# 2
		
		$argsList, 			# 3
		
		$altFileExtension,	# 4
		 
		$timeout, 			# 5
		
	);			



	if ($sleepBetween && $i < $#commands) {

		print STDOUT     "Sleeping 30 before next command.\n" if $verbose > 1;

		print $runlogFHO "Sleeping 30 before next command.\n" if $verbose > 1;

		sleep 30;
	
	} else {
	
		sleep 3; # This sleep is required to prevent duplicate output file names.
		
	}

} # @commands loop.


print "All command output complete.\n"  if $verbose;

print "\nShould also run some commands as root:\n\nsudo lsof -n > $outputSubDir/stdout/_lsof_-n_ROOT_.txt\n\nsudo lsof > $outputSubDir/stdout/_lsof_ROOT_.txt\n\nsudo log collect --last 1d --output=$outputSubDir\n\n"  if $verbose > 0; 



print $runlogFHO  timestamp_log() . " All output complete.\n\n";
print STDOUT      "Results saved in:\n$outputSubDir\n\n" if $verbose;
print $runlogFHO  timestamp_log() . "Results saved in [$outputSubDir]\n\n";
print $runlogFHO  timestamp_log() . "$scriptName $scriptVersionString done.\n";



close $runlogFHO or die "Could not close [\$runlogFHO]. $!";



if ($^O =~ /darwin/i )	{ system("open $outputSubDir"); } 
if ($^O =~ /win32/i) 	{ system("start $outputSubDir"); } 



print "Finished $scriptName $scriptVersionString at " . timestamp_log() . "\n" if $verbose > 0;

exit;




##############################################################################
##############################################################################









sub runCommandWriteOutputV3 {

	# Run command and save output from stdout and stderr to separate file.
	
	# Timeout if command runs for too long.


	# First 2 inputs are required.
	
	unless ( scalar @_ > 1 &&
	
		$_[0] !~ /\D/ 	&&

		defined $_[1] 	) {
	
		warn "WARN Invalid inputs to subroutine. [@_]";
		
		return;

	}
	
	
	
	
	my $sequenceIndex		=	$_[0];
	my $commandName			=	$_[1];
	my $pathList			=	$_[2];	       # List of paths where command might be installed. Empty string if no path.
	my $commandArgs			=	$_[3];
	my $altFileExtension	=	$_[4]		|| '';
	my $timeout				=	$_[5]		|| 333;
	
	
	
	if ( defined $pathList && ref $pathList ne 'ARRAY') {
	
		warn "WARN Skipping $commandName. Bad input to subroutine. pathList is not an array ref. [$pathList]";
		
		return;

	}
	
	my @pathList = @{ $pathList };
	
	
	
	
	if ( defined $commandArgs && ref $commandArgs ne 'ARRAY') {
	
		warn "WARN Skipping $commandName. Bad input to subroutine. commandArgs is not an array ref. [$commandArgs]";
		
		return;

	} 
	
	my @commandArgs = @{ $commandArgs };
	
	
	
	
	if ($altFileExtension) {
	
		if ( $altFileExtension	!~ /^\../ && 
		
		$altFileExtension	!~ /[a-z][A-Z][\d]/ && 
		
		length $altFileExtension > 20 ) {
			
			warn "WARN Skipping $commandName. Bad input to subroutine. commandArgs is not an array ref. [$commandArgs]";
				
			return;
			
		}

	}
	
	if (defined $timeout && $timeout !~ m/\D/ && $timeout > 10000 ) {
	
		warn "WARN Skipping $commandName. Invalid timeout given. [$timeout]";
		
		return;
	
	}
					
			
	my $sequence = sprintf("%02d", $sequenceIndex+1);
	
	
	
	
	
	
	
	
	
	#
	# Look for executable commandName in each path listed in pathList.  If found
	# then prepend path and set command.  Otherwise we will run command with no 
	# prepended path.
	
	my $command = $commandName;
		
	for my $path ( @pathList ) {
	
		print "\tChecking $path for $commandName" if $verbose > 5;
		
		if ( -x "$path/$commandName" ) {
		
			$command = "$path/$commandName" ;
			
			print " FOUND $command.\n" if $verbose > 5;
			
			last;
		
		}
	
		print " no exe found.\n" if $verbose > 5;	
	
	}
	

	
	
	
	
	
	
	
	
	
	# Make sure output files do not already exist.

	my $crts = timestamp_log(); # $crts is Command Run Time Stamp.

	my ($crd, $crt) = $crts =~ m/(\d+)-(\d\d\d\d)/;
	
	my @outputFiles = ('',  "stdout/$sequence-$commandName-$crts.stdout$altFileExtension", "stderr/$sequence-$commandName-$crts.stderr"); 
	
	for (1 .. $#outputFiles) {
	
		die "File exits [$outputFiles[$_]]"			if -e $outputFiles[$_];
		die "File exits [$outputFiles[$_].tmp]"		if -e "$outputFiles[$_].tmp";
	
	}
	
	open (my $commFHO, ">", "$outputFiles[1].tmp") or die "Could not open file for output. $outputFiles[1]. $!";

	my $commandCallString = "$command @commandArgs 2>$outputFiles[2].tmp";

	print STDOUT     "$sequence/". scalar @commands . " $crt [$commandName] [@commandArgs] $timeout" if $verbose > 0;
	
	print $runlogFHO "Running $sequence of ". scalar @commands . " [$commandCallString] Timeout: $timeout.";

	my $pid = open (my $commFHI, "-|", $commandCallString);  # FYI, pipe open may return a PID even if cannot run the command. For example here we are redirecting STDERR from the command to a file.  This causes the open to fork a separate shell and so will get a PID from that.
		
	print STDOUT     " $pid\n" if $verbose > 0;		

	print $runlogFHO " Open PID: $pid.\n" if $verbose > 0;		
	
	print $runlogFHO "Reading from $commandName, writing to $outputFiles[1].tmp\n";
	
	
	
	
	eval {
	
		local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
	
		alarm $timeout;
	
		#$nread = sysread SOCKET, $buffer, $size;

		while ( my $data = <$commFHI> ) {  # Read data into scalar first, may help with output buffering.
		
			print $commFHO $data ;
				
		}

		alarm 0;

		print "\tEval made it, alarm reset to 0.\n" if $verbose > 2;		

	};


	if ($@) {

		die unless $@ eq "alarm\n";   # propagate unexpected errors
	
		#
		# Eval timed out.
	
		warn "WARN Command timed out.. Alarm reached ($timeout) while waiting for output from opened pipe.  Command was [$commandCallString] ? [$?] ! [$!]";

		print $runlogFHO "WARN Command timed out.. Alarm reached ($timeout) while waiting for output from opened pipe.  Command was [$commandCallString] ? [$?] ! [$!]\n";

		kill 'TERM', $pid;
		
		close $commFHI or warn "WARN Error closing commFHI pipe: $! Exit status $? from commFHI";
        
		close $commFHO or warn "WARN Could not close file handle. $!";
				  
		# die "The command timed out after alarm ($timeout).\n";
		
	}  else {
	
		#
		# Eval did not timeout.
		
		close $commFHI or warn "WARN Error closing commFHI pipe: [$commandCallString] Exit status [$?] [$!]";
        
		close $commFHO or warn "WARN Could not close file handle. $!";
		
		rename "$outputFiles[1].tmp", $outputFiles[1] or warn "WARN Could not rename $outputFiles[1] $!";

		rename "$outputFiles[2].tmp", $outputFiles[2] or warn "WARN Could not rename $outputFiles[2] $!";

	}

	
	return;
	
} # runCommandWriteOutputV3




sub timestamp_log {

	# Return a time value in the form yyyymmdd-hhmmss.

	my $timeValue = $_[0] || time;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime ($timeValue);
	
	return (
	
		($year += 1900) . 
		sprintf("%02d",$mon+1) .
		sprintf("%02d",$mday) .
		'-' .  
		sprintf("%02d",$hour) . 
		sprintf("%02d",$min) .  
		sprintf("%02d",$sec)

	);  

}




sub parseARGV {

	# Parse arguments specified at runtime and store in hash.  Return reference
	# to hash.

	my %args; 
	
	my $currentArgName;
	
	my $verbose = $verbose;
	
	
	for my $i (0 .. $#ARGV) {
	
		print "Checking ARGV index $i: $ARGV[$i]\n" if $verbose > 5;
		
		
		if ( $ARGV[$i] =~ m/^-+(.+)/ ) {

			$currentArgName = $1;
	
		
			# If next ARGV starts with a - then this is a flag (no string 
			# value). So increment the flag value by 1.
			
			if ($i == $#ARGV || $ARGV[$i+1] && $ARGV[$i+1] =~ m/^-/ ) {
			
				$args{$currentArgName} ++;
			
			}

			next;
		
		} else {

			$args{$currentArgName} .= " " if $args{$currentArgName};
			
			$args{$currentArgName} .= "$ARGV[$i]";
			
		}
	
	}

	return \%args;

}




sub usage {

	print "$description USAGE\n";
	
	for my $name (sort keys %{$_[0]}) {
	
		print "\t-$name $_[0]->{$name}\n";
	
	}

}