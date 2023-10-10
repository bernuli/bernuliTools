#! /usr/bin/perl

use warnings;
use strict;

my $scriptGroup		= 'baselines';

my $scriptName		= "hwswBaselines.pl";

my @scriptVersion	= (2,8,1);	# Must be 3 elements and all must be digits.


if (
	$scriptGroup 	=~ /[^\w\-\.]/ || 
	$scriptName 	=~ /[^\w\-\.]/ ||
	scalar @scriptVersion != 3  || 
	grep m/\D/, @scriptVersion 
	
) { die "Invalid script version name or group" }


my $scriptVersionString = "$scriptVersion[0].$scriptVersion[1].$scriptVersion[2]";




my %manualSections = (

'NAME', 
    "$scriptName -- Gather machine HW and SW info.",

'SYNOPSIS',
    "$scriptName [argument list] Space separated argument list.",

'DESCRIPTION',
    "Gathers up hardware and software info using commands already installed 
    or shell builtins and writes each commands's output to separate files. 
    STDOUT and STDERR from the command are both saved in separate directories.",

);




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
#	2.7.4 Rewrote runWriteOutputV4_1 and moved to module.
#	2.8.0 Moved some other things to modules. Rewrote parseARGV now v1_1.
#	2.8.1 Code cleanup.







#
# Prepend our  dir to INC.  Copied from exiftool by P. Harvey
 
BEGIN { unshift @INC, ($0 =~ /(.*)[\\\/]/) ? "$1/" : './'; }

use Baselines;




##############################################################################
#### Global variables.
##

my $baseTimestamp = Baselines::timestamp_log($^T);
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
);
my @envPathList;
my $timeout = 300;
my $anonymous = 0;

##
#### Global variables.
##############################################################################





# Process and validate ARGVs.
#

my %legalArgs;

$legalArgs{'help'} 			= 'Display help.';
$legalArgs{'verbose='} 		= 'Change verbose level.'; 

$legalArgs{'anonymous'} 	= 'Attempt is made to exclude privacy related info.'; 
$legalArgs{'noSleep'} 		= 'Do not sleep between command runs.'; 
$legalArgs{'notes='} 		= 'Notes added to the runlog file.'; 
$legalArgs{'outputRoot='}	= 'Specify outputRoot for writing report files.'; 

my $argsHashRef = Baselines::parseARGV_v1_1(\%legalArgs);  # Organize ARGV into hash.







if ( defined $argsHashRef->{'help'} ) { 

	Baselines::sendManual($scriptGroup, $scriptName, $scriptVersionString, \%manualSections, \%legalArgs);
	
	exit;
	
}


$verbose = $argsHashRef->{'verbose'} if defined $argsHashRef->{'verbose'} ; 

die "Invalid verbose. [$verbose]\nUse 'help' for manual." if $verbose =~ /\D/;




$anonymous = 1 if $argsHashRef->{'anon'};

$notes = $argsHashRef->{'notes'} if $argsHashRef->{'notes'};

$sleepBetween = 0 if defined $argsHashRef->{'noSleep'};

$outputRoot = $argsHashRef->{'outputRoot'} if $argsHashRef->{'outputRoot'};




print "Started $scriptName $scriptVersionString at $baseTimestamp\n" if $verbose > 0;




if ( $ENV{'PATH'} ) {

	if ($^O eq 'MSWin32' ) {
	
		for (split /\;/, $ENV{'PATH'}) {
				
			push @envPathList, $_;	
		
		}

	} else {

		for (split /\:/, $ENV{'PATH'}) {
				
			push @envPathList, $_;	
		
		}
	}
}








# 
# Create or verify top level output directory. I.E.
# /Users/home/mike/baselines/hwswbl.pl/7.7/20230102-000204

my $outputDir = Baselines::createOutputDir(

	$outputRoot, 
	$scriptGroup, 
	$scriptName, 
	"$scriptVersion[0].$scriptVersion[1]", 
	$baseTimestamp 

);

unless ($outputDir && -d $outputDir && -w $outputDir) {

	die "Problem creating outputDir. Cannot continue.";

}



#
# Create or verify output sub directories.

my @outputSubDirs = Baselines::createOutputSubDirs(

	$outputDir,
	qw(
		log
		cmdSDTOUT
		cmdSTDERR
	)
	
);

die "Could not make or verify all outputSubDirs. [@outputSubDirs]." unless scalar @outputSubDirs eq 3;




print "Will save results in:\n$outputDir\n\n" if $verbose;




#
# Open $runlogFHO used for run status info.

my $logFile = "$outputDir/log/runlog-$baseTimestamp.txt";

die "Willnot overwrite $logFile" if -e $logFile;

open (my $runlogFHO, ">", $logFile) or die "Could not open file for writing [$logFile] $!";

print $runlogFHO "Started $scriptName $scriptVersionString at $baseTimestamp\n\nNotes: $notes\n\n";















#
# Define commands we will run;

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
	
	# sub runWriteOutputV4_1 {

	# runWriteOutput( $command, \@args, \@pathList, 6, ".fnx" );
	# runWriteOutput( $command, undef, undef, undef, "fnen" );
	#
	#	0	STRING		REQUIRED	commandName
	#	1	ARRAYREF	optional	commandArgs
	#	2	ARRAYREF	optional	pathList
	#	3	STRING		optional	outFileName (override default)
	#	4	STRING		optional	outFileExt (override default)
	#	5	STRING		optional	timeout (override default)
	#

	# 	[ 
	# 		'',		# 0 SCALAR The name of command.
	# 		[],		# 1 ARRREF List of paths where command might be installed.
	# 		[],		# 2 ARRREF List of command args.
	# 		'',		# 3 SCALAR Alternate file name.
	# 		'',		# 4 SCALAR Alternate file extension.
	# 		'',		# 5 SCALAR Seconds to wait before timeout.	
	# 	],


		[ # 1
			'ps', 
			['-A', '-o', "'pid ppid pgid tty uid user %cpu %mem vsz rss acflag lstart etime time flags inblk jobc majflt minflt msgrcv msgsnd nice nivcsw nsigs nswap nvcsw sl state tpgid ucomm xstat command'"],
			[ '/bin', @defaultPathList, @envPathList ],
			undef,
			'.txt'
			
		],

	
		[ # 2
			'vm_stat',
			[],
			['/usr/bin', @defaultPathList, @envPathList],
		],

	
		[ # 3
			'uptime',
			[],
			['/usr/bin', @defaultPathList, @envPathList ],
		],


		[ # 4
			'top',
			['-u', '-s', '15', '-l', '4' ],
			['/usr/bin', @defaultPathList, @envPathList],
		],


		[ # 5
			'uname',
			['-a'],
			['/usr/bin', @defaultPathList, @envPathList],
		],


		[ # 6
			'kextstat',
			[],
			['/usr/sbin', @defaultPathList, @envPathList],
		],


		[ # 7
			'lsof',
			['-n'],
			['/usr/sbin', @defaultPathList, @envPathList],
			'lsof_-n'
		],


		[ # 8
			'lsof',
			[],
			['/usr/sbin', @defaultPathList, @envPathList],
		],


		[ # 9
			'system_profiler',
			['-detailLevel', $system_profiler_detail ],
			['/usr/zbin', @defaultPathList, @envPathList],
		],


		[ # 10
			'system_profiler',
			['-detailLevel', $system_profiler_detail, '-xml'],
			['/usr/sbin', @defaultPathList, @envPathList],
			undef,
			'.spx'
		],


		[ # 11
			'nvram',
			['-x', '-x', '-p'],
			['/usr/sbin', @defaultPathList, @envPathList],
		],


		[ # 12
			'sysctl',
			['-a'],
			['/usr/sbin', @defaultPathList, @envPathList],
		],


		[ # 13
			'ioreg',
			['-l'],
			['/usr/sbin', @defaultPathList, @envPathList],
		],


		[ # 14
			'ioreg',
			['-a'],
			['/usr/sbin', @defaultPathList, @envPathList],
			'ioreg_-a',
			'.xml'
		],


		[ # 15
			'remotectl',
			['dumpstate'],
			['/usr/libexec', @defaultPathList, @envPathList],
		],


		[ # 16
			'tar',
			['-cz', @launchdDirsValid],
			['/usr/bin', @defaultPathList, @envPathList],
			undef,
			'.tgz'
		],


		[ # 17
			'iostat',
			['-n', '11', '-w', '10', '-c', '6'],
			['/usr/sbin', @defaultPathList, @envPathList],
		],


		[ # 18
			'diskutil',
			['list'],
			['/usr/sbin', @defaultPathList, @envPathList],
		],


		[ # 18
			'dirs',
			[],
			['/usr/sbin', @defaultPathList, @envPathList],
		],
		
	);
	
	

	if (-x "/Applications/Utilities/HardwareMonitor.app/Contents/MacOS/hwmonitor") {
	
		push @commands, 

			[ # 
				'hwmonitor',
				[],
				['/Applications/Utilities/HardwareMonitor.app/Contents/MacOS'],
			],

	
	}

} # darwin commands




if ($^O =~ /mswin32/i ) { # MSWin32 commands

	@commands = (

		[ # 1
			'WMIC.exe',
			['cpu', 'get'],
			[@envPathList]

		],

	);

} # MSWin32 commands




# unless (@commands) { # Default commands.  Not Darwin or Windows.
# 
# 	@commands = (		
# 	
# 		[ # 1
# 			'ps', 
# 			[ 'axu' ],
# 			['/bin',  @defaultPathList],
# 			'.txt'
# 		],
# 	
# 	
# # 		[ # 2
# # 			'uptime',
# # 			[], 		
# # 			['/usr/bin', @defaultPathList],
# # 			'.txt'
# # 		],
# # 
# # 
# # 		[ # 3
# # 			'uname',
# # 			['-a'],
# # 			['/usr/bin', @defaultPathList],
# # 			'.txt'
# # 		],
# # 
# # 
# # 		[ # 4
# # 			'lsof',
# # 			['-n'],
# # 			['/usr/sbin', @defaultPathList],
# # 			'.txt'
# # 		],
# # 
# # 
# # 		[ # 5
# # 			'lsof',
# # 			[],
# # 			['/usr/sbin', @defaultPathList],
# # 			'.txt'
# # 		],
# # 
# # 
# # 		[ # 6
# # 			'vmstat',
# # 			[],
# # 			['/usr/bin', @defaultPathList],
# # 			'.txt'
# # 		],
# # 
# # 
# # 		[ # 7
# # 			'sysctl',
# # 			['-a'],
# # 			['/usr/sbin', @defaultPathList],
# # 			'.txt'
# # 		],
# 		
# 	);

# } # Fall back to default commands.














#
# Sleep for 5 minutes to let things stabilize before running commands.

if ($sleepBetween) {

	my $currentTime = Baselines::timestamp_log(time);
 
	print STDOUT      "Sleeping for 5 minutes to let things stabilize. Started sleeping at: $currentTime\n" if $verbose > 0;

	print $runlogFHO  "Sleeping for 5 minutes to let things stabilize. Started sleeping at: $currentTime\n";

	sleep 300;

}









#
# Run each command.
#
# Chdir to outputDir as we will be hitting the shell to redirect STDERR 
# from open funcion.

print "chdir to $outputDir\n" if $verbose > 0;

chdir $outputDir || die "Could not chdir to $outputDir $!";

print "Progress:\n";

print "Seq    Time            [Command Args] Timeout PID\n";


for my $i (0 .. $#commands) {

	my $commandName		= "$commands[$i]->[0]";
	
	my $commandArgs		= $commands[$i][1];

	my $pathList		= $commands[$i][2];

	my $fileName		= $commands[$i][3] || $commandName;
	
	   $fileName 		= sprintf("%02d",$i+1) . "-$fileName-" . Baselines::timestamp_log() if $fileName;

	my $fileExt			= $commands[$i][4] || '';

	my $timeout			= $commands[$i][5] || $timeout;
	

	print sprintf("%02d",$i+1) . "/" . scalar @commands . "  " . Baselines::timestamp_log() . " [$commandName @{$commandArgs}] $timeout " ;

	print $runlogFHO  Baselines::timestamp_log() . " Running $commandName @{$commandArgs}";


	my @returns = Baselines::runWriteOutputV4_1(
	
		$commandName,	# 0

		$commandArgs,	# 1

		$pathList,		# 2
		
		$fileName,		# 3

		$fileExt,		# 4

		$timeout,		# 5

	);
	
	print "$returns[2] \$?=$returns[0] $returns[4]\n";

	print $runlogFHO " [$returns[1]] \$?=$returns[0] $returns[4]\n";


		



	if ($sleepBetween && $i < $#commands) {

		print STDOUT     "Sleeping 30 before next command.\n" if $verbose > 1;

		print $runlogFHO "Sleeping 30 before next command.\n" if $verbose > 1;

		sleep 30;
	
	} else {
	
		#sleep 3; # This sleep is required to prevent duplicate output file names.
		
	}

} # @commands loop.


print "All command output complete.\n"  if $verbose;

print "\nShould also run some commands as root:\n\nsudo lsof -n > $outputDir/stdout/_lsof_-n_ROOT_.txt\n\nsudo lsof > $outputDir/stdout/_lsof_ROOT_.txt\n\nsudo log collect --last 1d --output=$outputDir\n\n"  if $verbose > 0; 



print $runlogFHO	Baselines::timestamp_log() . " All command output complete.\n";
print 				"Results saved in:\n$outputDir\n\n" if $verbose;
print $runlogFHO	Baselines::timestamp_log() . " Results saved in [$outputDir]\n";
print $runlogFHO	Baselines::timestamp_log() . " $scriptName $scriptVersionString done.\n";



close $runlogFHO or die "Could not close [\$runlogFHO]. $!";



# if ($^O =~ /darwin/i )	{ system("open $outputDir"); } 
# if ($^O =~ /win32/i) 		{ system("start $outputDir"); } 



print "Finished $scriptName $scriptVersionString at " . Baselines::timestamp_log() . "\n" if $verbose > 0;

exit;




##############################################################################
##############################################################################





