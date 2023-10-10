#!/usr/bin/perl5.18

use warnings;
use strict;

my $scriptGroup		= 'baselines';

my $scriptName		= "psb.pl";

my @scriptVersion	= (0,2,3);	# Must be 3 elements and all must be digits.


if (
	$scriptGroup 	=~ /[^\w\-\.]/ || 
	$scriptName 	=~ /[^\w\-\.]/ ||
	scalar @scriptVersion != 3  || 
	grep m/\D/, @scriptVersion 
	
) { die "Invalid script version name or group" }


my $scriptVersionString = "$scriptVersion[0].$scriptVersion[1].$scriptVersion[2]";




my %manualSections = (

'NAME', 
    "$scriptName -- Perl Simple Benchmark. Evalutate a CPUs parallel processing ability.",

'SYNOPSIS',
    "$scriptName [argument list] Space separated argument list.",

'DESCRIPTION',
    "Attempts to measure a system's multi tasking, aka
multi core performance.  The base benchmark is an empty foreach loop that
iterates from 1 to 1000000000, known as the INNERLOOP.  The INNERLOOP looks 
like this: foreach (1 .. 1000000000 ) {}

The OUTERLOOP controls execution of the INNERLOOP.  On the first pass of
the OUTERLOOP, a single instance of the INNERLOOP is forked, and timed.
On the second pass of the OUTERLOOP, 2 instances of the INNERLOOP are
forked and run in parallel as separate processes.  For each subsequent
pass of the OUTERLOOP, another instance of the INNERLOOP is added and the 
elapsed time to complete all inner loops in parallel is measured.

The default number of OUTERLOOP passes is 8. If running with defaults, 8 passes
will be run, and on the 8th pass there would be 8 separate processes running 
the INNERLOOP in parallel.

You can set the number of OUTERLOOP passes with the -p flag.  For
example, if you wanted to benchmark running 11 separate processes, run
the script with -p 11.  psb will then start with a single process but
continue until 11 processes are run in parallel.

While the benchmark is running, loop statistics for each pass are sent
to the terminal.

Upon completion of all OUTERLOOP passes, benchmark results are output in
CSV format to both the terminal as well written to a file.  Included in
the benchmark results is various hardware and software config info.

In addition to the CSV file, system info is gathered and output as
separate files written to the machineInfo subdirectory.",

);











my $description = "
psb.pl perlSimpleBenchmark



";


#
#  Version History
#
#  0.0.1  Switched to old style file handles for backwards compatibility.
#  0.0.2  Fixed incorrect escaping of CSV fields.  If field has a comma then enclose field in double quotes and escape existing double quotes with a double quote.
#  0.0.3  Minor bug fixes.
#  0.0.4  Moved benchmark engine to a subroutine.  perlSimpleBenchmarkEngine_0_3_0.
#  0.0.5  Cleaned up status output to STDOUT.
#  0.0.5  Rewrote parseArgs subroutine.
#  0.0.5  Added command line option -a.
#  0.0.5  Updated CSV output, accounting for win mac or unix.
#  0.0.5  Build a separate array for each row of output.
#  0.0.5  Added more sys info for Windows machines.
#  0.0.5  Added command line option -n.
#  0.0.5  Write out a copy of sysctl -a for each run to the sub directory sysctls.
#  0.0.6  Added 1 column (result type) and 2 rows (ips/1000000 and ips delta)
#  0.1.0  Added delta times to STDOUT (outputPassTotals).
#  0.1.0  Added delta percent to STDOUT (outputPassTotals).
#  0.1.0  Seems like could be release.
#  0.1.1  Changed added sub returnPassTotals to return value instead of direct printing.  outputPassTotals may no longer be needed.
#  0.1.2  Added subroutines passDataUpdate and passDataReport.   
#  0.1.3  renamed @header array to fieldNames and reworked building of the array.  
#  0.1.4  Added new CSV column "User Name" after "Computer Name" column.  
#  0.1.5  Code cleanup.
#  0.1.6  Code cleanup.
#  0.2.0  Rewrote command output capture in runCommandGetOutputV3
#  0.2.1  Verbage fixes
#  0.2.2  Bug fixes.  466 =~ instead of eq.  Timeout definition and validation in runCommandGetOutputV3
#  0.2.3  Code clean up. Moved argument parsing to Baseleines.pm




#
# Prepend our  dir to INC.  Copied from exiftool by P. Harvey
 
BEGIN { unshift @INC, ($0 =~ /(.*)[\\\/]/) ? "$1/" : './'; }

use Baselines;




#
# Need to use a module for more accurate loop timing.

use Time::HiRes qw(gettimeofday);




##############################################################################
#### Global variables.
##

my $anonymous = 0;		# Flag used to omit machine name and Serial Number from CSV output.

my $notes = '';			# Run notes will go to Notes column of csv output.

my	@passTimes;			# Array of array.  For each pass store the number of forks and time to complete all forks.

	$passTimes[0] =  ["0","0"];


my	@passData;			# Array of array.  Store report data for each pass

	$passData[0]  =  ["0","0"];
	

my $hostname = "unknownHostname";	# Will become actual machine's hostname unless -a is specified.

my $username = "unknownUsername";	# Will become username -a is specified.

my $numberOfPasses = 8;		# Default. Can be overridden with -p flag.

my $maxPasses = 128;		# Limit number passes user can specify so we don't run out of columns in CSV output.

my $numberofInnerLoops = 1000000000;

my $testRun = 0;			# Flag to shorten benchmark execution time.

my $outputRoot;

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

my $winDir = $ENV{WINDIR} || 'C:/Windows';



my $verbose = 1; 

##
#### Global variables.
##############################################################################








#
# Process and validate ARGVs.


my %legalArgs;

$legalArgs{'help'}			= 'Display help.';
$legalArgs{'anonymous'}		= 'Attempt is made to exclude privacy related info.'; 
$legalArgs{'notes='}		= 'Notes added to the notes column in CSV output.'; 
$legalArgs{'outputRoot='}	= 'Specify outDir for writing report files.'; 
$legalArgs{'passes='}		= 'Number of passes to perform.';
$legalArgs{'testing'}		= 'Use shorter innerloop for testing.'; 

my $argsHashRef = Baselines::parseARGV_v1_1(\%legalArgs);  # Organize ARGV into hash.





if ( $argsHashRef->{'help'} ) { 

	Baselines::sendManual($scriptGroup, $scriptName, $scriptVersionString, \%manualSections, \%legalArgs);
	
	exit;
	
}


$anonymous = 1 if $argsHashRef->{'anonymous'};

$notes = $argsHashRef->{'notes'} if $argsHashRef->{'notes'};

$numberOfPasses = $argsHashRef->{'passes'} if $argsHashRef->{'passes'};

die "Illegal value [$numberOfPasses]" if $numberOfPasses =~ /\D/;

die "Too many passes. Must be less than $maxPasses. [$numberOfPasses]" unless $numberOfPasses <= $maxPasses;

if ( $argsHashRef->{'testing'} ) {

	$testRun = 1;
	
	$numberofInnerLoops = 1000;

}

$outputRoot = $argsHashRef->{'outputRoot'} if $argsHashRef->{'outputRoot'};








#
#	Prompt user if not running perl 5.18
#	Since perl versions vary in empty foreach loop performance, lets try
#	to stick with perl 5.18.

unless ($^V =~ /^v5.18/) {

	print "Perl v5.18.xx is requested for benchmark consistency.\n";
	print "Please run with /usr/bin/perl5.18\n";
	print "Continue with perl $]? [y/n] (n):";

	my $response = (<STDIN>);

	chomp $response;

	$response = lc($response);
	
	unless ($response eq "y" || $response eq "yes") { print "Exiting.\n"; exit;}

}









#
# Print some environment to screen before running benchmark.

print "Script Name     : $scriptName\n";
print "Script Version  : $scriptVersionString\n";
print "Perl Version ^V : $^V\n";
print "Perl Version  ] : $]\n";
print "benchmarkEngine : " . perlSimpleBenchmarkEngine_0_4_1() . "\n";
print "Passes          : $numberOfPasses\n";
print "Innerloops      : $numberofInnerLoops\n";





chomp (my $beginningUptime = runCommandGetOutputV3('uptime', [], ['/usr/bin', @defaultPathList] )->[0] || "NA"); 

###############################################################################
#	Run the benchmark.

my $benchmarkEngineVersion = perlSimpleBenchmarkEngine_0_4_1();

unless ($testRun) {

	print "Sleeping 5 seconds before starting $benchmarkEngineVersion with $numberOfPasses pass(es).\n"; 
	
	sleep 5;

}


#
# Start with 1 fork and increase by 1 fork on each pass.

for my $i (1 .. $numberOfPasses) {  # Start of OUTERLOOP.

	# print "\nSleeping 3 seconds before starting benchmark pass.\n";  sleep 3;

	print "\nStarting pass $i of $numberOfPasses. Forking $i processe(s).\n";

	my ($forks, $forkedTime) = perlSimpleBenchmarkEngine_0_4_1($i);

	push @passTimes, [$forks, $forkedTime];
	
	print "Pass $i complete. $forks processes(s), " . sprintf("%.3f",$forkedTime). " seconds. " . sprintf("%.3f", ( ($i * $numberofInnerLoops) / $forkedTime) / 1000000 )  . " ips.\n";

	passDataUpdate($i);
	
	print passDataReport() ;
	

} # End of OUTERLOOP.

#  Benchmark run is done.
###############################################################################

chomp (my $endingUptime = runCommandGetOutputV3('uptime', [], ['/usr/sbin', @defaultPathList] )->[0] || "NA");




#
# Get hostname.

if ($anonymous) {

	$hostname = "anon";

} else {

	#
	# If Sys::Hostname module available then get this machine's hostname using eval.

	$hostname = Sys::Hostname::hostname() if eval {

		require Sys::Hostname;

		Sys::Hostname::hostname->import();

		1;

	};

}

my $sysctlOutputRef = runCommandGetOutputV3('sysctl', ['-a'], ['/usr/sbin'])  ;












###############################################################################
#  Gather machine info.
#

my $ps_aux_OutputRef = runCommandGetOutputV3('ps', ['aux'], ['/bin', @defaultPathList])  ;

print "Getting a copy of lsof -n ...\n";

my $lsof_n_OutputRef = runCommandGetOutputV3('lsof', ['-n'], ['/usr/sbin', @defaultPathList])  ;

my %machineDetails;			# Property and value of various machine specs.

my @cpuLookupTable;			# CPU data from ark.intel.com






#
# Get data from system_profiler to %machineDetails

if ( $^O =~ m/darwin/i ) {

	system_profiler_parse(\%machineDetails, "SPHardwareDataType");

	system_profiler_parse(\%machineDetails, "SPSoftwareDataType");

}




#
# Organize data from sysctl.

if  ($sysctlOutputRef) {
	
	sysctl_parse(\%machineDetails, $sysctlOutputRef);

}




#
# If on windows use "wmic cpu get name" for cpu.marketing.string

if ($^O =~ m/mswin32/i ) {

	$machineDetails{'cpu.marketing.string'} = runCommandGetOutputV3('WMIC.EXE',['cpu', 'get', 'name'], ["$winDir/System32/wbem"] )->[1] || 'nA';
		
	$machineDetails{'cpu.marketing.string'} =~ s/\n//sg;

	$machineDetails{'cpu.marketing.string'} =~ s/\r//sg;
	
}




#
# Add alias for cpu.marketing.string 

$machineDetails{'cpu.marketing.string'} = $machineDetails{'machdep.cpu.brand_string'} if $machineDetails{'machdep.cpu.brand_string'}; 

$machineDetails{'cpu.marketing.string'} = $machineDetails{'hw.model'} if $machineDetails{'hw.model'};




#
# Get CPU max turbo using lookup table compiled from ark.intel.com

$machineDetails{'Max Turbo'} = "unknown"; 

if ( defined $machineDetails{'machdep.cpu.brand_string'} ) {  # <- macOS

	loadCPUlookupTable();

	$machineDetails{'Max Turbo'} = getMaxTurbo($machineDetails{'machdep.cpu.brand_string'});

}

if ( defined $machineDetails{'hw.model'} ) {  ## freeBSD

	loadCPUlookupTable();

	$machineDetails{'Max Turbo'} = getMaxTurbo($machineDetails{'hw.model'});

}


if ( defined $machineDetails{'win.cpu'} ) {  ## windows

	loadCPUlookupTable();

	$machineDetails{'Max Turbo'} = getMaxTurbo($machineDetails{'win.cpu'});

}




#
# uname -a or ver
# Retrieve output of ver command on windows, or uname command on other OSs.

my $uname_or_ver;

if ($^O =~ m/mswin32/i) {
	
	my @uname_or_ver = `ver`;  # ver command is a builtin so just use backtics.
	
	chomp ($uname_or_ver = $uname_or_ver[1]);
	
} else {

	my $uname_or_verRef  = runCommandGetOutputV3('uname', ['-a'], ['/usr/bin', @defaultPathList]) ;#${ getCommandOutput("$unameCommand -a") }[0];
	
	chomp ($uname_or_ver = $uname_or_verRef->[0]);
	
}

$uname_or_ver = 'NA' unless $uname_or_ver;




#
# Gather various data into commonRowData array.

my @commonRowData; 

push @commonRowData,  timestamp_excel($^T);




#
# Run UUID.  Used in CSV output to tie results from multiple reports to the 
# same run.

my @uuid;

if ($^O =~ m/mswin32/i) {

	require Win32;

	@uuid = Win32::GuidGen();

} else {

	chomp (@uuid = @{runCommandGetOutputV3('uuidgen', [], ['/usr/bin', @defaultPathList] )});

}
 
$uuid[0] = "$hostname-$^T" unless $uuid[0];  ## Failsafe incase no uuid, use scriptStartTime instead.

push @commonRowData, $uuid[0];




#
# Computer Name

push @commonRowData,  $hostname;




#
# Username

if  ($anonymous) {

	$username = "anon";

} else {

	$username = getlogin() || (getpwuid($<))[0] || $ENV{LOGNAME} || $ENV{USER} || "unknown";

}

push @commonRowData,  $username;




#
# System Serial Number

if ($anonymous) {

	push @commonRowData,  "anon";

} else {

	push @commonRowData,  getItemFromMachineDetails( \%machineDetails,  "Serial Number (system)");

}







push @commonRowData,  getItemFromMachineDetails( \%machineDetails, "Model Name");

push @commonRowData,  getItemFromMachineDetails( \%machineDetails, "Model Identifier");

push @commonRowData,  getItemFromMachineDetails( \%machineDetails, "Processor Name");

push @commonRowData,  getItemFromMachineDetails( \%machineDetails, "Processor Speed");

push @commonRowData,  getItemFromMachineDetails( \%machineDetails, "Boot ROM Version");

push @commonRowData,  getItemFromMachineDetails( \%machineDetails, "SMC Version (system)");

push @commonRowData,  getItemFromMachineDetails( \%machineDetails, "System Version"); # OS details

push @commonRowData,  getItemFromMachineDetails( \%machineDetails, "cpu.marketing.string");

push @commonRowData,  getItemFromMachineDetails( \%machineDetails, "hw.cpufrequency");

push @commonRowData,  getItemFromMachineDetails( \%machineDetails, "Max Turbo");

push @commonRowData,  getItemFromMachineDetails( \%machineDetails, "machdep.cpu.core_count");

push @commonRowData,  getItemFromMachineDetails( \%machineDetails, "machdep.cpu.thread_count");

push @commonRowData,  $uname_or_ver;

push @commonRowData,  "$]";	# perl Version. use $] for backwards compatibility.

push @commonRowData,  scalar @{$lsof_n_OutputRef} - 1;	# lsofUser

push @commonRowData,  '';	# Placeholder incase we are able to run lsof as root.

push @commonRowData,  "$scriptName $scriptVersionString benchmarkEngineVersion $benchmarkEngineVersion  INNERLOOP: foreach (1 .. $numberofInnerLoops ) {}";

push @commonRowData,  "$beginningUptime";

push @commonRowData,  "$endingUptime";

push @commonRowData,  $notes;

push @commonRowData, "$numberofInnerLoops" ;




my @fieldNames = (	# Column names of data output.

	"Run Date Time",								## Now which is then.
	"Run UUID",										## A uniquie id given to this running of the loops.
	"Computer Name",								## from system_profiler
	"User Name",									## from perl function or environment variable.
	"System Serial Number",							## from system_profiler
	"Model Name",									## from system_profiler
	"Model Identifier",								## from system_profiler
	"Processor Name",								## from system_profiler
	"Processor Speed",								## from system_profiler
	"Boot ROM Version/System Firmware Version",		## from system_profiler
	"SMC Version (system)",							## from system_profiler
	"OS v",											## system_profiler
	"CPU Marketing String ( on macOS sysctl -a machdep.cpu.brand_string)",	## from sysctl -a
	"Current Processor Speed",						## sysctl -a
	"Max Turbo (Intel Spec)",						## Look up in data gathered from ark.intel.com 
	"Cores",										## syctl -a machdep.cpu.core_count
	"Threads",										## from sysctl -a (machdep.cpu.thread_count)
	"uname -a or ver",								## uname -a command
	"perl version (\$])",							## The value of variable $]
	"lsof count (user)",							## lsof command
	"lsof count (root)",							## * Not implemented at this time.  Users are welcome to get this on their own and add to CSV rather than run this script as root.
	"Benchmark Version",							## The benchmarkEngineVersion.  That is the fork and loop code that is being timed.
	"Beginning Uptime",								## uptime command
	"Ending Uptime",								## uptime command
	"Notes",										## User supplied notes from command line options.
	"Innerloops",									## Number of iterations of the INNERLOOP.

);




#
# Add number pass columns using the defined maxPasses variable.

for my $i ( 1 .. $maxPasses ) {

	push @fieldNames, "Pass #$i";

}




#
# Build @dataRow for output.

my @dataRow;

foreach (@commonRowData) {

	push @dataRow, $_ ;

}


for my $i (1 .. $#passTimes) {

	push @dataRow, $passTimes[$i][1]  ;

}




my $fieldNamesRowCSV = makeCSV(@fieldNames);  # String containing column names in CSV format.

my $dataRowCSV = makeCSV(@dataRow);  




#### Send a copy of CSV to stdout.

print "\n\nCSV BEGIN\n";

print "$fieldNamesRowCSV";

print "\n" . $dataRowCSV;

print "\nCSV END\n";










# Create or verify top level output directory. I.E.
# /Users/home/mike/baselines/psb.pl/7.7

my $outputDir = Baselines::createOutputDir(

	$outputRoot, 
	$scriptGroup, 
	$scriptName, 
	"$scriptVersion[0].$scriptVersion[1]", 

);

unless ($outputDir && -d $outputDir && -w $outputDir) {

	die "Problem creating outputDir. Cannot continue.";

}

print "Will save results in $outputDir\n";




#
# Create or verify output sub directories.

my @outputSubDirs = Baselines::createOutputSubDirs(

	$outputDir,
	'machineInfo'

);

die "Could not make or verify all outputSubDirs. [@outputSubDirs]." unless scalar @outputSubDirs eq 1;




#
# Write to CSVoutputFile.

my $CSVCSVoutputFileName	= "$scriptName-$scriptVersion[0].$scriptVersion[1]-$hostname.csv";

my $CSVoutputFile 			= "$outputDir/$CSVCSVoutputFileName";




#
# Set sendHeader Flag.  If this is a new file will want to send BOM and Column Names as first row.

my $sendHeader = 0;

$sendHeader = 1 unless -e $CSVoutputFile ; 


print "Writing CSV to [$CSVoutputFile].\n";

open (FHO, ">>", $CSVoutputFile) or die "Could not open file for writing [$CSVoutputFile] $!";



# Write column headers if this is a new file.

if ($sendHeader == 1) {

	## Output BOM otherwise Excel may not display UTF-8 unicode characters correctly.
	print FHO "\x{ef}\x{bb}\x{bf}";  ## So excel will display unicode correctly.

	print FHO "$fieldNamesRowCSV";

}


# Write out row in csv format.

print FHO "\n" . $dataRowCSV;

close FHO or warn "Could not close filehandle on $CSVoutputFile.\n";









#
# Send ouput of sysctl to a file

if ( $sysctlOutputRef ) {
	
	print "Sending a copy of sysctl -a to $outputDir/machineInfo/sysctls\n";
	
	unless (-d "$outputDir/machineInfo/sysctls") {

		mkdir "$outputDir/machineInfo/sysctls" or warn "Could not make directory [$outputDir/machineInfo/sysctls] $! ";

	}
	
	my $sysctlFile = "$outputDir/machineInfo/sysctls/$uuid[0]-sysctl_-a.txt" ;

	unless (-e $sysctlFile) {
	
		open (my $sysfo,">",$sysctlFile) or warn "Could not open file for writing $!";

		print $sysfo @{$sysctlOutputRef} ;

		close $sysfo;

	}

}









#
# Send a copy of ps aux to a file.

unless ($^O =~ m/mswin32/i) {

	print "Saving a copy of ps aux to $outputDir/machineInfo/ps\n";

	unless (-d "$outputDir/machineInfo/ps") {

		mkdir "$outputDir/machineInfo/ps" or warn "Could not make directory [$outputDir/machineInfo/ps] $! ";

	}
	
	my $psFile = "$outputDir/machineInfo/ps/$uuid[0]-ps_aux.txt" ;

	unless (-e $psFile) {
	
		open (my $psfo,">",$psFile) or warn "Could not open file for writing $!";

		print $psfo @{$ps_aux_OutputRef};

		close $psfo;
	}

}









#
# Send a copy of lsof to a file.

unless ($^O =~ m/mswin32/i) {

	unless (-d "$outputDir/machineInfo/lsof") {

		mkdir "$outputDir/machineInfo/lsof" or warn "Could not make directory [$outputDir/machineInfo/lsof] $! ";

	}
	
	my $lsofFile = "$outputDir/machineInfo/lsof/$uuid[0]-lsof_-n.txt" ;

	unless (-e $lsofFile) {
	
		open (my $lsoffo,">",$lsofFile) or warn "Could not open file for writing $!";

		print $lsoffo @{$lsof_n_OutputRef};

		close $lsoffo;

	} else {
	
		warn "Will not overwrite file [$lsofFile].";
	
	}

}









#
# Send a copy of last pass totals to a file.

my $passTotalsFile = "$outputDir/$scriptName-$scriptVersion[0].$scriptVersion[1]-$hostname-passTotals.txt";

print "Writing pass Totals to $passTotalsFile\n";

open (my $PTO, ">>", "$outputDir/$scriptName-$scriptVersionString-$hostname-passTotals.txt") or warn "Could not open file for writing. $!";

print	$PTO	"Run Date: " . timestamp_excel($^T) . "\n";
print	$PTO	"Run UUID: $uuid[0]\n";
print	$PTO	"Pass Totals: (INNERLOOP $numberofInnerLoops)\n";
print	$PTO	passDataReport();

close 	$PTO;




print "\n\nResults were written to:\n$outputDir\n" if $verbose > 0;
print "$scriptName $scriptVersionString Done.\n" if $verbose > 0;

# if ($thisOS eq 'mac') { system ("open $outputDir"); }
# if ($thisOS eq 'win') { system ("start $outputDir"); }




exit 0;








#
# Subroutines
###############################################################################


sub subroutines {}




sub runCommandGetOutputV3 {

	# Run command and collect it's stdout.  Return reference to array.
	
	# Timeout if command runs for too long.
	
	# Return 0 if command did not run.

	
	# First input is required.
	
	unless ( defined $_[0]) {
	
		warn "WARN Invalid inputs to subroutine. [@_]";
		
		return ();

	}
	
	
	
	
	my $commandName			= $_[0];

	my $commandArgs			= $_[1]	|| [];

	my $pathList			= $_[2]	|| [] ;  # List of paths where command might be installed. Empty string if no path.

	my $timeoutRequested	= $_[3];
	
	my $timeout 			= 333;

	my @data 				= ();
	
	

	if ( defined $pathList && ref $pathList ne 'ARRAY') {
	
		warn "WARN Skipping $commandName. Bad input to subroutine. pathList is not an array ref. [$pathList]";
		
		return ();

	}
	

	
	if ( defined $commandArgs && ref $commandArgs ne 'ARRAY') {
	
		warn "WARN Skipping $commandName. Bad input to subroutine. commandArgs is not an array ref. [$commandArgs]";
		
		return ();

	} 
	
	
	
	

	if (defined $timeoutRequested) {
	
		if ($timeoutRequested =~ m/\D/) {
		
			warn "WARN Invalid timeout [$timeoutRequested] for [$commandName]. will use default.";
			
		} elsif ($timeoutRequested > 10000) {
		
			warn "WARN Invalid timeout [$timeoutRequested] for [$commandName]. will use default.";

		} else {
		
			$timeout = $timeoutRequested;
		}
	
	}
					
			
	
	
	
	
	
	
	
	
	
	#
	# Look for executable commandName in each path listed in pathList.  If found
	# then prepend path and set command.  If none found then issue warning and
	# return empty list.


	my $command;
		
	for my $path ( @{$pathList} ) {
	
		my $commandCheck = "$path/$commandName";
		
		print "\tChecking $commandCheck \n" if $verbose > 2;
		
		if ( -x $commandCheck ) {
		
			print " FOUND $commandCheck.\n" if $verbose > 2;
			
			$command = $commandCheck ;
	
 			last;
		
		}
	
	}
	
	unless ($command) {
	
		warn "WARN Could not find $commandName. Searched @{$pathList}\n" if $verbose > 1;
		
		return [];
	
	}
	
	
	my $pid;	
	
	my $commFHI;

	eval {
	
		local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
	
		alarm $timeout;
	
		$pid = open ($commFHI, "-|", $command, @{$commandArgs});  # FYI, pipe open may return a PID even if cannot run the command. For example here we are redirecting STDERR from the command to a file.  This causes the open to fork a separate shell and so will get a PID from that.

		@data = <$commFHI>;
		
		alarm 0;

		print "\tEval made it, alarm reset to 0.\n" if $verbose > 2;		

	};


	if ($@) {

		die unless $@ eq "alarm\n";   # propagate unexpected errors
	
		#
		# Eval timed out.
	
		warn "WARN Command timed out.. Alarm reached ($timeout) while waiting for output from opened pipe.  Command was [$command @{$commandArgs}] ? [$?] ! [$!]";

		kill 'TERM', $pid;
		
		close $commFHI or warn "WARN Error closing commFHI pipe: $! Exit status $? from commFHI";
        				  
		# die "The command timed out after alarm ($timeout).\n";
		
	}  else {
	
		#
		# Eval did not timeout.
		
		close $commFHI or warn "WARN Error closing commFHI pipe: [$command @{$commandArgs}] Exit status [$?] [$!]";
        
	}


	return \@data;
	
}









sub perlSimpleBenchmarkEngine_0_4_1 {

	my $benchmarkEngineVersion = "0.4.1"; # 0.4.1 Code cleanup.
	
	return "benchmarkEngine $benchmarkEngineVersion" unless $_[0];
	
	die "Bad input to perlSimpleBenchmarkEngine_0_4_1. Only digits allowed. [$_[0]]" if ($_[0] =~ /\D/);


	my $forks = $_[0];

	my @pids;

	my $outerStartTime = gettimeofday;


	foreach my $ii (1 .. $forks) {

		my $pid = fork();

		if ($pid == 0) {

			foreach (1 .. $numberofInnerLoops ) {}    # INNERLOOP Empty foreach loop. 

			exit;		

		}

		push @pids, $pid;

	}
	
	
	for my $pid (@pids) {

		waitpid $pid, 0;

	}

	
	return ($forks, gettimeofday - $outerStartTime);

}









sub passDataUpdate {

	## Given a pass number, update the @passReports array with new data.
	
	# 	@passData AOA
	#	0  0 ""
	#	1  1 processes
	# 	1  2 seconds
	# 	1  3 seconds Delta
	# 	1  4 iterations
	# 	1  5 ips
	# 	1  6 ipsDelta
	# 	1  7 ipsDeltaPercent
	# 	1  8 ipsTotalDelta
	# 	1  9 ipsTotalDeltaPercent
	
	unless ( $_[0] && $_[0] =~ /^\d+$/ ) { warn "Bad input to updatePassTotals. $!"; return; }


	my $pass = $_[0];
	
	my $processes					= $pass;
	my $seconds         			= $passTimes[$pass][1];
	my $secondsDelta       			= $seconds;
	my $iterations      			= ($numberofInnerLoops * $pass);
	my $ips             			= ($iterations / $seconds);
	my $ipsDelta        			= 0;
	my $ipsDeltaPercent 	 	    = 0;
	my $ipsTotalDelta			    = 0;
	my $ipsTotalDeltaPercent		= 0;

	
	if ($pass == 1) {
		
		push @passData , [ "", $processes, $seconds, $secondsDelta, $iterations, $ips, $ipsDelta, $ipsDeltaPercent, $ipsTotalDelta, $ipsTotalDeltaPercent ];
		
	}
	

	
	if ($pass > 1) {
		
		$secondsDelta			= $seconds - $passData[$pass-1][2];

		my $ipsFirst			= $passData[1][5];

		my $ipsPrevious 		= $passData[$pass-1][5];	

		$ipsDeltaPercent		= ( $ips - $ipsPrevious ) / $ipsPrevious * 100;

		$ipsTotalDeltaPercent	= ( $ips - $ipsFirst )    / $ipsFirst    * 100;

		
                         # 0   1           2         3              4            5     6          7                 8               9
		push @passData , [ '', $processes, $seconds, $secondsDelta, $iterations, $ips, $ipsDelta, $ipsDeltaPercent, $ipsTotalDelta, $ipsTotalDeltaPercent ];

	}

}









sub passDataReport {

	## Run though passData and generate formatted output.
		
	my @passDataReport;
	
	push @passDataReport, "\nPass Totals: (INNERLOOP was $numberofInnerLoops )\n" ;
	push @passDataReport, "IPS = Iterations Per Second\n" ;
	push @passDataReport, ("Pass#  Sec       SecDlt     IPS/1000000  IPSdlt%  IPSdltTotal% \n");
	
	
	
	
	## Find hightest IPS.

	my $maxIPSid = 1;

	foreach my $i (1 .. $#passData) {
	
		if ($passData[$i][5] > $passData[$maxIPSid][5]) { $maxIPSid = $i;}
	
	}

	
	# Store pass data table.
	
	foreach my $i (1 .. $#passData) {
	
		my $passDataReportLine = sprintf (

			"%-6s %-9s %-10s %-12s %-8s %s",
			$i, sprintf("%.3f", $passData[$i][2]), sprintf("%.3f", $passData[$i][3]), sprintf("%.3f", $passData[$i][5]/1000000), sprintf("%.3f", $passData[$i][7]), sprintf("%.3f", $passData[$i][9]) 

		);
	
		if ( $i == $maxIPSid ) { $passDataReportLine .= " | Max IPS"; }
		
		push @passDataReport, $passDataReportLine . "\n";
	
	}


	push @passDataReport, ("----------------------------------------------------------------------\n");


	return @passDataReport;

}









sub timestamp_excel {

	# Return a time stamp in the form mm/dd/yyyy hh:mm:ss suitable for Excel.

	return "" unless $_[0];

	my $timeValue = $_[0];

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($timeValue);
	

	return
	
	sprintf("%02d",($mon+1)) . "/" . sprintf("%02d",$mday) . "/" . ($year+1900) 
	. " " .
	sprintf("%02d",$hour) . ":"	. sprintf("%02d",$min) . ":" . sprintf("%02d",$sec);

}









sub system_profiler_parse {

	#
	# Get data from macOS system_profiler command and add to %machineDetails

	my $machineDetailsRef = $_[0];
	
	my $dataType = $_[1];
	
	return unless $machineDetailsRef && $dataType ;
		
	foreach (	@{runCommandGetOutputV3('system_profiler', [$dataType], ['/usr/sbin'])} 	) {
		
		chomp;
		
		s/^\s+//;  ## Remove leading whitespace.
			
		my ($key, $value) = split /:\s/,$_,2;
		
		next unless (defined $key && defined $value);
		
		$machineDetailsRef->{$key}=$value;
		
	}
	
	warn "The command [system_profiler $dataType] failed. [$?]" if $?;

	return;
	
}









sub sysctl_parse {

	## Get data from sysctl -a command and add to %machineDetails
	
	my $machineDetailsRef 	= $_[0];
	
	my $sysctlDataRef		= $_[1];

	return unless @{$sysctlDataRef};
	
	foreach ( @{$sysctlDataRef} ) {

		my ($key, $value) = split /:\s/,$_,2;

		next unless (defined $key && defined $value);
		
		chomp $value;
		
		$machineDetailsRef->{$key}=$value;

	}

	return;
	
}









sub getItemFromMachineDetails {  
	
	
	my $machineDetailsRef = $_[0];

	my $field = $_[1];

	my $data = ''; # Handle the unknown.
	

	if ($machineDetails{$field}) { 

		$data = $machineDetails{$field};

		return $data;

	} 


	#
	# Handle differently named properties in system_profiler.

	# Some call it System Firmware Version.
	
	if ($field eq "Boot ROM Version"){
		$field = "System Firmware Version";
		$data = $machineDetails{$field} if $machineDetails{$field};
		return $data;
	}


	if ($field eq "Serial Number (system)"){
		$field = "Serial Number";
		$data = $machineDetails{$field} if $machineDetails{$field};
		return $data;
	}


	if ($field eq "Model Name"){
		$field = "Machine Model";
		$data = $machineDetails{$field} if $machineDetails{$field};
		return $data;
	}


	if ($field eq "Processor Name"){
		$field = "CPU Type";
		$data = $machineDetails{$field} if $machineDetails{$field};
		return $data;
	}


	if ($field eq "Processor Speed"){
		$field = "CPU Speed";
		$data = $machineDetails{$field} if $machineDetails{$field};
		return $data;
	}
	

	return $data;

}









sub getMaxTurbo {
	
	unless ($_[0]) {

		return "Not found. No args sent to getMaxTurbo";

	}

	my $machdepcpubrand_string = $_[0];

	if ($machdepcpubrand_string eq 'unknown') { return "Unknown"; }

	my @cpuBrandBreakdown = split /\s+/,$machdepcpubrand_string;  ## i.e. Intel(R) Core(TM) I7-2860QM CPU @ 2.50GHz

	#
	# Read through lookup table

	foreach my $row (@cpuLookupTable){

		my ($Product_Name, $pn, $Status, $Launch_Date, $Total_Cores, $ThreadCount, $ClockSpeed, $ClockSpeedMax, $TurboBoostTech2MaxFreq) = split /,/,$row,9;

		foreach my $cpuBrandItem (@cpuBrandBreakdown) {

			if ($Product_Name =~ /$cpuBrandItem/i) {

				return $ClockSpeedMax;

			}

		}

	}

	return "not found";  ## If we did not find anything send back not found.
}









sub makeCSV {
	
	# Given a row of data return the row as CSV.
	#
		
	my $lineOfCsv;
	
	foreach my $field ( @_ ) {  
 		
		# CSV quoting 
		#
		
		if ($field =~ m/\,/ or $field =~ m/\"/) {    ## If field contains a comma or double quote then enclose the field in double quotes, but first escape double quotes. 

		 	$field =~ s/"/""/g;  	## Escape double quotes;

   			$field = "\"$field\"";	## Enclose field in double quotes.
 	
		} 

		$lineOfCsv .= "$field,";
	
	}


	## Remove trailing comma.
	$lineOfCsv =~ s/,$//;
	

	return $lineOfCsv;	

}




sub loadCPUlookupTable {

## ark.intel.com data in $table last updated 20220118

	my $table = <<END_TABLE;
intelProductDescription,Processor Number,Status,Launch Date,Total Cores,ThreadCount,ClockSpeed,ClockSpeedMax,TurboBoostTech2MaxFreq
Intel® Core™ i5-9400H Processor 8M Cache/ up to 4.30 GHz,i5-9400H,Launched,Q2'19,4,8,2.50 GHz,4.30 GHz,notFound
Intel® Celeron® Processor G5900E 2M Cache/ 3.20 GHz,G5900E,Launched,Q2'20,2,2,3.20 GHz,notFound,notFound
Intel® Core™ i5-560M Processor 3M Cache/ 2.66 GHz,i5-560M,Discontinued,Q3'10,2,4,2.66 GHz,3.20 GHz,notFound
Intel® Core™ i5-4590T Processor 6M Cache/ up to 3.00 GHz,i5-4590T,Launched,Q2'14,4,4,2.00 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i5-9400 Processor 9M Cache/ up to 4.10 GHz,i5-9400,Launched,Q1'19,6,6,2.90 GHz,4.10 GHz,4.10 GHz
Intel® Xeon® Processor E5345 8M Cache/ 2.33 GHz/ 1333 MHz FSB,E5345,Discontinued,Q1'07,4,notFound,2.33 GHz,notFound,notFound
Intel® Core™2 Duo Processor E6300 2M Cache/ 1.86 GHz/ 1066 MHz FSB,E6300,Discontinued,Q3'06,2,notFound,1.86 GHz,notFound,notFound
Intel® Pentium® Processor G2130 3M Cache/ 3.20 GHz,G2130,Discontinued,Q1'13,2,2,3.20 GHz,notFound,notFound
Intel® Core™ i7-10870H Processor 16M Cache/ up to 5.00 GHz,i7-10870H,Launched,Q3'20,8,16,2.20 GHz,5.00 GHz,notFound
Intel® Xeon® Processor E3110 6M Cache/ 3.00 GHz/ 1333 MHz FSB,E3110,Discontinued,Q1'08,2,notFound,3.00 GHz,notFound,notFound
Intel® Core™ i7-9850H Processor 12M Cache/ up to 4.60 GHz,i7-9850H,Launched,Q2'19,6,12,2.60 GHz,4.60 GHz,notFound
Intel® Core™ i7-9850H Processor 12M Cache/ up to 4.60 GHz,i7-9850H,Launched,Q2'19,6,12,2.60 GHz,4.60 GHz,notFound
Intel® Core™ i5-4302Y Processor 3M Cache/ up to 2.30 GHz,i5-4302Y,Discontinued,Q3'13,2,4,1.60 GHz,2.30 GHz,2.30 GHz
Intel® Xeon® Processor E7-4870 v2 30M Cache/ 2.30 GHz,E7-4870V2,Launched,Q1'14,15,30,2.30 GHz,2.90 GHz,2.90 GHz
Intel® Celeron® Processor N6211 1.5M Cache/ up to 3.00 GHz,N6211,Launched,Q1'21,2,2,1.20 GHz,notFound,notFound
Intel® Celeron® Processor B810 2M Cache/ 1.60 GHz,B810,Discontinued,Q1'11,2,2,1.60 GHz,notFound,notFound
Intel® Core™ i3-3220T Processor 3M Cache/ 2.80 GHz,i3-3220T,Discontinued,Q3'12,2,4,2.80 GHz,notFound,notFound
Intel® Core™ i5-2410M Processor 3M Cache/ up to 2.90 GHz,i5-2410M,Discontinued,Q1'11,2,4,2.30 GHz,2.90 GHz,2.90 GHz
Intel® Pentium® Processor Extreme Edition 840 2M Cache/ 3.20 GHz/ 800 MHz FSB,840,Discontinued,Q2'05,2,notFound,3.20 GHz,notFound,notFound
Intel® Xeon® Processor E5-2643 v2 25M Cache/ 3.50 GHz,E5-2643V2,Discontinued,Q3'13,6,12,3.50 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Processor X5355 8M Cache/ 2.66 GHz/ 1333 MHz FSB,X5355,Discontinued,Q4'06,4,notFound,2.66 GHz,notFound,notFound
Intel® Core™ i7-4860HQ Processor 6M Cache/ up to 3.60 GHz,i7-4860HQ,Discontinued,Q1'14,4,8,2.40 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i7-660LM Processor 4M Cache/ 2.26 GHz,i7-660LM,Discontinued,Q3'10,2,4,2.26 GHz,3.06 GHz,notFound
Intel® Core™ i5-5675R Processor 4M Cache/ up to 3.60 GHz,i5-5675R,Discontinued,Q2'15,4,notFound,3.10 GHz,3.60 GHz,3.60 GHz
Intel Atom® Processor N475 512K Cache/ 1.83 GHz,N475,Discontinued,Q2'10,1,2,1.83 GHz,notFound,notFound
Intel® Celeron® Processor G5900TE 2M Cache/ 3.00 GHz,G5900TE,Launched,Q2'20,2,2,3.00 GHz,notFound,notFound
Intel® Core™ i7-3687U Processor 4M Cache/ up to 3.30 GHz,i7-3687U,Discontinued,Q1'13,2,4,2.10 GHz,3.30 GHz,3.30 GHz
Intel® Celeron® Processor N2807 1M Cache/ up to 2.16 GHz,N2807,Launched,Q1'14,2,2,1.58 GHz,notFound,notFound
Intel® Core™ i9-12900T Processor 30M Cache/ up to 4.90 GHz,i9-12900T,Launched,Q1'22,16,24,notFound,4.90 GHz,notFound
Intel® Core™ i7-5557U Processor 4M Cache/ up to 3.40 GHz,i7-5557U,Discontinued,Q1'15,2,4,3.10 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i7-5557U Processor 4M Cache/ up to 3.40 GHz,i7-5557U,Discontinued,Q1'15,2,4,3.10 GHz,3.40 GHz,3.40 GHz
Intel® Pentium® Silver N6005 Processor 4M Cache/ up to 3.30 GHz,N6005,Launched,Q1'21,4,4,2.00 GHz,notFound,notFound
Intel® Pentium® Processor Extreme Edition 955 4M Cache/ 3.46 GHz/ 1066 MHz FSB,955,Discontinued,Q1'06,2,notFound,3.46 GHz,notFound,notFound
Intel® Core™ i3-3220 Processor 3M Cache/ 3.30 GHz,i3-3220,Discontinued,Q3'12,2,4,3.30 GHz,notFound,notFound
Intel® Pentium® Gold G5400T Processor 4M Cache/ 3.10 GHz,G5400T,Launched,Q2'18,2,4,3.10 GHz,notFound,notFound
Intel® Core™ i3-8145U Processor 4M Cache/ up to 3.90 GHz,i3-8145U,Launched,Q3'18,2,4,2.10 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i3-8145U Processor 4M Cache/ up to 3.90 GHz,i3-8145U,Launched,Q3'18,2,4,2.10 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor E7-8880 v2 37.5M Cache/ 2.50 GHz,E7-8880V2,Discontinued,Q1'14,15,30,2.50 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® E-2236 Processor 12M Cache/ 3.40 GHz,E-2236,Launched,Q2'19,6,12,3.40 GHz,4.80 GHz,4.80 GHz
Intel® Xeon® Gold 6126F Processor 19.25M Cache/ 2.60 GHz,6126F,Launched,Q3'17,12,24,2.60 GHz,3.70 GHz,notFound
Intel® Core™ i7-7700 Processor 8M Cache/ up to 4.20 GHz,i7-7700,Launched,Q1'17,4,8,3.60 GHz,4.20 GHz,4.20 GHz
Intel Atom® Processor S1260 1M Cache/ 2.00 GHz,S1260,Discontinued,Q4'12,2,4,2.00 GHz,notFound,notFound
Intel® Xeon® Processor E5-2643 10M Cache/ 3.30 GHz/ 8.00 GT/s Intel® QPI,E5-2643,Discontinued,Q1'12,4,8,3.30 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® Processor L5506 4M Cache/ 2.13 GHz/ 4.80 GT/s Intel® QPI,L5506,Discontinued,Q1'09,4,4,2.13 GHz,notFound,notFound
Intel® Xeon® E-2124G Processor 8M Cache/ up to 4.50 GHz,E-2124G,Launched,Q3'18,4,4,3.40 GHz,4.50 GHz,4.50 GHz
Intel Atom® Processor Z625 512K Cache/ 1.90 GHz,Z625,Discontinued,Q2'10,1,2,1.90 GHz,notFound,notFound
Intel® Xeon® Gold 6154 Processor 24.75M Cache/ 3.00 GHz,6154,Launched,Q3'17,18,36,3.00 GHz,3.70 GHz,notFound
Intel® Celeron® Processor 3867U 2M Cache/ 1.80 GHz,3867U,Launched,Q1'19,2,2,1.80 GHz,notFound,notFound
Intel® Core™ i5-8400T Processor 9M Cache/ up to 3.30 GHz,i5-8400T,Discontinued,Q2'18,6,6,1.70 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i5-10200H Processor 8M Cache/ up to 4.10 GHz,i5-10200H,Launched,Q3'20,4,8,2.40 GHz,4.10 GHz,4.10 GHz
Intel® Core™ i5-7500T Processor 6M Cache/ up to 3.30 GHz,i5-7500T,Launched,Q1'17,4,4,2.70 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i5-11260H Processor 12M Cache/ up to 4.40 GHz,i5-11260H,Launched,Q2'21,6,12,notFound,4.40 GHz,notFound
Intel® Xeon® Processor E3-1230L v3 8M Cache/ 1.80 GHz,E3-1230Lv3,Discontinued,Q2'13,4,8,1.80 GHz,2.80 GHz,2.80 GHz
Intel® Xeon® Processor W3520 8M Cache/ 2.66 GHz/ 4.80 GT/s Intel® QPI,W3520,Discontinued,Q1'09,4,8,2.66 GHz,2.93 GHz,notFound
Intel® Core™2 Duo Processor P7350 3M Cache/ 2.00 GHz/ 1066 MHz FSB,P7350,Discontinued,Q3'08,2,notFound,2.00 GHz,notFound,notFound
Intel® Pentium® Processor G2120T 3M Cache/ 2.70 GHz,G2120T,Discontinued,Q2'13,2,2,2.70 GHz,notFound,notFound
Intel® Core™ i5-9600K Processor 9M Cache/ up to 4.60 GHz,i5-9600K,Launched,Q4'18,6,6,3.70 GHz,4.60 GHz,4.60 GHz
Intel® Core™ i7-2600S Processor 8M Cache/ up to 3.80 GHz,i7-2600S,Discontinued,Q1'11,4,8,2.80 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i3-10100TE Processor 6M Cache/ up to 3.60 GHz,i3-10100TE,Launched,Q2'20,4,8,2.30 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® E-2144G Processor 8M Cache/ up to 4.50 GHz,E-2144G,Launched,Q3'18,4,8,3.60 GHz,4.50 GHz,4.50 GHz
Intel® Pentium® Processor E5200 2M Cache/ 2.50 GHz/ 800 MHz FSB,E5200,Discontinued,Q3'08,2,notFound,2.50 GHz,notFound,notFound
Intel® Pentium® Processor 3560Y 2M Cache/ 1.20 GHz,3560Y,Discontinued,Q3'13,2,2,1.20 GHz,notFound,notFound
Intel Atom® Processor S1220 1M Cache/ 1.60 GHz,S1220,Discontinued,Q4'12,2,4,1.60 GHz,notFound,notFound
Intel® Xeon® Processor E5-2667 15M Cache/ 2.90 GHz/ 8.00 GT/s Intel® QPI,E5-2667,Discontinued,Q1'12,6,12,2.90 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® Processor L5310 8M Cache/ 1.60 GHz/ 1066 MHz FSB,L5310,Discontinued,Q1'07,4,notFound,1.60 GHz,notFound,notFound
Intel® Core™ i9-11900H Processor 24M Cache/ up to 4.80 GHz,i9-11900H,Launched,Q2'21,8,16,notFound,4.90 GHz,notFound
Intel® Core™ i5-7200U Processor 3M Cache/ up to 3.10 GHz,i5-7200U,Launched,Q3'16,2,4,2.50 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Platinum 8160F Processor 33M Cache/ 2.10 GHz,8160F,Launched,Q3'17,24,48,2.10 GHz,3.70 GHz,notFound
Intel® Core™ i3-7100H Processor 3M Cache/ 3.00 GHz,i3-7100H,Launched,Q1'17,2,4,3.00 GHz,notFound,notFound
Intel® Xeon® Processor E3-1565L v5 8M Cache/ 2.50 GHz,E3-1565LV5,Discontinued,Q2'16,4,8,2.50 GHz,3.50 GHz,3.50 GHz
Intel® Pentium® Gold G5500T Processor 4M Cache/ 3.20 GHz,G5500T,Discontinued,Q2'18,2,4,3.20 GHz,notFound,notFound
Intel® Xeon® Processor E7-8891 v2 37.5M Cache/ 3.20 GHz,E7-8891V2,Discontinued,Q1'14,10,20,3.20 GHz,3.70 GHz,3.70 GHz
Intel® Celeron® Processor N5100 4M Cache/ up to 2.80 GHz,N5100,Launched,Q1'21,4,4,1.10 GHz,notFound,notFound
Intel® Core™ i5-560UM Processor 3M Cache/ 1.33 GHz,i5-560UM,Discontinued,Q3'10,2,4,1.33 GHz,2.13 GHz,notFound
Intel® Xeon® Gold 6130 Processor 22M Cache/ 2.10 GHz,6130,Launched,Q3'17,16,32,2.10 GHz,3.70 GHz,notFound
Intel Atom® Processor C3436L 8M Cache/ 1.30 GHz,C3436L,Launched,Q2'20,4,4,1.30 GHz,notFound,notFound
Intel® Xeon® Processor W3550 8M Cache/ 3.06 GHz/ 4.80 GT/s Intel® QPI,W3550,Discontinued,Q3'09,4,8,3.06 GHz,3.33 GHz,notFound
Intel® Xeon® Silver 4215 Processor 11M Cache/ 2.50 GHz,4215,Launched,Q2'19,8,16,2.50 GHz,3.50 GHz,notFound
Intel® Core™ i5-3380M Processor 3M Cache/ up to 3.60 GHz,i5-3380M,Discontinued,Q1'13,2,4,2.90 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i5-2500T Processor 6M Cache/ up to 3.30 GHz,i5-2500T,Discontinued,Q1'11,4,4,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i7-4750HQ Processor 6M Cache/ up to 3.20 GHz,i7-4750HQ,Discontinued,Q3'13,4,8,2.00 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Processor E5-2470 v2 25M Cache/ 2.40 GHz,E5-2470V2,Discontinued,Q1'14,10,20,2.40 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Processor E3-1230 v3 8M Cache/ 3.30 GHz,E3-1230 v3,Discontinued,Q2'13,4,8,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i3-12300 Processor 12M Cache/ up to 4.40 GHz,i3-12300,Launched,Q1'22,4,8,notFound,4.40 GHz,notFound
Intel® Celeron® Processor P4500 2M Cache/ 1.86 GHz,P4500,Discontinued,Q1'10,2,2,1.86 GHz,notFound,notFound
Intel® Core™ i3-2348M Processor 3M Cache/ 2.30 GHz,i3-2348M,Discontinued,Q1'13,2,4,2.30 GHz,notFound,notFound
Intel® Xeon Phi™ Processor 7235 16GB/ 1.3 GHz/ 64 Core,7235,Launched,Q4'17,64,notFound,1.30 GHz,1.40 GHz,notFound
Intel® Xeon® Processor E3-1275 v3 8M Cache/ 3.50 GHz,E3-1275 v3,Launched,Q2'13,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Pentium® Processor P6000 3M Cache/ 1.86 GHz,P6000,Discontinued,Q2'10,2,2,1.86 GHz,notFound,notFound
Intel® Core™ i7-620UM Processor 4M Cache/ 1.06 GHz,i7-620UM,Discontinued,Q1'10,2,4,1.06 GHz,2.13 GHz,notFound
Intel® Pentium® Processor P6100 3M Cache/ 2.00 GHz,P6100,Discontinued,Q3'10,2,2,2.00 GHz,notFound,notFound
Intel Atom® Processor N2600 1M Cache/ 1.6 GHz,N2600,Discontinued,Q4'11,2,4,1.60 GHz,notFound,notFound
Intel® Core™ i7-10875H Processor 16M Cache/ up to 5.10 GHz,i7-10875H,Launched,Q2'20,8,16,2.30 GHz,5.10 GHz,notFound
Intel® Pentium® 4 Processor 672 supporting HT Technology 2M Cache/ 3.80 GHz/ 800 MHz FSB,672,Discontinued,Q4'05,1,notFound,3.80 GHz,notFound,notFound
Intel® Pentium® Processor G3450T 3M Cache/ 2.90 GHz,G3450T,Discontinued,Q3'14,2,2,2.90 GHz,notFound,notFound
Intel® Celeron® Processor N2806 1M Cache/ up to 2.00 GHz,N2806,Discontinued,Q4'13,2,2,1.60 GHz,notFound,notFound
Intel® Core™ i3-6320 Processor 4M Cache/ 3.90 GHz,i3-6320,Discontinued,Q3'15,2,4,3.90 GHz,notFound,notFound
Intel® Xeon® Processor X5482 12M Cache/ 3.20 GHz/ 1600 MHz FSB,X5482,Discontinued,Q4'07,4,notFound,3.20 GHz,notFound,notFound
Intel® Core™ i3-4120U Processor 3M Cache/ 2.00 GHz,i3-4120U,Discontinued,Q2'14,2,4,2.00 GHz,notFound,notFound
Intel® Core™ i5-10500 Processor 12M Cache/ up to 4.50 GHz,i5-10500,Launched,Q2'20,6,12,3.10 GHz,4.50 GHz,4.50 GHz
Intel® Core™ i7-620UE Processor 4M Cache/ 1.06 GHz,i7-620UE,Discontinued,Q1'10,2,4,1.06 GHz,2.13 GHz,notFound
Intel® Celeron® Processor P4505 2M Cache/ 1.86 GHz,P4505,Discontinued,Q1'10,2,2,1.86 GHz,notFound,notFound
Intel® Core™ i3-10100 Processor 6M Cache/ up to 4.30 GHz,i3-10100,Launched,Q2'20,4,8,3.60 GHz,4.30 GHz,4.30 GHz
Intel® Pentium® Gold G6405T Processor 4M Cache/ 3.50 GHz,G6405T,Launched,Q1'21,2,4,3.50 GHz,notFound,notFound
Intel® Core™ i3-1125G4 Processor 8M Cache/ up to 3.70 GHz/ with IPU,i3-1125G4,Launched,Q1'21,4,8,notFound,3.70 GHz,notFound
Intel® Core™ i7-5600U Processor 4M Cache/ up to 3.20 GHz,i7-5600U,Discontinued,Q1'15,2,4,2.60 GHz,3.20 GHz,3.20 GHz
Intel® Xeon Phi™ Coprocessor 7120A 16GB/ 1.238 GHz/ 61 core,7120A,Discontinued,Q2'14,61,notFound,1.24 GHz,1.33 GHz,notFound
Intel® Core™ i3-540 Processor 4M Cache/ 3.06 GHz,i3-540,Discontinued,Q1'10,2,4,3.06 GHz,notFound,notFound
Intel® Core™ i5-8200Y Processor 4M Cache/ up to 3.90 GHz,i5-8200Y,Launched,Q3'18,2,4,1.30 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor E3-1265L v3 8M Cache/ 2.50 GHz,E3-1265Lv3,Discontinued,Q2'13,4,8,2.50 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® W-2135 Processor 8.25M Cache/ 3.70 GHz,W-2135,Launched,Q3'17,6,12,3.70 GHz,4.50 GHz,notFound
Intel® Xeon® Processor L3406 4M Cache/ 2.26 GHz,L3406,Discontinued,Q1'10,2,4,2.26 GHz,2.53 GHz,notFound
Intel® Core™ i3-10110U Processor 4M Cache/ up to 4.10 GHz,i3-10110U,Launched,Q3'19,2,4,2.10 GHz,4.10 GHz,notFound
Intel® Core™ i3-10110U Processor 4M Cache/ up to 4.10 GHz,i3-10110U,Launched,Q3'19,2,4,2.10 GHz,4.10 GHz,notFound
Intel® Xeon® Processor D-1533N 9M Cache/ 2.10 GHz,D-1533N,Launched,Q3'17,6,12,2.10 GHz,2.70 GHz,2.70 GHz
Intel® Core™ i5-5200U Processor 3M Cache/ up to 2.70 GHz,i5-5200U,Discontinued,Q1'15,2,4,2.20 GHz,2.70 GHz,2.70 GHz
Intel® Xeon® Processor E3-1240L v5 8M Cache/ 2.10 GHz,E3-1240LV5,Launched,Q4'15,4,8,2.10 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i3-10100T Processor 6M Cache/ up to 3.80 GHz,i3-10100T,Launched,Q2'20,4,8,3.00 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i5-4440 Processor 6M Cache/ up to 3.30 GHz,i5-4440,Discontinued,Q3'13,4,4,3.10 GHz,3.30 GHz,3.30 GHz
Intel® Celeron® Processor G5900T 2M Cache/ 3.20 GHz,G5900T,Launched,Q2'20,2,2,3.20 GHz,notFound,notFound
Intel® Core™ i7-980X Processor Extreme Edition 12M Cache/ 3.33 GHz/ 6.40 GT/s Intel® QPI,i7-980X,Discontinued,Q1'10,6,12,3.33 GHz,3.60 GHz,notFound
Intel® Xeon® Gold 6138P Processor 27.5M Cache/ 2.00 GHz,6138P,Launched,Q2'18,20,40,2.00 GHz,3.70 GHz,notFound
Intel® Core™ i3-6100T Processor 3M Cache/ 3.20 GHz,i3-6100T,Discontinued,Q3'15,2,4,3.20 GHz,notFound,notFound
Intel® Pentium® Processor G2030T 3M Cache/ 2.60 GHz,G2030T,Discontinued,Q2'13,2,2,2.60 GHz,notFound,notFound
Intel® Pentium® Processor G3440 3M Cache/ 3.30 GHz,G3440,Discontinued,Q2'14,2,2,3.30 GHz,notFound,notFound
Intel® Xeon® Processor E3-1275 8M Cache/ 3.40 GHz,E3-1275,Discontinued,Q2'11,4,8,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Celeron® Processor 2981U 2M Cache/ 1.60 GHz,2981U,Discontinued,Q4'13,2,2,1.60 GHz,notFound,notFound
Intel® Core™2 Duo Processor E7400 3M Cache/ 2.80 GHz/ 1066 MHz FSB,E7400,Discontinued,Q1'08,2,notFound,2.80 GHz,notFound,notFound
Intel® Quark™ SoC X1020D 16K Cache/ 400 MHz,X1020D,Discontinued,Q1'14,1,1,400 MHz,notFound,notFound
Intel Atom® Processor Z2520 1M Cache/ 1.20 GHz,Z2520,Discontinued,Q2'13,2,4,1.20 GHz,notFound,notFound
Intel® Core™ i5-661 Processor 4M Cache/ 3.33 GHz,i5-661,Discontinued,Q1'10,2,4,3.33 GHz,3.60 GHz,notFound
Intel Atom® Processor C3950 16M Cache/ up to 2.20 GHz,C3950,Launched,Q3'17,16,16,1.70 GHz,2.20 GHz,2.20 GHz
Intel® Core™ i3-4025U Processor 3M Cache/ 1.90 GHz,i3-4025U,Discontinued,Q2'14,2,4,1.90 GHz,notFound,notFound
Intel® Celeron® Processor B840 2M Cache/ 1.90 GHz,B840,Discontinued,Q3'11,2,2,1.90 GHz,notFound,notFound
Intel® Core™ i5-10600T Processor 12M Cache/ up to 4.00 GHz,i5-10600T,Launched,Q2'20,6,12,2.40 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i3-3120M Processor 3M Cache/ 2.50 GHz,i3-3120M,Discontinued,Q3'12,2,4,2.50 GHz,notFound,notFound
Intel® Core™ i7-6500U Processor 4M Cache/ up to 3.10 GHz,i7-6500U,Discontinued,Q3'15,2,4,2.50 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® E-2288G Processor 16M Cache/ 3.70 GHz,E-2288G,Launched,Q2'19,8,16,3.70 GHz,5.00 GHz,5.00 GHz
Intel® Core™ i5-4570R Processor 4M Cache/ up to 3.20 GHz,i5-4570R,Discontinued,Q2'13,4,4,2.70 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i7-11370H Processor 12M Cache/ up to 4.80 GHz/ with IPU,i7-11370H,Launched,Q1'21,4,8,notFound,4.80 GHz,notFound
Intel® Pentium® 4 Processor 662 supporting HT Technology 2M Cache/ 3.60 GHz/ 800 MHz FSB,662,Discontinued,Q4'05,1,notFound,3.60 GHz,notFound,notFound
Intel® Core™ i7-3612QM Processor 6M Cache/ up to 3.10 GHz rPGA,i7-3612QM,Discontinued,Q2'12,4,8,2.10 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Processor E3-1535M v5 8M Cache/ 2.90 GHz,E3-1535MV5,Launched,Q3'15,4,8,2.90 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i7-6770HQ Processor 6M Cache/ up to 3.50 GHz,i7-6770HQ,Discontinued,Q1'16,4,8,2.60 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i7-6770HQ Processor 6M Cache/ up to 3.50 GHz,i7-6770HQ,Discontinued,Q1'16,4,8,2.60 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i3-7350K Processor 4M Cache/ 4.20 GHz,i3-7350K,Discontinued,Q1'17,2,4,4.20 GHz,notFound,notFound
Intel® Core™ i3-1115GRE Processor 6M Cache/ up to 3.90 GHz,i3-1115GRE,Launched,Q3'20,2,4,2.20 GHz,3.90 GHz,notFound
Intel® Pentium® Processor G4560 3M Cache/ 3.50 GHz,G4560,Discontinued,Q1'17,2,4,3.50 GHz,notFound,notFound
Intel® Core™ i3-3245 Processor 3M Cache/ 3.40 GHz,i3-3245,Discontinued,Q2'13,2,4,3.40 GHz,notFound,notFound
Intel® Xeon® Processor E5430 12M Cache/ 2.66 GHz/ 1333 MHz FSB,E5430,Discontinued,Q4'07,4,notFound,2.66 GHz,notFound,notFound
Intel Atom® Processor Z550 512K Cache/ 2.00 GHz/ 533 MHz FSB,Z550,Discontinued,Q2'09,1,notFound,2.00 GHz,notFound,notFound
Intel® Pentium® 4 Processor 641 supporting HT Technology 2M Cache/ 3.20 GHz/ 800 MHz FSB,641,Discontinued,Q1'06,1,notFound,3.20 GHz,notFound,notFound
Intel® Core™ i5-6200U Processor 3M Cache/ up to 2.80 GHz,i5-6200U,Discontinued,Q3'15,2,4,2.30 GHz,2.80 GHz,2.80 GHz
Intel® Xeon® E-2254ML Processor 8M Cache/ 1.70 GHz,E-2254ML,Launched,Q2'19,4,8,1.70 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i5-4430 Processor 6M Cache/ up to 3.20 GHz,i5-4430,Discontinued,Q2'13,4,4,3.00 GHz,3.20 GHz,3.20 GHz
Intel® Celeron® Processor N4020 4M Cache/ up to 2.80 GHz,N4020,Launched,Q4'19,2,2,1.10 GHz,notFound,notFound
Intel® Xeon® W-10885M Processor 16M Cache/ up to 5.30 GHz,W-10885M,Launched,Q2'20,8,16,2.40 GHz,5.30 GHz,notFound
Intel® Xeon® Processor LV 5148 4M Cache/ 2.33 GHz/ 1333 MHz FSB,5148,Discontinued,Q2'06,2,notFound,2.33 GHz,notFound,notFound
Intel® Quark™ SoC X1021 16K Cache/ 400 MHz,X1021,Discontinued,Q2'14,1,1,400 MHz,notFound,notFound
Intel® Xeon® Gold 6230N Processor 27.5M Cache/ 2.30 GHz,6230N,Launched,Q2'19,20,40,2.30 GHz,3.50 GHz,notFound
Intel® Core™ i3-1000G1 Processor 4M Cache/ up to 3.20 GHz,i3-1000G1,Launched,Q3'19,2,4,1.10 GHz,3.20 GHz,notFound
Intel® Celeron® Processor 2961Y 2M Cache/ 1.10 GHz,2961Y,Discontinued,Q4'13,2,2,1.10 GHz,notFound,notFound
Intel® Core™ i3-9350K Processor 8M Cache/ up to 4.60 GHz,i3-9350K,Launched,Q2'19,4,4,4.00 GHz,4.60 GHz,4.60 GHz
Intel® Xeon® Processor E3-1225 6M Cache/ 3.10 GHz,E3-1225,Discontinued,Q2'11,4,4,3.10 GHz,3.40 GHz,3.40 GHz
Intel® Pentium® 4 Processor 570J supporting HT Technology 1M Cache/ 3.80 GHz/ 800 MHz FSB,570,Discontinued,Q4'04,1,notFound,3.80 GHz,notFound,notFound
Intel® Core™ i3-4030Y Processor 3M Cache/ 1.60 GHz,i3-4030Y,Discontinued,Q2'14,2,4,1.60 GHz,notFound,notFound
Intel® Core™ i5-7600K Processor 6M Cache/ up to 4.20 GHz,i5-7600K,Discontinued,Q1'17,4,4,3.80 GHz,4.20 GHz,4.20 GHz
Intel® Xeon® Processor E6540 18M Cache/ 2.00 GHz/ 6.40 GT/s Intel® QPI,E6540,Discontinued,Q1'10,6,12,2.00 GHz,2.27 GHz,notFound
Intel® Xeon® W-2145 Processor 11M Cache/ 3.70 GHz,W-2145,Launched,Q3'17,8,16,3.70 GHz,4.50 GHz,notFound
Intel Atom® x7-Z8700 Processor 2M Cache/ up to 2.40 GHz,x7-Z8700,Launched,Q1'15,4,notFound,1.60 GHz,notFound,notFound
Intel® Celeron® Processor 560 1M Cache/ 2.13 GHz/ 533 MHz FSB,560,Discontinued,Q1'08,1,notFound,2.13 GHz,notFound,notFound
Intel® Xeon® Processor E7-8890 v2 37.5M Cache/ 2.80 GHz,E7-8890V2,Discontinued,Q1'14,15,30,2.80 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® Processor E3-1585L v5 8M Cache/ 3.00 GHz,E3-1585LV5,Launched,Q2'16,4,8,3.00 GHz,3.70 GHz,3.70 GHz
Intel® Pentium® Gold G5500 Processor 4M Cache/ 3.80 GHz,G5500,Discontinued,Q2'18,2,4,3.80 GHz,notFound,notFound
Intel® Xeon® Gold 5220 Processor 24.75M Cache/ 2.20 GHz,5220,Launched,Q2'19,18,36,2.20 GHz,3.90 GHz,notFound
Intel® Xeon® Processor W3565 8M Cache/ 3.20 GHz/ 4.80 GT/s Intel® QPI,W3565,Discontinued,Q4'09,4,8,3.20 GHz,3.46 GHz,notFound
Intel® Celeron® Processor N5105 4M Cache/ up to 2.90 GHz,N5105,Launched,Q1'21,4,4,2.00 GHz,notFound,notFound
Intel® Core™ i7-680UM Processor 4M Cache/ 1.46 GHz,i7-680UM,Discontinued,Q3'10,2,4,1.46 GHz,2.53 GHz,notFound
Intel® Xeon® Gold 6134 Processor 24.75M Cache/ 3.20 GHz,6134,Launched,Q3'17,8,16,3.20 GHz,3.70 GHz,notFound
Intel® Core™ i9-11980HK Processor 24M Cache/ up to 5.00 GHz,i9-11980HK,Launched,Q2'21,8,16,notFound,5.00 GHz,notFound
Intel® Celeron® 6305 Processor 4M Cache/ 1.80 GHz/ with IPU,6305,Launched,Q4'20,2,2,notFound,notFound,notFound
Intel Atom® Processor S1240 1M Cache/ 1.60 GHz,S1240,Discontinued,Q4'12,2,4,1.60 GHz,notFound,notFound
Intel® Xeon® Gold 6262V Processor 33M Cache/ 1.90 GHz,6262V,Launched,Q2'19,24,48,1.90 GHz,3.60 GHz,notFound
Intel® Xeon® Processor E5-2609 10M Cache/ 2.40 GHz/ 6.40 GT/s Intel® QPI,E5-2609,Discontinued,Q1'12,4,4,2.40 GHz,notFound,notFound
Intel® Xeon® Gold 6138F Processor 27.5M Cache/ 2.00 GHz,6138F,Discontinued,Q3'17,20,40,2.00 GHz,3.70 GHz,notFound
Intel® Core™ i7-7820EQ Processor 8M Cache/ up to 3.70 GHz,i7-7820EQ,Launched,Q1'17,4,8,3.00 GHz,3.70 GHz,3.70 GHz
Intel Atom® Processor C2508 2M Cache/ 1.25 GHz,C2508,Launched,Q2'14,4,4,1.25 GHz,notFound,notFound
Intel® Core™ i3-7100U Processor 3M Cache/ 2.40 GHz,i3-7100U,Launched,Q3'16,2,4,2.40 GHz,notFound,notFound
Intel® Core™ i3-7100U Processor 3M Cache/ 2.40 GHz,i3-7100U,Launched,Q3'16,2,4,2.40 GHz,notFound,notFound
Intel® Core™ i7-4850HQ Processor 6M Cache/ up to 3.50 GHz,i7-4850HQ,Discontinued,Q3'13,4,8,2.30 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i7-2600 Processor 8M Cache/ up to 3.80 GHz,i7-2600,Discontinued,Q1'11,4,8,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Processor E3-1240 v3 8M Cache/ 3.40 GHz,E3-1240 v3,Discontinued,Q2'13,4,8,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Processor E3-1290 8M Cache/ 3.60 GHz,E3-1290,Discontinued,Q3'11,4,8,3.60 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i5-430M Processor 3M Cache/ 2.26 GHz,i5-430M,Discontinued,Q1'10,2,4,2.26 GHz,2.53 GHz,notFound
Intel® Core™ Duo Processor U2500 2M Cache/ 1.20 GHz/ 533 MHz FSB,U2500,Discontinued,Q1'06,2,notFound,1.20 GHz,notFound,notFound
Intel® Xeon® Processor E5-2640 v2 20M Cache/ 2.00 GHz,E5-2640V2,Discontinued,Q3'13,8,16,2.00 GHz,2.50 GHz,2.50 GHz
Intel® Core™ i5-8279U Processor 6M Cache/ up to 4.10 GHz,i5-8279U,Launched,Q2'19,4,8,2.40 GHz,4.10 GHz,4.10 GHz
Intel® Core™ i5-3340M Processor 3M Cache/ up to 3.40 GHz,i5-3340M,Discontinued,Q1'13,2,4,2.70 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® E-2174G Processor 8M Cache/ up to 4.70 GHz,E-2174G,Launched,Q3'18,4,8,3.80 GHz,4.70 GHz,4.70 GHz
Intel® Core™ i7-9700T Processor 12M Cache/ up to 4.30 GHz,i7-9700T,Launched,Q2'19,8,8,2.00 GHz,4.30 GHz,4.30 GHz
Intel® Core™ i5-8500T Processor 9M Cache/ up to 3.50 GHz,i5-8500T,Launched,Q2'18,6,6,2.10 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® E-2126G Processor 12M Cache/ up to 4.50 GHz,E-2126G,Launched,Q3'18,6,6,3.30 GHz,4.50 GHz,4.50 GHz
Intel® Xeon® Processor E5-2603 v3 15M Cache/ 1.60 GHz,E5-2603V3,Discontinued,Q3'14,6,6,1.60 GHz,notFound,notFound
Intel® Core™ i3-10100E Processor 6M Cache/ up to 3.80 GHz,i3-10100E,Launched,Q2'20,4,8,3.20 GHz,3.80 GHz,3.80 GHz
Intel® Celeron® Processor 927UE 1M Cache/ 1.50 GHz,927UE,Launched,Q1'13,1,1,1.50 GHz,notFound,notFound
Intel® Xeon® Processor E7-8893 v2 37.5M Cache/ 3.40 GHz,E7-8893V2,Launched,Q1'14,6,12,3.40 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® Processor E3-1220 v3 8M Cache/ 3.10 GHz,E3-1220 v3,Launched,Q2'13,4,4,3.10 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i7-2600K Processor 8M Cache/ up to 3.80 GHz,i7-2600K,Discontinued,Q1'11,4,8,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i7-3940XM Processor Extreme Edition 8M Cache/ up to 3.90 GHz,i7-3940XM,Discontinued,Q3'12,4,8,3.00 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor W3540 8M Cache/ 2.93 GHz/ 4.80 GT/s Intel® QPI,W3540,Discontinued,Q1'09,4,8,2.93 GHz,3.20 GHz,notFound
Intel® Core™ i5-4460T Processor 6M Cache/ up to 2.70 GHz,i5-4460T,Discontinued,Q2'14,4,4,1.90 GHz,2.70 GHz,2.70 GHz
Intel® Core™ i5-3437U Processor 3M Cache/ up to 2.90 GHz,i5-3437U,Discontinued,Q1'13,2,4,1.90 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i5-10500TE Processor 12M Cache/ up to 3.70 GHz,i5-10500TE,Launched,Q2'20,6,12,2.30 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® Processor L5318 8M Cache/ 1.60 GHz/ 1066 MHz FSB,L5318,Discontinued,Q1'07,4,notFound,1.60 GHz,notFound,notFound
Intel® Celeron® Processor N2930 2M Cache/ up to 2.16 GHz,N2930,Launched,Q1'14,4,4,1.83 GHz,notFound,notFound
Intel® Core™ i9-12900KF Processor 30M Cache/ up to 5.20 GHz,i9-12900KF,Launched,Q4'21,16,24,notFound,5.20 GHz,notFound
Intel® Xeon® Processor X3220 8M Cache/ 2.40 GHz/ 1066 MHz FSB,X3220,Discontinued,Q1'07,4,notFound,2.40 GHz,notFound,notFound
Intel® Xeon® Processor E5-2650 v2 20M Cache/ 2.60 GHz,E5-2650V2,Discontinued,Q3'13,8,16,2.60 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i7-4960HQ Processor 6M Cache/ up to 3.80 GHz,i7-4960HQ,Discontinued,Q4'13,4,8,2.60 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i5-5575R Processor 4M Cache/ up to 3.30 GHz,i5-5575R,Discontinued,Q2'15,4,notFound,2.80 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® Gold 6130F Processor 22M Cache/ 2.10 GHz,6130F,Launched,Q3'17,16,32,2.10 GHz,3.70 GHz,notFound
Intel® Core™2 Extreme Processor QX9775 12M Cache/ 3.20 GHz/ 1600 MHz FSB,QX9775,Discontinued,Q1'08,4,notFound,3.20 GHz,notFound,notFound
Intel® Core™ i7-7700K Processor 8M Cache/ up to 4.50 GHz,i7-7700K,Discontinued,Q1'17,4,8,4.20 GHz,4.50 GHz,4.50 GHz
Intel® Xeon® E-2244G Processor 8M Cache/ 3.80 GHz,E-2244G,Launched,Q2'19,4,8,3.80 GHz,4.80 GHz,4.80 GHz
Intel® Xeon® E-2186G Processor 12M Cache/ up to 4.70 GHz,E-2186G,Launched,Q3'18,6,12,3.80 GHz,4.70 GHz,4.70 GHz
Intel® Xeon® Processor E5-2630L 15M Cache/ 2.00 GHz/ 7.20 GT/s Intel® QPI,E5-2630L,Discontinued,Q1'12,6,12,2.00 GHz,2.50 GHz,2.50 GHz
Intel® Core™ i3-3225 Processor 3M Cache/ 3.30 GHz,i3-3225,Discontinued,Q3'12,2,4,3.30 GHz,notFound,notFound
Intel® Pentium® Processor Extreme Edition 965 4M Cache/ 3.73 GHz/ 1066 MHz FSB,965,Discontinued,Q1'06,2,notFound,3.73 GHz,notFound,notFound
Intel® Celeron® Processor N4500 4M Cache/ up to 2.80 GHz,N4500,Launched,Q1'21,2,2,1.10 GHz,notFound,notFound
Intel® Core™ i7-5550U Processor 4M Cache/ up to 3.00 GHz,i7-5550U,Discontinued,Q1'15,2,4,2.00 GHz,3.00 GHz,3.00 GHz
Intel® Xeon® Processor E7-8880L v2 37.5M Cache/ 2.20 GHz,E7-8880LV2,Launched,Q1'14,15,30,2.20 GHz,2.80 GHz,2.80 GHz
Intel® Core™ i7-8700T Processor 12M Cache/ up to 4.00 GHz,i7-8700T,Launched,Q2'18,6,12,2.40 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i7-8565U Processor 8M Cache/ up to 4.60 GHz,i7-8565U,Launched,Q3'18,4,8,1.80 GHz,4.60 GHz,notFound
Intel® Core™ i7-8565U Processor 8M Cache/ up to 4.60 GHz,i7-8565U,Launched,Q3'18,4,8,1.80 GHz,4.60 GHz,notFound
Intel® Core™ i7-8850H Processor 9M Cache/ up to 4.30 GHz,i7-8850H,Launched,Q2'18,6,12,2.60 GHz,4.30 GHz,4.30 GHz
Intel® Core™ i5-580M Processor 3M Cache/ 2.66 GHz,i5-580M,Discontinued,Q3'10,2,4,2.66 GHz,3.33 GHz,notFound
Intel® Core™ i5-4210H Processor 3M Cache/ up to 3.50 GHz,i5-4210H,Discontinued,Q3'14,2,4,2.90 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i5-5350H Processor 4M Cache/ up to 3.50 GHz,i5-5350H,Discontinued,Q2'15,2,4,3.10 GHz,3.50 GHz,3.50 GHz
Intel® Core™2 Duo Processor E6400 2M Cache/ 2.13 GHz/ 1066 MHz FSB,E6400,Discontinued,Q3'06,2,notFound,2.13 GHz,notFound,notFound
Intel® Xeon® Processor L7445 12M Cache/ 2.13 GHz/ 1066 MHz FSB,L7445,Discontinued,Q3'08,4,notFound,2.13 GHz,notFound,notFound
Intel® Xeon® Processor X3210 8M Cache/ 2.13 GHz/ 1066 MHz FSB,X3210,Discontinued,Q1'07,4,notFound,2.13 GHz,notFound,notFound
Intel® Pentium® Processor N3530 2M Cache/ up to 2.58 GHz,N3530,Discontinued,Q1'14,4,4,2.16 GHz,notFound,notFound
Intel Atom® x5-Z8300 Processor 2M Cache/ up to 1.84 GHz,x5-Z8300,Discontinued,Q2'15,4,notFound,1.44 GHz,notFound,notFound
Intel® Core™ i5-4422E Processor 3M Cache/ up to 2.90 GHz,i5-4422E,Launched,Q2'14,2,4,1.80 GHz,2.90 GHz,2.90 GHz
Intel® Pentium® Gold G6400E Processor 4M Cache/ 3.80 GHz,G6400E,Launched,Q2'20,2,4,3.80 GHz,notFound,notFound
Intel® Core™2 Duo Processor T5800 2M Cache/ 2.00 GHz/ 800 MHz FSB,T5800,Discontinued,Q4'08,2,notFound,2.00 GHz,notFound,notFound
Intel Atom® x6425RE Processor 1.5M Cache/ 1.90 GHz,6425RE,Launched,Q1'21,4,4,1.90 GHz,notFound,notFound
Intel® Xeon® Processor E7-4890 v2 37.5M Cache/ 2.80 GHz,E7-4890V2,Discontinued,Q1'14,15,30,2.80 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i9-11900KF Processor 16M Cache/ up to 5.30 GHz,i9-11900KF,Launched,Q1'21,8,16,3.50 GHz,5.30 GHz,5.10 GHz
Intel® Core™ i7-5650U Processor 4M Cache/ up to 3.20 GHz,i7-5650U,Launched,Q1'15,2,4,2.20 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Bronze 3204 Processor 8.25M Cache/ 1.90 GHz,3204,Launched,Q2'19,6,6,1.90 GHz,1.90 GHz,notFound
Intel® Core™ i3-3210 Processor 3M Cache/ 3.20 GHz,i3-3210,Discontinued,Q1'13,2,4,3.20 GHz,notFound,notFound
Intel® Core™ i5-4300Y Processor 3M Cache/ up to 2.30 GHz,i5-4300Y,Discontinued,Q3'13,2,4,1.60 GHz,2.30 GHz,2.30 GHz
Intel® Core™ i7-9750HF Processor 12M Cache/ up to 4.50 GHz,i7-9750HF,Launched,Q2'19,6,12,2.60 GHz,4.50 GHz,notFound
Intel® Xeon® Processor L5408 12M Cache/ 2.13 GHz/ 1066 MHz FSB,L5408,Discontinued,Q1'08,4,notFound,2.13 GHz,notFound,notFound
Intel® Core™ i3-1000G4 Processor 4M Cache/ up to 3.20 GHz,i3-1000G4,Launched,Q3'19,2,4,1.10 GHz,3.20 GHz,notFound
Intel® Xeon® Gold 6254 Processor 24.75M Cache/ 3.10 GHz,6254,Launched,Q2'19,18,36,3.10 GHz,4.00 GHz,notFound
Intel® Core™ i5-4430S Processor 6M Cache/ up to 3.20 GHz,i5-4430S,Discontinued,Q2'13,4,4,2.70 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® W-10855M Processor 12M Cache/ up to 5.10 GHz,W-10855M,Launched,Q2'20,6,12,2.80 GHz,5.10 GHz,notFound
Intel® Xeon® Processor E3-1230 8M Cache/ 3.20 GHz,E3-1230,Discontinued,Q2'11,4,8,3.20 GHz,3.60 GHz,3.60 GHz
Intel® Core™2 Duo Processor P7450 3M Cache/ 2.13 GHz/ 1066 MHz FSB,P7450,Discontinued,Q1'09,2,notFound,2.13 GHz,notFound,notFound
Intel® Pentium® 4 Processor 561 supporting HT Technology 1M Cache/ 3.60 GHz/ 800 MHz FSB,561,Discontinued,Q3'05,1,notFound,3.60 GHz,notFound,notFound
Intel® Celeron® Processor 2957U 2M Cache/ 1.40 GHz,2957U,Discontinued,Q4'13,2,2,1.40 GHz,notFound,notFound
Intel Atom® Processor Z515 512K Cache/ 1.20 GHz/ 400 MHz FSB,Z515,Discontinued,Q2'09,1,notFound,1.20 GHz,notFound,notFound
Intel® Pentium® 4 Processor 640 supporting HT Technology 2M Cache/ 3.20 GHz/ 800 MHz FSB,640,Discontinued,Q1'05,1,notFound,3.20 GHz,notFound,notFound
Intel® Pentium® Processor G2140 3M Cache/ 3.30 GHz,G2140,Discontinued,Q2'13,2,2,3.30 GHz,notFound,notFound
Intel® Xeon® Processor E5410 12M Cache/ 2.33 GHz/ 1333 MHz FSB,E5410,Discontinued,Q4'07,4,notFound,2.33 GHz,notFound,notFound
Intel® Core™ i7-6600U Processor 4M Cache/ up to 3.40 GHz,i7-6600U,Launched,Q3'15,2,4,2.60 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® E-2278G Processor 16M Cache/ 3.40 GHz,E-2278G,Launched,Q2'19,8,16,3.40 GHz,5.00 GHz,5.00 GHz
Intel Atom® x5-Z8500 Processor 2M Cache/ up to 2.24 GHz,x5-Z8500,Launched,Q1'15,4,notFound,1.44 GHz,notFound,notFound
Intel® Celeron® 6305E Processor 4M Cache/ 1.80 GHz,6305E,Launched,Q4'20,2,2,1.80 GHz,notFound,notFound
Intel® Core™ i5-4220Y Processor 3M Cache/ up to 2.00 GHz,i5-4220Y,Discontinued,Q2'14,2,4,1.60 GHz,2.00 GHz,2.00 GHz
Intel® Core™2 Duo Processor E7200 3M Cache/ 2.53 GHz/ 1066 MHz FSB,E7200,Discontinued,Q2'08,2,notFound,2.53 GHz,notFound,notFound
Intel® Xeon® Processor E6510 12M Cache/ 1.73 GHz/ 4.80 GT/s Intel® QPI,E6510,Discontinued,Q1'10,4,8,1.73 GHz,1.73 GHz,notFound
Intel® Core™ i7-6900K Processor 20M Cache/ up to 3.70 GHz,i7-6900K,Discontinued,Q2'16,8,16,3.20 GHz,3.70 GHz,notFound
Intel® Core™ i5-10400F Processor 12M Cache/ up to 4.30 GHz,i5-10400F,Launched,Q2'20,6,12,2.90 GHz,4.30 GHz,4.30 GHz
Intel® Core™ i7-6700K Processor 8M Cache/ up to 4.20 GHz,i7-6700K,Discontinued,Q3'15,4,8,4.00 GHz,4.20 GHz,4.20 GHz
Intel® Xeon® E-2276ME Processor 12M Cache/ 2.80 GHz,E-2276ME,Launched,Q2'19,6,12,2.80 GHz,4.50 GHz,4.50 GHz
Intel® Core™ i5-4670R Processor 4M Cache/ up to 3.70 GHz,i5-4670R,Discontinued,Q2'13,4,4,3.00 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i3-4030U Processor 3M Cache/ 1.90 GHz,i3-4030U,Discontinued,Q2'14,2,4,1.90 GHz,notFound,notFound
Intel® Xeon® Processor X5460 12M Cache/ 3.16 GHz/ 1333 MHz FSB,X5460,Discontinued,Q4'07,4,notFound,3.16 GHz,notFound,notFound
Intel® Pentium® Processor 4405U 2M Cache/ 2.10 GHz,4405U,Discontinued,Q3'15,2,4,2.10 GHz,notFound,notFound
Intel® Pentium® 4 Processor 670 supporting HT Technology 2M Cache/ 3.80 GHz/ 800 MHz FSB,670,Discontinued,Q2'05,1,notFound,3.80 GHz,notFound,notFound
Intel® Pentium® Processor 3558U 2M Cache/ 1.70 GHz,3558U,Discontinued,Q4'13,2,2,1.70 GHz,notFound,notFound
Intel® Xeon® Processor E3-1270 8M Cache/ 3.40 GHz,E3-1270,Discontinued,Q2'11,4,8,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i5-4260U Processor 3M Cache/ up to 2.70 GHz,i5-4260U,Discontinued,Q2'14,2,4,1.40 GHz,2.70 GHz,2.70 GHz
Intel® Quark™ SoC X1011 16K Cache/ 400 MHz,X1011,Discontinued,Q2'14,1,1,400 MHz,notFound,notFound
Intel® Celeron® Processor 900 1M Cache/ 2.20 GHz/ 800 MHz FSB,900,Discontinued,Q1'09,1,notFound,2.20 GHz,notFound,notFound
Intel® Core™ i5-1145G7E Processor 8M Cache/ up to 4.10 GHz,i5-1145G7E,Launched,Q3'20,4,8,1.50 GHz,4.10 GHz,notFound
Intel® Core™ i5-6440HQ Processor 6M Cache/ up to 3.50 GHz,i5-6440HQ,Discontinued,Q3'15,4,4,2.60 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i7-6870HQ Processor 8M Cache/ up to 3.60 GHz,i7-6870HQ,Discontinued,Q1'16,4,8,2.70 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i5-520UM Processor 3M Cache/ 1.06 GHz,i5-520UM,Discontinued,Q1'10,2,4,1.07 GHz,1.87 GHz,notFound
Intel® Pentium® Processor B960 2M Cache/ 2.20 GHz,B960,Discontinued,Q4'11,2,2,2.20 GHz,notFound,notFound
Intel® Xeon® Gold 6250L Processor 35.75M Cache/ 3.90 GHz,6250L,Launched,Q1'20,8,16,3.90 GHz,4.50 GHz,notFound
Intel® Xeon® W-2125 Processor 8.25M Cache/ 4.00 GHz,W-2125,Launched,Q3'17,4,8,4.00 GHz,4.50 GHz,notFound
Intel® Core™ i3-530 Processor 4M Cache/ 2.93 GHz,i3-530,Discontinued,Q1'10,2,4,2.93 GHz,notFound,notFound
Intel® Xeon® Processor E3-1245 v3 8M Cache/ 3.40 GHz,E3-1245 v3,Discontinued,Q2'13,4,8,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i7-8500Y Processor 4M Cache/ up to 4.20 GHz,i7-8500Y,Launched,Q1'19,2,4,1.50 GHz,4.20 GHz,4.20 GHz
Intel® Core™ i5-10400 Processor 12M Cache/ up to 4.30 GHz,i5-10400,Launched,Q2'20,6,12,2.90 GHz,4.30 GHz,4.30 GHz
Intel® Core™ i7-970 Processor 12M Cache/ 3.20 GHz/ 4.80 GT/s Intel® QPI,i7-970,Discontinued,Q3'10,6,12,3.20 GHz,3.46 GHz,notFound
Intel® Pentium® Processor G3440T 3M Cache/ 2.80 GHz,G3440T,Discontinued,Q2'14,2,2,2.80 GHz,notFound,notFound
Intel® Core™ i5-3470 Processor 6M Cache/ up to 3.60 GHz,i5-3470,Discontinued,Q2'12,4,4,3.20 GHz,3.60 GHz,3.60 GHz
Intel® Pentium® Processor G2030 3M Cache/ 3.00 GHz,G2030,Discontinued,Q2'13,2,2,3.00 GHz,notFound,notFound
Intel® Xeon® Processor D-1513N 6M Cache/ 1.60 GHz,D-1513N,Launched,Q3'17,4,8,1.60 GHz,2.20 GHz,2.20 GHz
Intel® Core™ i5-5300U Processor 3M Cache/ up to 2.90 GHz,i5-5300U,Discontinued,Q1'15,2,4,2.30 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i5-5300U Processor 3M Cache/ up to 2.90 GHz,i5-5300U,Discontinued,Q1'15,2,4,2.30 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i3-3115C Processor 4M Cache/ 2.50 GHz,i3-3115C,Launched,Q3'13,2,4,2.50 GHz,notFound,notFound
Intel® Xeon® Processor E3-1225 v5 8M Cache/ 3.30 GHz,E3-1225V5,Launched,Q4'15,4,4,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Pentium® Gold G6600 Processor 4M Cache/ 4.20 GHz,G6600,Launched,Q2'20,2,4,4.20 GHz,notFound,notFound
Intel® Core™ i9-10910 Processor 20M Cache/ up to 5.00 GHz,i9-10910,Launched,Q3'20,10,20,3.60 GHz,5.00 GHz,5.00 GHz
Intel® Xeon® Processor E3-1285 v3 8M Cache/ 3.60 GHz,E3-1285 v3,Discontinued,Q2'13,4,8,3.60 GHz,4.00 GHz,4.00 GHz
Intel Atom® Processor N2800 1M Cache/ 1.86 GHz,N2800,Discontinued,Q4'11,2,4,1.86 GHz,notFound,notFound
Intel® Xeon® Platinum 8256 Processor 16.5M Cache/ 3.80 GHz,8256,Launched,Q2'19,4,8,3.80 GHz,3.90 GHz,notFound
Intel® Pentium® Processor 2129Y 2M Cache/ 1.10 GHz,2129Y,Discontinued,Q1'13,2,2,1.10 GHz,notFound,notFound
Intel® Core™ i7-640LM Processor 4M Cache/ 2.13 GHz,i7-640LM,Discontinued,Q1'10,2,4,2.13 GHz,2.93 GHz,notFound
Intel® Core™ i5-12400T Processor 18M Cache/ up to 4.20 GHz,i5-12400T,Launched,Q1'22,6,12,notFound,4.20 GHz,notFound
Intel® Core™ i5-7267U Processor 4M Cache/ up to 3.50 GHz,i5-7267U,Discontinued,Q1'17,2,4,3.10 GHz,3.50 GHz,3.50 GHz
Intel® Core™2 Duo Processor T6500 2M Cache/ 2.10 GHz/ 800 MHz FSB,T6500,Discontinued,Q2'09,2,notFound,2.10 GHz,notFound,notFound
Intel® Core™ i5-4200Y Processor 3M Cache/ up to 1.90 GHz,i5-4200Y,Discontinued,Q3'13,2,4,1.40 GHz,1.90 GHz,1.90 GHz
Intel® Core™ i3-10300T Processor 8M Cache/ up to 3.90 GHz,i3-10300T,Launched,Q2'20,4,8,3.00 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i3-4330 Processor 4M Cache/ 3.50 GHz,i3-4330,Launched,Q3'13,2,4,3.50 GHz,notFound,notFound
Intel® Pentium® Gold G6405 Processor 4M Cache/ 4.10 GHz,G6405,Launched,Q1'21,2,4,4.10 GHz,notFound,notFound
Intel® Xeon® Processor E3-1280 8M Cache/ 3.50 GHz,E3-1280,Discontinued,Q2'11,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i7-5500U Processor 4M Cache/ up to 3.00 GHz,i7-5500U,Discontinued,Q1'15,2,4,2.40 GHz,3.00 GHz,3.00 GHz
Intel® Celeron® Processor N2815 1M Cache/ up to 2.13 GHz,N2815,Discontinued,Q4'13,2,2,1.86 GHz,notFound,notFound
Intel® Pentium® Processor G4520 3M Cache/ 3.60 GHz,G4520,Discontinued,Q3'15,2,2,3.60 GHz,notFound,notFound
Intel® Pentium® Processor G3450 3M Cache/ 3.40 GHz,G3450,Discontinued,Q2'14,2,2,3.40 GHz,notFound,notFound
Intel® Core™ i5-10400T Processor 12M Cache/ up to 3.60 GHz,i5-10400T,Launched,Q2'20,6,12,2.00 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i3-330E Processor 3M Cache/ 2.13 GHz,i3-330E,Discontinued,Q1'10,2,4,2.13 GHz,notFound,notFound
Intel® Core™ i7-620LE Processor 4M Cache/ 2.00 GHz,i7-620LE,Discontinued,Q1'10,2,4,2.00 GHz,2.80 GHz,notFound
Intel® Core™ i5-4210U Processor 3M Cache/ up to 2.70 GHz,i5-4210U,Discontinued,Q2'14,2,4,1.70 GHz,2.70 GHz,2.70 GHz
Intel® Core™ i9-9900KF Processor 16M Cache/ up to 5.00 GHz,i9-9900KF,Launched,Q1'19,8,16,3.60 GHz,5.00 GHz,5.00 GHz
Intel® Celeron® Processor G5925 4M Cache/ 3.60 GHz,G5925,Launched,Q3'20,2,2,3.60 GHz,notFound,notFound
Intel® Celeron® Processor 5205U 2M Cache/ 1.90 GHz,5205U,Launched,Q4'19,2,2,1.90 GHz,notFound,notFound
Intel Atom® Processor Z3530 2M Cache/ up to 1.33 GHz,Z3530,Discontinued,Q2'14,4,notFound,notFound,notFound,notFound
Intel® Pentium® Processor G4560T 3M Cache/ 2.90 GHz,G4560T,Discontinued,Q1'17,2,4,2.90 GHz,notFound,notFound
Intel® Xeon® Processor X3360 12M Cache/ 2.83 GHz/ 1333 MHz FSB,X3360,Discontinued,Q1'08,4,notFound,2.83 GHz,notFound,notFound
Intel® Xeon® Processor E5-2683 v4 40M Cache/ 2.10 GHz,E5-2683V4,Launched,Q1'16,16,32,2.10 GHz,3.00 GHz,3.00 GHz
Intel® Xeon® Gold 6330 Processor 42M Cache/ 2.00 GHz,6330,Launched,Q2'21,28,56,2.00 GHz,3.10 GHz,notFound
Intel Atom® Processor Z3745 2M Cache/ up to 1.86 GHz,Z3745,Discontinued,Q1'14,4,notFound,1.33 GHz,notFound,notFound
Intel® Xeon® W-2275 Processor 19.25M Cache/ 3.30 GHz,W-2275,Launched,Q4'19,14,28,3.30 GHz,4.60 GHz,notFound
Intel® Xeon® Processor E5-2418L 10M/ 2.0 GHz/ 6.4 GT/s Intel® QPI,E5-2418L,Launched,Q2'12,4,8,2.00 GHz,2.10 GHz,2.10 GHz
Intel® Core™ i3-8350K Processor 8M Cache/ 4.00 GHz,i3-8350K,Discontinued,Q4'17,4,4,4.00 GHz,notFound,notFound
Intel® Xeon® Processor E5507 4M Cache/ 2.26 GHz/ 4.80 GT/s Intel® QPI,E5507,Discontinued,Q1'10,4,4,2.26 GHz,notFound,notFound
Intel® Core™ i5-2310 Processor 6M Cache/ up to 3.20 GHz,i5-2310,Discontinued,Q2'11,4,4,2.90 GHz,3.20 GHz,3.20 GHz
Intel® Celeron® Processor J1850 2M Cache/ 2.00 GHz,J1850,Discontinued,Q3'13,4,4,2.00 GHz,notFound,notFound
Intel® Xeon® Processor E7-8830 24M Cache/ 2.13 GHz/ 6.40 GT/s Intel® QPI,E7-8830,Discontinued,Q2'11,8,16,2.13 GHz,2.40 GHz,notFound
Intel Atom® Processor Z520PT 512K Cache/ 1.33 GHz/ 533 MHz FSB,Z520PT,Discontinued,Q2'08,1,notFound,1.33 GHz,notFound,notFound
Intel® Celeron® Processor N3150 2M Cache/ up to 2.08 GHz,N3150,Discontinued,Q1'15,4,4,1.60 GHz,notFound,notFound
Intel® Core™ i5-3230M Processor 3M Cache/ up to 3.20 GHz rPGA,i5-3230M,Discontinued,Q1'13,2,4,2.60 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Processor E5-2648L v4 35M Cache/ 1.80 GHz,E5-2648LV4,Launched,Q1'16,14,28,1.80 GHz,2.50 GHz,2.50 GHz
Intel® Core™ i9-10980XE Extreme Edition Processor 24.75M Cache/ 3.00 GHz,i9-10980XE,Launched,Q4'19,18,36,3.00 GHz,4.60 GHz,notFound
Intel® Celeron® Processor J3355 2M Cache/ up to 2.50 GHz,J3355,Launched,Q3'16,2,2,2.00 GHz,notFound,notFound
Intel® Core™ i7-7820HQ Processor 8M Cache/ up to 3.90 GHz,i7-7820HQ,Launched,Q1'17,4,8,2.90 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor E7210 8M Cache/ 2.40 GHz/ 1066 MHz FSB,E7210,Discontinued,Q3'07,2,notFound,2.40 GHz,notFound,notFound
Intel® Core™ i7-7920HQ Processor 8M Cache/ up to 4.10 GHz,i7-7920HQ,Launched,Q1'17,4,8,3.10 GHz,4.10 GHz,4.10 GHz
Intel® Xeon® Gold 6354 Processor 39M Cache/ 3.00 GHz,6354,Launched,Q2'21,18,36,3.00 GHz,3.60 GHz,notFound
Intel Atom® Processor Z530P 512K Cache/ 1.60 GHz/ 533 MHz FSB,Z530P,Discontinued,Q2'08,1,notFound,1.60 GHz,notFound,notFound
Intel® Core™ i3-2370M Processor 3M Cache/ 2.40 GHz,i3-2370M,Discontinued,Q1'12,2,4,2.40 GHz,notFound,notFound
Intel® Core™ i9-9900KS Processor 16M Cache/ up to 5.00 GHz,i9-9900KS,Discontinued,Q4'19,8,16,4.00 GHz,5.00 GHz,5.00 GHz
Intel® Celeron® Processor N4100 4M Cache/ up to 2.40 GHz,N4100,Launched,Q4'17,4,4,1.10 GHz,notFound,notFound
Intel® Core™ i7-10700K Processor 16M Cache/ up to 5.10 GHz,i7-10700K,Launched,Q2'20,8,16,3.80 GHz,5.10 GHz,5.00 GHz
Intel® Core™ i3-7167U Processor 3M Cache/ 2.80 GHz,i3-7167U,Launched,Q1'17,2,4,2.80 GHz,notFound,notFound
Intel® Core™ i5-8400 Processor 9M Cache/ up to 4.00 GHz,i5-8400,Discontinued,Q4'17,6,6,2.80 GHz,4.00 GHz,4.00 GHz
Intel® Xeon® Gold 6348 Processor 42M Cache/ 2.60 GHz,6348,Launched,Q2'21,28,56,2.60 GHz,3.50 GHz,notFound
Intel® Pentium® Processor G620 3M Cache/ 2.60 GHz,G620,Discontinued,Q2'11,2,2,2.60 GHz,notFound,notFound
Intel® Core™2 Duo Processor E6750 4M Cache/ 2.66 GHz/ 1333 MHz FSB,E6750,Discontinued,Q3'07,2,notFound,2.66 GHz,notFound,notFound
Intel® Xeon® Processor E5-2697A v4 40M Cache/ 2.60 GHz,E5-2697AV4,Launched,Q1'16,16,32,2.60 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i3-10325 Processor 8M Cache/ up to 4.70 GHz,i3-10325,Launched,Q1'21,4,8,3.90 GHz,4.70 GHz,4.70 GHz
Intel® Core™ i7-2760QM Processor 6M Cache/ up to 3.50 GHz,i7-2760QM,Discontinued,Q4'11,4,8,2.40 GHz,3.50 GHz,3.50 GHz
Intel® Pentium® Processor G4600 3M Cache/ 3.60 GHz,G4600,Discontinued,Q1'17,2,4,3.60 GHz,notFound,notFound
Intel® Xeon® Processor E5-2628L v3 25M Cache/ 2.00 GHz,E5-2628LV3,Launched,Q3'14,10,20,2.00 GHz,2.50 GHz,2.50 GHz
Intel Atom® Processor Z2460 512K Cache/ up to 1.60 GHz,Z2460,Discontinued,Q2'12,1,2,notFound,notFound,notFound
Intel® Core™ i9-10900K Processor 20M Cache/ up to 5.30 GHz,i9-10900K,Launched,Q2'20,10,20,3.70 GHz,5.30 GHz,5.10 GHz
Intel® Xeon® Processor X5560 8M Cache/ 2.80 GHz/ 6.40 GT/s Intel® QPI,X5560,Discontinued,Q1'09,4,8,2.80 GHz,3.20 GHz,notFound
Intel® Pentium® Silver J5005 Processor 4M Cache/ up to 2.80 GHz,J5005,Launched,Q4'17,4,4,1.50 GHz,notFound,notFound
Intel® Xeon® Silver 4114 Processor 13.75M Cache/ 2.20 GHz,4114,Launched,Q3'17,10,20,2.20 GHz,3.00 GHz,notFound
Intel® Pentium® Processor G3258 3M Cache/ 3.20 GHz,G3258,Discontinued,Q2'14,2,2,3.20 GHz,notFound,notFound
Intel® Xeon® Processor E5-2687W v4 30M Cache/ 3.00 GHz,E5-2687WV4,Launched,Q1'16,12,24,3.00 GHz,3.50 GHz,3.50 GHz
Intel® Pentium® Processor 3825U 2M Cache/ 1.90 GHz,3825U,Discontinued,Q1'15,2,4,1.90 GHz,notFound,notFound
Intel® Xeon® Processor E5-4624L v2 25M Cache/ 1.90 GHz,E5-4624LV2,Launched,Q1'14,10,20,1.90 GHz,2.50 GHz,2.50 GHz
Intel® Core™2 Duo Processor E6550 4M Cache/ 2.33 GHz/ 1333 MHz FSB,E6550,Discontinued,Q3'07,2,notFound,2.33 GHz,notFound,notFound
Intel® Xeon® Processor E7-8867 v4 45M Cache/ 2.40 GHz,E7-8867V4,Launched,Q2'16,18,36,2.40 GHz,3.30 GHz,3.30 GHz
Intel® Celeron® Processor 827E 1.5M Cache/ 1.40 GHz,827E,Discontinued,Q3'11,1,1,1.40 GHz,notFound,notFound
Intel® Core™ i9-10900X X-series Processor 19.25M Cache/ 3.70 GHz,i9-10900X,Launched,Q4'19,10,20,3.70 GHz,4.50 GHz,notFound
Intel® Pentium® Processor G640T 3M Cache/ 2.40 GHz,G640T,Discontinued,Q2'12,2,2,2.40 GHz,notFound,notFound
Intel® Celeron® Processor U3600 2M Cache/ 1.20 GHz,U3600,Discontinued,Q1'11,2,2,1.20 GHz,notFound,notFound
Intel® Core™ i5-11320H Processor 8M Cache/ up to 4.50 GHz/ with IPU,i5-11320H,Launched,Q2'21,4,8,notFound,4.50 GHz,notFound
Intel Atom® Processor Z3770 2M Cache/ up to 2.39 GHz,Z3770,Discontinued,Q3'13,4,notFound,1.46 GHz,notFound,notFound
Intel® Xeon® Processor E7-4850 v3 35M Cache/ 2.20 GHz,E7-4850V3,Launched,Q2'15,14,28,2.20 GHz,2.80 GHz,2.80 GHz
Intel® Pentium® Gold G7400E Processor 6M Cache/ 3.60 GHz,G7400E,Launched,Q1'22,2,4,notFound,notFound,notFound
Intel® Xeon® Processor D-1541 12M Cache/ 2.10 GHz,D-1541,Launched,Q4'15,8,16,2.10 GHz,2.70 GHz,2.70 GHz
Intel® Core™ i3-2120T Processor 3M Cache/ 2.60 GHz,i3-2120T,Discontinued,Q3'11,2,4,2.60 GHz,notFound,notFound
Intel Atom® Processor 230 512K Cache/ 1.60 GHz/ 533 MHz FSB,230,Discontinued,Q2'08,1,notFound,1.60 GHz,notFound,notFound
Intel® Xeon® Processor E5-2658 v3 30M Cache/ 2.20 GHz,E5-2658V3,Launched,Q3'14,12,24,2.20 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i3-4130 Processor 3M Cache/ 3.40 GHz,i3-4130,Discontinued,Q3'13,2,4,3.40 GHz,notFound,notFound
Intel® Core™ i5-3570T Processor 6M Cache/ up to 3.30 GHz,i5-3570T,Discontinued,Q2'12,4,4,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Pentium® Processor 3805U 2M Cache/ 1.90 GHz,3805U,Discontinued,Q1'15,2,2,1.90 GHz,notFound,notFound
Intel® Core™ i7-3517UE Processor 4M Cache/ up to 2.80 GHz,i7-3517UE,Launched,Q2'12,2,4,1.70 GHz,2.80 GHz,2.80 GHz
Intel® Xeon® Processor E5-2618L v4 25M Cache/ 2.20 GHz,E5-2618LV4,Launched,Q1'16,10,20,2.20 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® E-2336 Processor 12M Cache/ 2.90 GHz,E-2336,Launched,Q3'21,6,12,2.90 GHz,4.80 GHz,4.80 GHz
Intel® Core™ i7-12650H Processor 24M Cache/ up to 4.70 GHz,i7-12650H,Launched,Q1'22,10,16,notFound,notFound,notFound
Intel® Core™ i7-5775C Processor 6M Cache/ up to 3.70 GHz,i7-5775C,Discontinued,Q2'15,4,8,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® Processor X3470 8M Cache/ 2.93 GHz,X3470,Discontinued,Q3'09,4,8,2.93 GHz,3.60 GHz,notFound
Intel® Celeron® Processor G550 2M Cache/ 2.60 GHz,G550,Discontinued,Q2'12,2,2,2.60 GHz,notFound,notFound
Intel® Xeon® Processor E5-4640 v3 30M Cache/ 1.90 GHz,E5-4640V3,Discontinued,Q2'15,12,24,1.90 GHz,2.60 GHz,2.60 GHz
Intel® Celeron® D Processor 325/325J 256K Cache/ 2.53 GHz/ 533 MHz FSB,326,Discontinued,Q2'04,1,notFound,2.53 GHz,notFound,notFound
Intel® Celeron® Processor G555 2M Cache/ 2.70 GHz,G555,Discontinued,Q3'12,2,2,2.70 GHz,notFound,notFound
Intel® Core™ i7-12800H Processor 24M Cache/ up to 4.80 GHz,i7-12800H,Launched,Q1'22,14,20,notFound,notFound,notFound
Intel® Xeon® Processor E5-1428L v2 15M Cache/ 2.20 GHz,E5-1428LV2,Launched,Q1'14,6,12,2.20 GHz,2.70 GHz,2.70 GHz
Intel® Xeon® Gold 6328HL Processor 22M Cache/ 2.80 GHz,6328HL,Launched,Q2'20,16,32,2.80 GHz,4.30 GHz,notFound
Intel® Celeron® D Processor 356 512K Cache/ 3.33 GHz/ 533 MHz FSB,356,Discontinued,Q2'06,1,notFound,3.33 GHz,notFound,notFound
Intel® Xeon® Processor E5-4620 v3 25M Cache/ 2.00 GHz,E5-4620V3,Discontinued,Q2'15,10,20,2.00 GHz,2.60 GHz,2.60 GHz
Intel® Core™ i7-4700HQ Processor 6M Cache/ up to 3.40 GHz,i7-4700HQ,Discontinued,Q2'13,4,8,2.40 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® D-1623N Processor 6M Cache/ 2.40GHz,D-1623N,Launched,Q2'19,4,8,2.40 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Processor E5-1660 v4 20M Cache/ 3.20 GHz,E5-1660V4,Launched,Q2'16,8,16,3.20 GHz,3.80 GHz,notFound
Intel® Core™ i9-11900F Processor 16M Cache/ up to 5.20 GHz,i9-11900F,Launched,Q1'21,8,16,2.50 GHz,5.20 GHz,5.00 GHz
Intel® Core™ i7-3517U Processor 4M Cache/ up to 3.00 GHz,i7-3517U,Discontinued,Q2'12,2,4,1.90 GHz,3.00 GHz,3.00 GHz
Intel® Celeron® M Processor ULV 523 1M Cache/ 933 MHz/ 533 MHz FSB,523,Discontinued,Q3'07,1,notFound,930 MHz,notFound,notFound
Intel® Core™ i3-4150T Processor 3M Cache/ 3.00 GHz,i3-4150T,Discontinued,Q2'14,2,4,3.00 GHz,notFound,notFound
Intel® Core™ i5-1155G7 Processor 8M Cache/ up to 4.50 GHz/ with IPU,i5-1155G7,Launched,Q2'21,4,8,notFound,4.50 GHz,notFound
Intel® Core™2 Duo Processor P9700 6M Cache/ 2.80 GHz/ 1066 MHz FSB,P9700,Discontinued,Q2'09,2,notFound,2.80 GHz,notFound,notFound
Intel® Core™ i5-12500TE Processor 18M Cache/ up to 4.30 GHz,i5-12500TE,Launched,Q1'22,6,12,notFound,4.30 GHz,notFound
Intel® Core™ i7-3520M Processor 4M Cache/ up to 3.60 GHz,i7-3520M,Discontinued,Q2'12,2,4,2.90 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® Platinum 8176F Processor 38.5M Cache/ 2.10 GHz,8176F,Launched,Q3'17,28,56,2.10 GHz,3.80 GHz,notFound
Intel® Xeon® D-2183IT Processor 22M Cache/ 2.20 GHz,D-2183IT,Launched,Q1'18,16,32,2.20 GHz,3.00 GHz,notFound
Intel® Core™2 Duo Processor T6670 2M Cache/ 2.20 GHz/ 800 MHz FSB,T6670,Discontinued,Q3'09,2,notFound,2.20 GHz,notFound,notFound
Intel® Itanium® Processor 9740 24M Cache/ 2.13 GHz,9740,Launched,Q2'17,8,16,2.13 GHz,notFound,notFound
Intel® Xeon® Silver 4309Y Processor 12M Cache/ 2.80 GHz,4309Y,Launched,Q2'21,8,16,2.80 GHz,3.60 GHz,notFound
Intel® Xeon® Processor E5-4607 12M Cache/ 2.20 GHz/ 6.40 GT/s Intel® QPI,E5-4607,Discontinued,Q2'12,6,12,2.20 GHz,notFound,notFound
Intel® Xeon® E-2378G Processor 16M Cache/ 2.80 GHz,E-2378G,Launched,Q3'21,8,16,2.80 GHz,5.10 GHz,5.10 GHz
Intel® Core™ i5-4690S Processor 6M Cache/ up to 3.90 GHz,i5-4690S,Discontinued,Q2'14,4,4,3.20 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i7-870 Processor 8M Cache/ 2.93 GHz,i7-870,Discontinued,Q3'09,4,8,2.93 GHz,3.60 GHz,notFound
Intel® Xeon® Processor D-1540 12M Cache/ 2.00 GHz,D-1540,Launched,Q1'15,8,16,2.00 GHz,2.60 GHz,2.60 GHz
Intel® Celeron® D Processor 320 256K Cache/ 2.40 GHz/ 533 MHz FSB,320,Discontinued,Q2'04,1,notFound,2.40 GHz,notFound,notFound
Intel® Core™ i7-975 Processor Extreme Edition 8M Cache/ 3.33 GHz/ 6.40 GT/s Intel® QPI,i7-975,Discontinued,Q2'09,4,8,3.33 GHz,3.60 GHz,notFound
Intel® Celeron® Processor G540 2M Cache/ 2.50 GHz,G540,Discontinued,Q3'11,2,2,2.50 GHz,notFound,notFound
Intel® Pentium® Processor N3510 2M Cache/ 2.00 GHz,N3510,Discontinued,Q3'13,4,4,2.00 GHz,notFound,notFound
Intel® Xeon® Gold 5318N Processor 36M Cache/ 2.10 GHz,5318N,Launched,Q2'21,24,48,2.10 GHz,3.40 GHz,notFound
Intel® Xeon® Processor E3-1290 v2 8M Cache/ 3.70 GHz,E3-1290V2,Discontinued,Q2'12,4,8,3.70 GHz,4.10 GHz,4.10 GHz
Intel® Xeon® Processor EC5539 4M Cache/ 2.27 GHz/ 5.87 GT/s Intel® QPI,EC5539,Discontinued,Q1'10,2,2,2.27 GHz,notFound,notFound
Intel® Core™ i5-3330S Processor 6M Cache/ up to 3.20 GHz,i5-3330S,Discontinued,Q3'12,4,4,2.70 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Processor E5-2407 v2 10M Cache/ 2.40 GHz,E5-2407V2,Discontinued,Q1'14,4,4,2.40 GHz,2.40 GHz,notFound
Intel® Xeon® Processor E7-8880 v3 45M Cache/ 2.30 GHz,E7-8880V3,Launched,Q2'15,18,36,2.30 GHz,3.10 GHz,3.10 GHz
Intel® Core™ i7-6560U Processor 4M Cache/ up to 3.20 GHz,i7-6560U,Discontinued,Q3'15,2,4,2.20 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i9-12900TE Processor 30M Cache/ up to 4.80 GHz,i9-12900TE,Launched,Q1'22,16,24,notFound,4.80 GHz,4.80 GHz
Intel Atom® Processor E645CT 512K Cache/ 1.0 GHz,E645CT,Discontinued,Q4'10,1,2,1.00 GHz,notFound,notFound
Intel® Xeon® Processor E5-2630L v4 25M Cache/ 1.80 GHz,E5-2630LV4,Launched,Q1'16,10,20,1.80 GHz,2.90 GHz,2.90 GHz
Intel® Xeon® Processor E7-4820 v3 25M Cache/ 1.90 GHz,E7-4820V3,Launched,Q2'15,10,20,1.90 GHz,notFound,notFound
Intel® Core™ i7-11700B Processor 24M Cache/ up to 4.80 GHz,i7-11700B,Launched,Q2'21,8,16,3.20 GHz,4.80 GHz,notFound
Intel® Celeron® Processor P1053 2M Cache/ 1.33 GHz,P1053,Discontinued,Q1'10,1,2,1.33 GHz,notFound,notFound
Intel® Xeon® Processor E5-2430 v2 15M Cache/ 2.50 GHz,E5-2430V2,Discontinued,Q1'14,6,12,2.50 GHz,3.00 GHz,3.00 GHz
Intel® Xeon® Gold 5315Y Processor 12M Cache/ 3.20 GHz,5315Y,Launched,Q2'21,8,16,3.20 GHz,3.60 GHz,notFound
Intel® Xeon® Processor E3-1280 v2 8M Cache/ 3.60 GHz,E3-1280V2,Discontinued,Q2'12,4,8,3.60 GHz,4.00 GHz,4.00 GHz
Intel® Core™2 Extreme Processor X9100 6M Cache/ 3.06 GHz/ 1066 MHz FSB,X9100,Discontinued,Q3'08,2,notFound,3.06 GHz,notFound,notFound
Intel® Core™ i5-4590 Processor 6M Cache/ up to 3.70 GHz,i5-4590,Discontinued,Q2'14,4,4,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® W-1370 Processor 16M Cache/ up to 5.10 GHz,W-1370,Launched,Q2'21,8,16,2.90 GHz,5.10 GHz,5.00 GHz
Intel® Xeon® Gold 6146 Processor 24.75M Cache/ 3.20 GHz,6146,Launched,Q3'17,12,24,3.20 GHz,4.20 GHz,notFound
Intel® Xeon® Gold 5317 Processor 18M Cache/ 3.00 GHz,5317,Launched,Q2'21,12,24,3.00 GHz,3.60 GHz,notFound
Intel® Xeon® Processor E5-4640 20M Cache/ 2.40 GHz/ 8.00 GT/s Intel® QPI,E5-4640,Discontinued,Q2'12,8,16,2.40 GHz,2.80 GHz,2.80 GHz
Intel® Core™ i3-4160T Processor 3M Cache/ 3.10 GHz,i3-4160T,Discontinued,Q3'14,2,4,3.10 GHz,notFound,notFound
Intel® Xeon® Gold 6258R Processor 38.5M Cache/ 2.70 GHz,6258R,Launched,Q1'20,28,56,2.70 GHz,4.00 GHz,notFound
Intel® Core™ i7-6820EQ Processor 8M Cache/ up to 3.50 GHz,i7-6820EQ,Launched,Q4'15,4,8,2.80 GHz,3.50 GHz,3.50 GHz
Intel® Pentium® Processor G4400T 3M Cache/ 2.90 GHz,G4400T,Discontinued,Q3'15,2,2,2.90 GHz,notFound,notFound
Intel® Celeron® Processor B800 2M Cache/ 1.50 GHz,B800,Discontinued,Q2'11,2,2,1.50 GHz,notFound,notFound
Intel® Core™ i7-12700TE Processor 25M Cache/ up to 4.60 GHz,i7-12700TE,Launched,Q1'22,12,20,notFound,4.60 GHz,4.60 GHz
Intel® Core™ i7-980 Processor 12M Cache/ 3.33 GHz/ 4.8 GT/s Intel® QPI,i7-980,Discontinued,Q2'11,6,12,3.33 GHz,3.60 GHz,notFound
Intel® Xeon® Processor E7-8880L v3 45M Cache/ 2.00 GHz,E7-8880LV3,Launched,Q2'15,18,36,2.00 GHz,2.80 GHz,2.80 GHz
Intel® Core™ i5-6287U Processor 4M Cache/ up to 3.50 GHz,i5-6287U,Discontinued,Q3'15,2,4,3.10 GHz,3.50 GHz,3.50 GHz
Intel® Pentium® Gold G5620 Processor 4M Cache/ 4.00 GHz,G5620,Launched,Q2'19,2,4,4.00 GHz,notFound,notFound
Intel® Core™ i7-4702HQ Processor 6M Cache/ up to 3.20 GHz,i7-4702HQ,Discontinued,Q2'13,4,8,2.20 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Silver 4112 Processor 8.25M Cache/ 2.60 GHz,4112,Launched,Q3'17,4,8,2.60 GHz,3.00 GHz,notFound
Intel® Xeon® Processor E5-2650 v3 25M Cache/ 2.30 GHz,E5-2650V3,Discontinued,Q3'14,10,20,2.30 GHz,3.00 GHz,3.00 GHz
Intel® Celeron® Processor G3930 2M Cache/ 2.90 GHz,G3930,Discontinued,Q1'17,2,2,2.90 GHz,notFound,notFound
Intel® Xeon® Processor E5-4669 v4 55M Cache/ 2.20 GHz,E5-4669V4,Launched,Q2'16,22,44,2.20 GHz,3.00 GHz,3.00 GHz
Intel® Core™2 Duo Processor E6540 4M Cache/ 2.33 GHz/ 1333 MHz FSB,E6540,Discontinued,Q3'07,2,notFound,2.33 GHz,notFound,notFound
Intel® Celeron® Processor N3350 2M Cache/ up to 2.40 GHz,N3350,Launched,Q3'16,2,2,1.10 GHz,notFound,notFound
Intel® Pentium® Processor G640 3M Cache/ 2.80 GHz,G640,Discontinued,Q2'12,2,2,2.80 GHz,notFound,notFound
Intel® Xeon® W-2223 Processor 8.25M Cache/ 3.60 GHz,W-2223,Launched,Q4'19,4,8,3.60 GHz,3.90 GHz,notFound
Intel® Core™ i7-2710QE Processor 6M Cache/ up to 3.00 GHz,i7-2710QE,Discontinued,Q1'11,4,8,2.10 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i7-8700 Processor 12M Cache/ up to 4.60 GHz,i7-8700,Launched,Q4'17,6,12,3.20 GHz,4.60 GHz,4.60 GHz
Intel® Core™ i3-7100 Processor 3M Cache/ 3.90 GHz,i3-7100,Discontinued,Q1'17,2,4,3.90 GHz,notFound,notFound
Intel Atom® x5-Z8330 Processor 2M Cache/ up to 1.92 GHz,x5-Z8330,Launched,Q1'16,4,notFound,1.44 GHz,notFound,notFound
Intel Atom® x5-Z8330 Processor 2M Cache/ up to 1.92 GHz,x5-Z8330,Launched,Q1'16,4,notFound,1.44 GHz,notFound,notFound
Intel® Celeron® Processor N3050 2M Cache/ up to 2.16 GHz,N3050,Discontinued,Q1'15,2,2,1.60 GHz,notFound,notFound
Intel® Xeon® E-2276M Processor 12M Cache/ 2.80 GHz,E-2276M,Launched,Q2'19,6,12,2.80 GHz,4.70 GHz,notFound
Intel® Core™2 Duo Processor T9550 6M Cache/ 2.66 GHz/ 1066 MHz FSB,T9550,Discontinued,Q4'08,2,notFound,2.66 GHz,notFound,notFound
Intel® Celeron® Processor N6210 1.5M Cache/ up to 2.60 GHz,N6210,Launched,Q1'21,2,2,1.20 GHz,notFound,notFound
Intel® Core™ i7-10810U Processor 12M Cache/ up to 4.90 GHz,i7-10810U,Launched,Q2'20,6,12,1.10 GHz,4.90 GHz,notFound
Intel® Pentium® Processor G620T 3M Cache/ 2.20 GHz,G620T,Discontinued,Q2'11,2,2,2.20 GHz,notFound,notFound
Intel® Xeon® Gold 6346 Processor 36M Cache/ 3.10 GHz,6346,Launched,Q2'21,16,32,3.10 GHz,3.60 GHz,notFound
Intel® Xeon® Processor E5-4628L v4 35M Cache/ 1.80 GHz,E5-4628LV4,Launched,Q2'16,14,28,1.80 GHz,2.20 GHz,2.20 GHz
Intel® Core™2 Duo Processor E6850 4M Cache/ 3.00 GHz/ 1333 MHz FSB,E6850,Discontinued,Q3'07,2,notFound,3.00 GHz,notFound,notFound
Intel® Celeron® Processor 530 1M Cache/ 1.73 GHz/ 533 MHz FSB Socket P,530,Discontinued,Q1'07,1,notFound,1.73 GHz,notFound,notFound
Intel® Xeon® Processor E3-1505M v6 8M Cache/ 3.00 GHz,E3-1505MV6,Launched,Q1'17,4,8,3.00 GHz,4.00 GHz,4.00 GHz
Intel® Celeron® Processor N3450 2M Cache/ up to 2.20 GHz,N3450,Launched,Q3'16,4,4,1.10 GHz,notFound,notFound
Intel® Pentium® Processor N3700 2M Cache/ up to 2.40 GHz,N3700,Discontinued,Q1'15,4,4,1.60 GHz,notFound,notFound
Intel® Xeon® W-2255 Processor 19.25M Cache/ 3.70 GHz,W-2255,Launched,Q4'19,10,20,3.70 GHz,4.50 GHz,notFound
Intel® Xeon® Processor X5550 8M Cache/ 2.66 GHz/ 6.40 GT/s Intel® QPI,X5550,Discontinued,Q1'09,4,8,2.66 GHz,3.06 GHz,notFound
Intel Atom® Processor Z530 512K Cache/ 1.60 GHz/ 533 MHz FSB,Z530,Discontinued,Q2'08,1,notFound,1.60 GHz,notFound,notFound
Intel® Xeon® Processor L5215 6M Cache/ 1.86 GHz/ 1066 MHz FSB,L5215,Discontinued,Q3'08,2,notFound,1.86 GHz,notFound,notFound
Intel® Pentium® Processor G860T 3M Cache/ 2.60 GHz,G860T,Discontinued,Q2'12,2,2,2.60 GHz,notFound,notFound
Intel Atom® Processor Z2480 512K Cache/ up to 2.00 GHz,Z2480,Discontinued,Q3'12,1,2,notFound,notFound,notFound
Intel® Celeron® Processor 570 1M Cache/ 2.26 GHz/ 533 MHz FSB,570,Discontinued,Q2'08,1,notFound,2.26 GHz,notFound,notFound
Intel® Xeon® Gold 6314U Processor 48M Cache/ 2.30 GHz,6314U,Launched,Q2'21,32,64,2.30 GHz,3.40 GHz,notFound
Intel® Xeon® Processor E5-2650 v4 30M Cache/ 2.20 GHz,E5-2650V4,Launched,Q1'16,12,24,2.20 GHz,2.90 GHz,2.90 GHz
Intel® Xeon® Processor X3350 12M Cache/ 2.66 GHz/ 1333 MHz FSB,X3350,Discontinued,Q1'08,4,notFound,2.66 GHz,notFound,notFound
Intel® Xeon® W-2295 Processor 24.75M Cache/ 3.00 GHz,W-2295,Launched,Q4'19,18,36,3.00 GHz,4.60 GHz,notFound
Intel® Pentium® Processor J4205 2M Cache/ up to 2.60 GHz,J4205,Launched,Q3'16,4,4,1.50 GHz,notFound,notFound
Intel Atom® Processor Z3745D 2M Cache/ up to 1.83 GHz,Z3745D,Discontinued,Q1'14,4,notFound,1.33 GHz,notFound,notFound
Intel® Xeon® Platinum 8360Y Processor 54M Cache/ 2.40 GHz,8360Y,Launched,Q2'21,36,72,2.40 GHz,3.50 GHz,notFound
Intel® Core™ i3-2375M Processor 3M Cache/ 1.50 GHz,i3-2375M,Discontinued,Q1'13,2,4,1.50 GHz,notFound,notFound
Intel® Celeron® Processor G5905T 4M Cache/ 3.30 GHz,G5905T,Launched,Q3'20,2,2,3.30 GHz,notFound,notFound
Intel® Core™ i3-9100F Processor 6M Cache/ up to 4.20 GHz,i3-9100F,Launched,Q2'19,4,4,3.60 GHz,4.20 GHz,4.20 GHz
Intel® Core™ i3-2377M Processor 3M Cache/ 1.50 GHz,i3-2377M,Discontinued,Q2'12,2,4,1.50 GHz,notFound,notFound
Intel® Core™ i7-7820HK Processor 8M Cache/ up to 3.90 GHz,i7-7820HK,Launched,Q1'17,4,8,2.90 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i9-9880H Processor 16M Cache/ up to 4.80 GHz,i9-9880H,Launched,Q2'19,8,16,2.30 GHz,4.80 GHz,notFound
Intel® Core™2 Quad Processor Q8400 4M Cache/ 2.66 GHz/ 1333 MHz FSB,Q8400,Discontinued,Q2'09,4,notFound,2.66 GHz,notFound,notFound
Intel® Itanium® Processor 9350 24M Cache/ 1.73 GHz/ 4.80 GT/s Intel® QPI,9350,Discontinued,Q1'10,4,8,1.73 GHz,1.87 GHz,notFound
Intel Atom® Processor Z510P 512K Cache/ 1.10 GHz/ 400 MHz FSB,Z510P,Discontinued,Q2'08,1,notFound,1.10 GHz,notFound,notFound
Intel® Celeron® Processor N3000 2M Cache/ up to 2.08 GHz,N3000,Discontinued,Q1'15,2,2,1.04 GHz,notFound,notFound
Intel® Core™ i3-8100 Processor 6M Cache/ 3.60 GHz,i3-8100,Launched,Q4'17,4,4,3.60 GHz,notFound,notFound
Intel® Pentium® Processor 2020M 2M Cache/ 2.40 GHz,2020M,Discontinued,Q3'12,2,2,2.40 GHz,notFound,notFound
Intel® Celeron® M Processor ULV 723 1M Cache/ 1.20 GHz/ 800 MHz FSB,723,Discontinued,Q3'08,1,notFound,1.20 GHz,notFound,notFound
Intel® Xeon® Processor E7-4830 24M Cache/ 2.13 GHz/ 6.40 GT/s Intel® QPI,E7-4830,Discontinued,Q2'11,8,16,2.13 GHz,2.40 GHz,notFound
Intel® Celeron® Processor J1750 1M Cache/ 2.41 GHz,J1750,Discontinued,Q3'13,2,2,2.41 GHz,notFound,notFound
Intel® Core™ i7-4785T Processor 8M Cache/ up to 3.20 GHz,i7-4785T,Discontinued,Q2'14,4,8,2.20 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Processor W3530 8M Cache/ 2.80 GHz/ 4.80 GT/s Intel® QPI,W3530,Discontinued,Q1'10,4,8,2.80 GHz,3.06 GHz,notFound
Intel® Xeon® Gold 6334 Processor 18M Cache/ 3.60 GHz,6334,Launched,Q2'21,8,16,3.60 GHz,3.70 GHz,notFound
Intel® Xeon® Processor E5-4610 15M Cache/ 2.40 GHz/ 7.20 GT/s Intel® QPI,E5-4610,Discontinued,Q2'12,6,12,2.40 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i7-12700H Processor 24M Cache/ up to 4.70 GHz,i7-12700H,Launched,Q1'22,14,20,notFound,notFound,notFound
Intel® Xeon® W-1350P Processor 12M Cache/ up to 5.10 GHz,W-1350P,Launched,Q2'21,6,12,4.00 GHz,5.10 GHz,5.10 GHz
Intel® Xeon® Gold 6144 Processor 24.75M Cache/ 3.50 GHz,6144,Launched,Q3'17,8,16,3.50 GHz,4.20 GHz,notFound
Intel® Pentium® M Processor 745 2M Cache/ 1.80 GHz/ 400 MHz FSB,745,Discontinued,Q2'04,1,notFound,1.80 GHz,notFound,notFound
Intel® Xeon® Processor LC3518 2M Cache/ 1.73 GHz,LC3518,Discontinued,Q1'10,1,1,1.73 GHz,notFound,notFound
Intel® Core™ i5-3550 Processor 6M Cache/ up to 3.70 GHz,i5-3550,Discontinued,Q2'12,4,4,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® Processor E5-2420 v2 15M Cache/ 2.20 GHz,E5-2420V2,Discontinued,Q1'14,6,12,2.20 GHz,2.70 GHz,2.70 GHz
Intel® Pentium® Gold Processor 4425Y 2M Cache/ 1.70 GHz,4425Y,Launched,Q1'19,2,4,1.70 GHz,notFound,notFound
Intel® Xeon® Processor X5470 12M Cache/ 3.33 GHz/ 1333 MHz FSB,X5470,Discontinued,Q3'08,4,notFound,3.33 GHz,notFound,notFound
Intel Atom® Processor Z3736G 2M Cache/ up to 2.16 GHz,Z3736G,Discontinued,Q2'14,4,notFound,1.33 GHz,notFound,notFound
Intel® Xeon® Processor E7-8890 v3 45M Cache/ 2.50 GHz,E7-8890V3,Launched,Q2'15,18,36,2.50 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® Processor E5-4610 v3 25M Cache/ 1.70 GHz,E5-4610V3,Discontinued,Q2'15,10,20,1.70 GHz,1.70 GHz,notFound
Intel® Pentium® Gold G5420 Processor 4M Cache/ 3.80 GHz,G5420,Launched,Q2'19,2,4,3.80 GHz,notFound,notFound
Intel® Core™ i3-12100 Processor 12M Cache/ up to 4.30 GHz,i3-12100,Launched,Q1'22,4,8,notFound,4.30 GHz,notFound
Intel® Core™ i7-4702MQ Processor 6M Cache/ up to 3.20 GHz,i7-4702MQ,Discontinued,Q2'13,4,8,2.20 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Platinum 8360HL Processor 33M Cache/ 3.00 GHz,8360HL,Launched,Q3'20,24,48,3.00 GHz,4.20 GHz,notFound
Intel® Xeon® Gold 6248R Processor 35.75M Cache/ 3.00 GHz,6248R,Launched,Q1'20,24,48,3.00 GHz,4.00 GHz,notFound
Intel® Core™ i3-4160 Processor 3M Cache/ 3.60 GHz,i3-4160,Discontinued,Q3'14,2,4,3.60 GHz,notFound,notFound
Intel® Celeron® Processor 787 1.5M Cache/ 1.30 GHz,787,Discontinued,Q3'11,1,1,1.30 GHz,notFound,notFound
Intel® Core™ i7-6822EQ Processor 8M Cache/ up to 2.80 GHz,i7-6822EQ,Launched,Q4'15,4,8,2.00 GHz,2.80 GHz,2.80 GHz
Intel® Core™ i5-4330M Processor 3M Cache/ up to 3.50 GHz,i5-4330M,Discontinued,Q4'13,2,4,2.80 GHz,3.50 GHz,3.50 GHz
Intel® Core™2 Duo Processor E8600 6M Cache/ 3.33 GHz/ 1333 MHz FSB,E8600,Discontinued,Q3'08,2,notFound,3.33 GHz,notFound,notFound
Intel® Celeron® Processor G540T 2M Cache/ 2.10 GHz,G540T,Discontinued,Q2'12,2,2,2.10 GHz,notFound,notFound
Intel® Xeon® Processor LC5528 8M Cache/ 2.13 GHz/ 4.80 GT/s Intel® QPI,LC5528,Discontinued,Q1'10,4,8,2.13 GHz,2.53 GHz,notFound
Intel® Core™ i5-3450 Processor 6M Cache/ up to 3.50 GHz,i5-3450,Discontinued,Q2'12,4,4,3.10 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® Processor E5-2418L v2 15M Cache/ 2.00 GHz,E5-2418LV2,Launched,Q1'14,6,12,2.00 GHz,2.00 GHz,notFound
Intel® Xeon® Gold 6336Y Processor 36M Cache/ 2.40 GHz,6336Y,Launched,Q2'21,24,48,2.40 GHz,3.60 GHz,notFound
Intel® Xeon® W-1350 Processor 12M Cache/ up to 5.00 GHz,W-1350,Launched,Q2'21,6,12,3.30 GHz,5.00 GHz,5.00 GHz
Intel® Core™ i7-9700E Processor 12M Cache/ up to 4.40 GHz,i7-9700E,Launched,Q2'19,8,8,2.60 GHz,4.40 GHz,4.40 GHz
Intel® Xeon® Gold 6326 Processor 24M Cache/ 2.90 GHz,6326,Launched,Q2'21,16,32,2.90 GHz,3.50 GHz,notFound
Intel® Core™ i7-4765T Processor 8M Cache/ up to 3.00 GHz,i7-4765T,Discontinued,Q2'13,4,8,2.00 GHz,3.00 GHz,3.00 GHz
Intel® Xeon® Processor D-1520 6M Cache/ 2.20 GHz,D-1520,Launched,Q1'15,4,8,2.20 GHz,2.60 GHz,2.60 GHz
Intel® Celeron® D Processor 315/315J 256K Cache/ 2.26 GHz/ 533 MHz FSB,315J,Discontinued,Q2'04,1,notFound,2.26 GHz,notFound,notFound
Intel® Core™ i5-4690T Processor 6M Cache/ up to 3.50 GHz,i5-4690T,Discontinued,Q2'14,4,4,2.50 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® W-11155MLE Processor 8M Cache/ up to 3.10 GHz,W-11155MLE,Launched,Q3'21,4,8,1.80 GHz,3.10 GHz,notFound
Intel® Core™ i3-6102E Processor 3M Cache/ 1.90 GHz,i3-6102E,Launched,Q4'15,2,4,1.90 GHz,notFound,notFound
Intel Atom® Processor E645C 512K Cache/ 1.0 GHz,E645C,Discontinued,Q4'10,1,2,1.00 GHz,notFound,notFound
Intel® Xeon® Processor E5-2667 v4 25M Cache/ 3.20 GHz,E5-2667V4,Launched,Q1'16,8,16,3.20 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i3-2130 Processor 3M Cache/ 3.40 GHz,i3-2130,Discontinued,Q3'11,2,4,3.40 GHz,notFound,notFound
Intel® Xeon® Processor E7-4809 v3 20M Cache/ 2.00 GHz,E7-4809V3,Launched,Q2'15,8,16,2.00 GHz,notFound,notFound
Intel® Xeon® Processor D-1537 12M Cache/ 1.70 GHz,D-1537,Launched,Q4'15,8,16,1.70 GHz,2.30 GHz,2.30 GHz
Intel® Xeon® Processor E7-8870 v3 45M Cache/ 2.10 GHz,E7-8870V3,Launched,Q2'15,18,36,2.10 GHz,2.90 GHz,2.90 GHz
Intel® Celeron® M Processor 320 512K Cache/ 1.30 GHz/ 400 MHz FSB,320,Discontinued,Q2'03,1,notFound,1.30 GHz,notFound,notFound
Intel® Pentium® Processor G2120 3M Cache/ 3.10 GHz,G2120,Launched,Q3'12,2,2,3.10 GHz,notFound,notFound
Intel® Core™ i5-1155G7 Processor 8M Cache/ up to 4.50 GHz,i5-1155G7,Launched,Q2'21,4,8,notFound,4.50 GHz,notFound
Intel® Xeon® Processor E5-2650L v3 30M Cache/ 1.80 GHz,E5-2650LV3,Discontinued,Q3'14,12,24,1.80 GHz,2.50 GHz,2.50 GHz
Intel® Core™ i3-4150 Processor 3M Cache/ 3.50 GHz,i3-4150,Discontinued,Q2'14,2,4,3.50 GHz,notFound,notFound
Intel® Xeon® Processor E5-4627 v3 25M Cache/ 2.60 GHz,E5-4627V3,Discontinued,Q2'15,10,10,2.60 GHz,3.20 GHz,3.20 GHz
Intel® Celeron® D Processor 355 256K Cache/ 3.33 GHz/ 533 MHz FSB,355,Discontinued,Q4'05,1,notFound,3.33 GHz,notFound,notFound
Intel® Xeon® Processor E3-1285 v4 6M Cache/ 3.50 GHz,E3-1285V4,Discontinued,Q2'15,4,8,3.50 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i7-4700MQ Processor 6M Cache/ up to 3.40 GHz,i7-4700MQ,Discontinued,Q2'13,4,8,2.40 GHz,3.40 GHz,3.40 GHz
Intel® Pentium® Processor 6805 4M Cache/ up to 3.00 GHz,6805,Launched,Q4'20,2,4,1.10 GHz,3.00 GHz,notFound
Intel® Itanium® Processor 9330 20M Cache/ 1.46 GHz/ 4.80 GT/s Intel® QPI,9330,Discontinued,Q1'10,4,8,1.46 GHz,1.60 GHz,notFound
Intel® Celeron® Processor G4932E 2M Cache/ 1.90 GHz,G4932E,Launched,Q2'19,2,2,1.90 GHz,1.90 GHz,notFound
Intel® Xeon® E-2324G Processor 8M Cache/ 3.10 GHz,E-2324G,Launched,Q3'21,4,4,3.10 GHz,4.60 GHz,4.60 GHz
Intel® Xeon® Processor E5-2640 v4 25M Cache/ 2.40 GHz,E5-2640V4,Launched,Q1'16,10,20,2.40 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i7-12700E Processor 25M Cache/ up to 4.80 GHz,i7-12700E,Launched,Q1'22,12,20,notFound,4.80 GHz,4.80 GHz
Intel Atom® Processor Z3740 2M Cache/ up to 1.86 GHz,Z3740,Discontinued,Q3'13,4,notFound,1.33 GHz,notFound,notFound
Intel® Xeon® D-2187NT Processor 22M Cache/ 2.00 GHz,D-2187NT,Launched,Q1'18,16,32,2.00 GHz,3.00 GHz,notFound
Intel® Core™ i5-3550S Processor 6M Cache/ up to 3.70 GHz,i5-3550S,Launched,Q2'12,4,4,3.00 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i3-12300HE Processor 12M Cache/ up to 4.30 GHz,i3-12300HE,Launched,Q1'22,8,12,notFound,4.30 GHz,notFound
Intel® Core™ i5-12500E Processor 18M Cache/ up to 4.50 GHz,i5-12500E,Launched,Q1'22,6,12,notFound,4.50 GHz,notFound
Intel® Core™ i7-4800MQ Processor 6M Cache/ up to 3.70 GHz,i7-4800MQ,Discontinued,Q2'13,4,8,2.70 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i3-6167U Processor 3M Cache/ 2.70 GHz,i3-6167U,Discontinued,Q3'15,2,4,2.70 GHz,notFound,notFound
Intel® Xeon® Processor E5-4669 v3 45M Cache/ 2.10 GHz,E5-4669V3,Discontinued,Q2'15,18,36,2.10 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i9-11900 Processor 16M Cache/ up to 5.20 GHz,i9-11900,Launched,Q1'21,8,16,2.50 GHz,5.20 GHz,5.00 GHz
Intel® Xeon® Processor E5-2637 v4 15M Cache/ 3.50 GHz,E5-2637V4,Launched,Q1'16,4,8,3.50 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® Processor E3-1265L v4 6M Cache/ 2.30 GHz,E3-1265LV4,Discontinued,Q2'15,4,8,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® D-1649N Processor 12M Cache/ 2.30GHz,D-1649N,Launched,Q2'19,8,16,2.30 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i3-4100U Processor 3M Cache/ 1.80 GHz,i3-4100U,Discontinued,Q3'13,2,4,1.80 GHz,notFound,notFound
Intel® Core™ i3-2120 Processor 3M Cache/ 3.30 GHz,i3-2120,Discontinued,Q1'11,2,4,3.30 GHz,notFound,notFound
Intel® Core™ i3-4130T Processor 3M Cache/ 2.90 GHz,i3-4130T,Discontinued,Q3'13,2,4,2.90 GHz,notFound,notFound
Intel® Xeon® Processor E7-4830 v3 30M Cache/ 2.10 GHz,E7-4830V3,Launched,Q2'15,12,24,2.10 GHz,2.70 GHz,2.70 GHz
Intel® Core™ i7-11390H Processor 12M Cache/ up to 5.00 GHz/ with IPU,i7-11390H,Launched,Q2'21,4,8,notFound,5.00 GHz,notFound
Intel® Xeon® Processor D-1528 9M Cache/ 1.90 GHz,D-1528,Launched,Q4'15,6,12,1.90 GHz,2.50 GHz,2.50 GHz
Intel® Core™ i7-3555LE Processor 4M Cache/ up to 3.20 GHz,i7-3555LE,Launched,Q2'12,2,4,2.50 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i5-3570K Processor 6M Cache/ up to 3.80 GHz,i5-3570K,Discontinued,Q2'12,4,4,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Celeron® Processor 3765U 2M Cache/ 1.90 GHz,3765U,Launched,Q2'15,2,2,1.90 GHz,notFound,notFound
Intel® Celeron® D Processor 325 256K Cache/ 2.53 GHz/ 533 MHz FSB,325,Discontinued,Q2'04,1,notFound,2.53 GHz,notFound,notFound
Intel® Xeon® Processor E5-4648 v3 30M Cache/ 1.70 GHz,E5-4648V3,Launched,Q2'15,12,24,1.70 GHz,2.20 GHz,2.20 GHz
Intel® Core™ i5-12500 Processor 18M Cache/ up to 4.60 GHz,i5-12500,Launched,Q1'22,6,12,notFound,4.60 GHz,notFound
Intel® Xeon® Processor E5-1620 v2 10M Cache/ 3.70 GHz,E5-1620V2,Discontinued,Q3'13,4,8,3.70 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i5-3350P Processor 6M Cache/ up to 3.30 GHz,i5-3350P,Discontinued,Q3'12,4,4,3.10 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i5-3360M Processor 3M Cache/ up to 3.50 GHz,i5-3360M,Discontinued,Q2'12,2,4,2.80 GHz,3.50 GHz,3.50 GHz
Intel® Celeron® Processor G550T 2M Cache/ 2.20 GHz,G550T,Discontinued,Q3'12,2,2,2.20 GHz,notFound,notFound
Intel® Celeron® Processor N2808 1M Cache/ up to 2.25 GHz,N2808,Discontinued,Q3'14,2,2,1.58 GHz,notFound,notFound
Intel® Core™ i7-8650U Processor 8M Cache/ up to 4.20 GHz,i7-8650U,Launched,Q3'17,4,8,1.90 GHz,4.20 GHz,4.20 GHz
Intel® Core™ i7-8650U Processor 8M Cache/ up to 4.20 GHz,i7-8650U,Launched,Q3'17,4,8,1.90 GHz,4.20 GHz,4.20 GHz
Intel® Core™ i5-2450P Processor 6M Cache/ up to 3.50 GHz,i5-2450P,Discontinued,Q1'12,4,4,3.20 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i5-12600KF Processor 20M Cache/ up to 4.90 GHz,i5-12600KF,Launched,Q4'21,10,16,notFound,4.90 GHz,notFound
Intel® Core™ i9-9960X X-series Processor 22M Cache/ up to 4.50 GHz,i9-9960X,Discontinued,Q4'18,16,32,3.10 GHz,4.40 GHz,notFound
Intel® Pentium® Processor J6426 1.5M Cache/ up to 3.00 GHz,J6426,Launched,Q1'21,4,4,2.00 GHz,notFound,notFound
Intel® Xeon® Gold 6238R Processor 38.5M Cache/ 2.20 GHz,6238R,Launched,Q1'20,28,56,2.20 GHz,4.00 GHz,notFound
Intel® Xeon® Platinum 8158 Processor 24.75M Cache/ 3.00 GHz,8158,Launched,Q3'17,12,24,3.00 GHz,3.70 GHz,notFound
Intel® Celeron® Processor G1840 2M Cache/ 2.80 GHz,G1840,Discontinued,Q2'14,2,2,2.80 GHz,notFound,notFound
Intel® Core™ i5-11400 Processor 12M Cache/ up to 4.40 GHz,i5-11400,Launched,Q1'21,6,12,2.60 GHz,4.40 GHz,4.40 GHz
Intel® Xeon® Processor E5-2430 15M Cache/ 2.20 GHz/ 7.20 GT/s Intel® QPI,E5-2430,Discontinued,Q2'12,6,12,2.20 GHz,2.70 GHz,notFound
Intel® Core™ i7-4702EC Processor 8M Cache/ up to 2.00 GHz,i7-4702EC,Launched,Q1'14,4,8,2.00 GHz,notFound,notFound
Intel® Xeon® Processor E5-2630 v2 15M Cache/ 2.60 GHz,E5-2630V2,Discontinued,Q3'13,6,12,2.60 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Platinum 8352Y Processor 48M Cache/ 2.20 GHz,8352Y,Launched,Q2'21,32,64,2.20 GHz,3.40 GHz,notFound
Intel® Core™ i3-10100Y Processor 4M Cache/ up to 3.90 GHz,i3-10100Y,Launched,Q1'21,2,4,1.30 GHz,3.90 GHz,3.90 GHz
Intel® Core™2 Quad Processor Q8400S 4M Cache/ 2.66 GHz/ 1333 MHz FSB,Q8400S,Discontinued,Q2'09,4,notFound,2.66 GHz,notFound,notFound
Intel® Xeon® Processor E3-1240 v2 8M Cache/ 3.40 GHz,E3-1240V2,Discontinued,Q2'12,4,8,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i9-8950HK Processor 12M Cache/ up to 4.80 GHz,i9-8950HK,Launched,Q2'18,6,12,2.90 GHz,4.80 GHz,notFound
Intel Atom® Processor C2308 1M Cache/ 1.25 GHz,C2308,Launched,Q2'14,2,2,1.25 GHz,notFound,notFound
Intel® Xeon® Processor E3-1278L v4 6M Cache/ 2.00 GHz,E3-1278LV4,Launched,Q2'15,4,8,2.00 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i5-3210M Processor 3M Cache/ up to 3.10 GHz BGA,i5-3210M,Discontinued,Q2'12,2,4,2.50 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Gold 5218R Processor 27.5M Cache/ 2.10 GHz,5218R,Launched,Q1'20,20,40,2.10 GHz,4.00 GHz,notFound
Intel® Core™ i5-2537M Processor 3M Cache/ up to 2.30 GHz,i5-2537M,Discontinued,Q1'11,2,4,1.40 GHz,2.30 GHz,2.30 GHz
Intel Atom® x6200FE Processor 1.5M Cache/ 1.00 GHz,6200FE,Launched,Q1'21,2,2,1.00 GHz,notFound,notFound
Intel® Core™ i9-12900 Processor 30M Cache/ up to 5.10 GHz,i9-12900,Launched,Q1'22,16,24,notFound,5.10 GHz,notFound
Intel® Core™ i9-9900X X-series Processor 19.25M Cache/ up to 4.50 GHz,i9-9900X,Discontinued,Q4'18,10,20,3.50 GHz,4.40 GHz,notFound
Intel® Core™ i5-2380P Processor 6M Cache/ up to 3.40 GHz,i5-2380P,Discontinued,Q1'12,4,4,3.10 GHz,3.40 GHz,3.40 GHz
Intel® Pentium® Processor N3540 2M Cache/ up to 2.66 GHz,N3540,Discontinued,Q3'14,4,4,2.16 GHz,notFound,notFound
Intel® Xeon® Processor X3450 8M Cache/ 2.66 GHz,X3450,Discontinued,Q3'09,4,8,2.66 GHz,3.20 GHz,notFound
Intel® Xeon Phi™ Coprocessor 3120A 6GB/ 1.100 GHz/ 57 core,3120A,Discontinued,Q2'13,57,notFound,1.10 GHz,notFound,notFound
Intel® Xeon® Processor E5-2450 20M Cache/ 2.10 GHz/ 8.00 GT/s Intel® QPI,E5-2450,Discontinued,Q2'12,8,16,2.10 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i7-1065G7 Processor 8M Cache/ up to 3.90 GHz,i7-1065G7,Launched,Q3'19,4,8,1.30 GHz,3.90 GHz,notFound
Intel® Core™ i5-11500 Processor 12M Cache/ up to 4.60 GHz,i5-11500,Launched,Q1'21,6,12,2.70 GHz,4.60 GHz,4.60 GHz
Intel® Core™ i7-4790K Processor 8M Cache/ up to 4.40 GHz,i7-4790K,Discontinued,Q2'14,4,8,4.00 GHz,4.40 GHz,4.40 GHz
Intel® Celeron® D Processor 330 256K Cache/ 2.66 GHz/ 533 MHz FSB,330,Discontinued,Q4'04,1,notFound,2.66 GHz,notFound,notFound
Intel® Core™2 Duo Processor T6400 2M Cache/ 2.00 GHz/ 800 MHz FSB,T6400,Discontinued,Q1'09,2,notFound,2.00 GHz,notFound,notFound
Intel® Core™2 Quad Processor Q9505 6M Cache/ 2.83 GHz/ 1333 MHz FSB,Q9505,Discontinued,Q3'09,4,notFound,2.83 GHz,notFound,notFound
Intel® Core™ i9-10900E Processor 20M Cache/ up to 4.70 GHz,i9-10900E,Launched,Q2'20,10,20,2.80 GHz,4.70 GHz,notFound
Intel® Xeon® Silver 4314 Processor 24M Cache/ 2.40 GHz,4314,Launched,Q2'21,16,32,2.40 GHz,3.40 GHz,notFound
Intel® Xeon® Processor E5-1650 v3 15M Cache/ 3.50 GHz,E5-1650V3,Discontinued,Q3'14,6,12,3.50 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® W-11865MLE Processor 24M Cache/ up to 4.50 GHz,W-11865MLE,Launched,Q3'21,8,16,1.50 GHz,4.50 GHz,notFound
Intel® Core™ i5-3570S Processor 6M Cache/ up to 3.80 GHz,i5-3570S,Discontinued,Q2'12,4,4,3.10 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i3-330M Processor 3M Cache/ 2.13 GHz,i3-330M,Discontinued,Q1'10,2,4,2.13 GHz,notFound,notFound
Intel® Core™ i3-4350T Processor 4M Cache/ 3.10 GHz,i3-4350T,Launched,Q2'14,2,4,3.10 GHz,notFound,notFound
Intel® Core™ i7-2629M Processor 4M Cache/ up to 3.00 GHz,i7-2629M,Discontinued,Q1'11,2,4,2.10 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i3-9350KF Processor 8M Cache/ up to 4.60 GHz,i3-9350KF,Launched,Q1'19,4,4,4.00 GHz,4.60 GHz,4.60 GHz
Intel Atom® Processor P5942B 18M Cache/ 2.20 GHz,P5942B,Launched,Q1'20,16,16,2.20 GHz,notFound,notFound
Intel® Celeron® D Processor 345J 256K Cache/ 3.06 GHz/ 533 MHz FSB,345J,Discontinued,Q4'04,1,notFound,3.06 GHz,notFound,notFound
Intel® Xeon® W-2245 Processor 16.5M Cache/ 3.90 GHz,W-2245,Launched,Q4'19,8,16,3.90 GHz,4.50 GHz,notFound
Intel® Core™ i7-5960X Processor Extreme Edition 20M Cache/ up to 3.50 GHz,i7-5960X,Discontinued,Q3'14,8,16,3.00 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i5-9500E Processor 9M Cache/ up to 4.20 GHz,i5-9500E,Launched,Q2'19,6,6,3.00 GHz,4.20 GHz,4.20 GHz
Intel® Core™ i3-4112E Processor 3M Cache/ 1.80 GHz,i3-4112E,Launched,Q2'14,2,4,1.80 GHz,notFound,notFound
Intel® Xeon® Processor E5-2609 v4 20M Cache/ 1.70 GHz,E5-2609V4,Launched,Q1'16,8,8,1.70 GHz,notFound,notFound
Intel® Core™ i7-4790T Processor 8M Cache/ up to 3.90 GHz,i7-4790T,Discontinued,Q2'14,4,8,2.70 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor E5240 6M Cache/ 3.00 GHz/ 1333 MHz FSB,E5240,Discontinued,Q1'08,2,notFound,3.00 GHz,notFound,notFound
Intel Atom® Processor Z3740D 2M Cache/ up to 1.83 GHz,Z3740D,Discontinued,Q3'13,4,notFound,1.33 GHz,notFound,notFound
Intel® Core™ i5-12600T Processor 18M Cache/ up to 4.60 GHz,i5-12600T,Launched,Q1'22,6,12,notFound,4.60 GHz,notFound
Intel® Xeon® W-1270TE Processor 16M Cache/ up to 4.40 GHz,W-1270TE,Launched,Q2'20,8,16,2.00 GHz,4.40 GHz,notFound
Intel® Core™ i7-11700 Processor 16M Cache/ up to 4.90 GHz,i7-11700,Launched,Q1'21,8,16,2.50 GHz,4.90 GHz,4.80 GHz
Intel® Xeon® Processor X3430 8M Cache/ 2.40 GHz,X3430,Discontinued,Q3'09,4,4,2.40 GHz,2.80 GHz,notFound
Intel® Xeon Phi™ Coprocessor 7120P 16GB/ 1.238 GHz/ 61 core,7120P,Discontinued,Q2'13,61,notFound,1.24 GHz,1.33 GHz,notFound
Intel® Core™ i7-940 Processor 8M Cache/ 2.93 GHz/ 4.80 GT/s Intel® QPI,i7-940,Discontinued,Q4'08,4,8,2.93 GHz,3.20 GHz,notFound
Intel® Xeon® E-2278GEL Processor 16M Cache/ 2.00 GHz,E-2278GEL,Launched,Q2'19,8,16,2.00 GHz,3.90 GHz,3.90 GHz
Intel® Pentium® Processor G6950 3M Cache/ 2.80 GHz,G6950,Discontinued,Q1'10,2,2,2.80 GHz,notFound,notFound
Intel® Xeon® Processor L5530 8M Cache/ 2.40 GHz/ 5.86 GT/s Intel® QPI,L5530,Discontinued,Q3'09,4,8,2.40 GHz,2.66 GHz,notFound
Intel® Xeon® Processor E5-1660 15M Cache/ 3.30 GHz/ 0.0 GT/s Intel® QPI,E5-1660,Discontinued,Q1'12,6,12,3.30 GHz,3.90 GHz,3.90 GHz
Intel Atom® Processor P5962B 27M Cache/ 2.20 GHz,P5962B,Launched,Q1'20,24,24,2.20 GHz,notFound,notFound
Intel® Core™ i3-4000M Processor 3M Cache/ 2.40 GHz,i3-4000M,Discontinued,Q4'13,2,4,2.40 GHz,notFound,notFound
Intel® Core™ i9-12900K Processor 30M Cache/ up to 5.20 GHz,i9-12900K,Launched,Q4'21,16,24,notFound,5.20 GHz,notFound
Intel® Celeron® D Processor 345 256K Cache/ 3.06 GHz/ 533 MHz FSB,345,Discontinued,Q4'04,1,notFound,3.06 GHz,notFound,notFound
Intel® Core™ i3-5015U Processor 3M Cache/ 2.10 GHz,i3-5015U,Discontinued,Q1'15,2,4,2.10 GHz,notFound,notFound
Intel® Pentium® Processor A1018 1M Cache/ 2.10 GHz,A1018,Discontinued,Q3'13,2,2,2.10 GHz,notFound,notFound
Intel® Core™ i7-2677M Processor 4M Cache/ up to 2.90 GHz,i7-2677M,Discontinued,Q2'11,2,4,1.80 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i3-4370 Processor 4M Cache/ 3.80 GHz,i3-4370,Discontinued,Q3'14,2,4,3.80 GHz,notFound,notFound
Intel® Celeron® Processor E3400 1M Cache/ 2.60 GHz/ 800 MHz FSB,E3400,Discontinued,Q1'10,2,notFound,2.60 GHz,notFound,notFound
Intel® Core™ i3-2312M Processor 3M Cache/ 2.10 GHz,i3-2312M,Discontinued,Q2'11,2,4,2.10 GHz,notFound,notFound
Intel® Pentium® D Processor 830 2M Cache/ 3.00 GHz/ 800 MHz FSB,830,Discontinued,Q2'05,2,notFound,3.00 GHz,notFound,notFound
Intel® Xeon® Processor E7-4830 v4 35M Cache/ 2.00 GHz,E7-4830V4,Launched,Q2'16,14,28,2.00 GHz,2.80 GHz,2.80 GHz
Intel® Xeon® Processor X7350 8M Cache/ 2.93 GHz/ 1066 MHz FSB,X7350,Discontinued,Q3'07,4,notFound,2.93 GHz,notFound,notFound
Intel® Pentium® Processor G860 3M Cache/ 3.00 GHz,G860,Discontinued,Q3'11,2,2,3.00 GHz,notFound,notFound
Intel® Core™ i3-2310E Processor 3M Cache/ 2.10 GHz,i3-2310E,Discontinued,Q1'11,2,4,2.10 GHz,notFound,notFound
Intel® Core™ i7-10700F Processor 16M Cache/ up to 4.80 GHz,i7-10700F,Launched,Q2'20,8,16,2.90 GHz,4.80 GHz,4.70 GHz
Intel® Celeron® Processor G1620T 2M Cache/ 2.40 GHz,G1620T,Discontinued,Q3'13,2,2,2.40 GHz,notFound,notFound
Intel® Core™ i7-3930K Processor 12M Cache/ up to 3.80 GHz,i7-3930K,Discontinued,Q4'11,6,12,3.20 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Processor E3-1270 v6 8M Cache/ 3.80 GHz,E3-1270V6,Launched,Q1'17,4,8,3.80 GHz,4.20 GHz,4.20 GHz
Intel® Xeon® D-2173IT Processor 19.25M Cache/ 1.70 GHz,D-2173IT,Launched,Q1'18,14,28,1.70 GHz,3.00 GHz,notFound
Intel® Xeon® Gold 6130T Processor 22M Cache/ 2.10 GHz,6130T,Launched,Q3'17,16,32,2.10 GHz,3.70 GHz,notFound
Intel® Celeron® D Processor 347 512K Cache/ 3.06 GHz/ 533 MHz FSB,347,Discontinued,Q4'06,1,notFound,3.06 GHz,notFound,notFound
Intel® Core™ i7-8559U Processor 8M Cache/ up to 4.50 GHz,i7-8559U,Launched,Q2'18,4,8,2.70 GHz,4.50 GHz,4.50 GHz
Intel® Core™ i7-8559U Processor 8M Cache/ up to 4.50 GHz,i7-8559U,Launched,Q2'18,4,8,2.70 GHz,4.50 GHz,4.50 GHz
Intel® Core™2 Duo Processor E8400 6M Cache/ 3.00 GHz/ 1333 MHz FSB,E8400,Discontinued,Q1'08,2,notFound,3.00 GHz,notFound,notFound
Intel® Core™ i7-3970X Processor Extreme Edition 15M Cache/ up to 4.00 GHz,i7-3970X,Discontinued,Q4'12,6,12,3.50 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i9-7940X X-series Processor 19.25M Cache/ up to 4.30 GHz,i9-7940X,Discontinued,Q3'17,14,28,3.10 GHz,4.30 GHz,notFound
Intel® Core™ M-5Y10 Processor 4M Cache/ up to 2.00 GHz,5Y10,Discontinued,Q3'14,2,4,800 MHz,2.00 GHz,2.00 GHz
Intel® Core™ i5-3340 Processor 6M Cache/ up to 3.30 GHz,i5-3340,Discontinued,Q3'13,4,4,3.10 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i7-7800X X-series Processor 8.25M Cache/ up to 4.00 GHz,i7-7800X,Discontinued,Q2'17,6,12,3.50 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i7-2715QE Processor 6M Cache/ up to 3.00 GHz,i7-2715QE,Discontinued,Q1'11,4,8,2.10 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i7-660UE Processor 4M Cache/ 1.33 GHz,i7-660UE,Discontinued,Q1'10,2,4,1.33 GHz,2.40 GHz,notFound
Intel Atom® Processor Z3590 2M Cache/ up to 2.50 GHz,Z3590,Discontinued,Q3'15,4,notFound,notFound,notFound,notFound
Intel® Xeon® Processor E7-8894 v4 60M Cache/ 2.40 GHz,E7-8894V4,Launched,Q1'17,24,48,2.40 GHz,3.40 GHz,3.40 GHz
Intel® Celeron® Processor B810E 2M Cache/ 1.60 GHz,B810E,Discontinued,Q2'11,2,2,1.60 GHz,notFound,notFound
Intel® Xeon® Processor L5335 8M Cache/ 2.00 GHz/ 1333 MHz FSB,L5335,Discontinued,Q3'07,4,notFound,2.00 GHz,notFound,notFound
Intel® Pentium® D Processor 840 2M Cache/ 3.20 GHz/ 800 MHz FSB,840,Discontinued,Q2'05,2,notFound,3.20 GHz,notFound,notFound
Intel® Celeron® Processor 887 2M Cache/ 1.50 GHz,887,Discontinued,Q3'12,2,2,1.50 GHz,notFound,notFound
Intel® Core™2 Duo Processor T9300 6M Cache/ 2.50 GHz/ 800 MHz FSB,T9300,Discontinued,Q1'08,2,notFound,2.50 GHz,notFound,notFound
Intel® Xeon® Processor X5687 12M Cache/ 3.60 GHz/ 6.40 GT/s Intel® QPI,X5687,Discontinued,Q1'11,4,8,3.60 GHz,3.86 GHz,notFound
Intel® Xeon® Gold 6138T Processor 27.5M Cache/ 2.00 GHz,6138T,Launched,Q3'17,20,40,2.00 GHz,3.70 GHz,notFound
Intel® Core™ i3-8100H Processor 6M Cache/ 3.00 GHz,i3-8100H,Launched,Q3'18,4,4,3.00 GHz,notFound,notFound
Intel® Core™ i9-10900F Processor 20M Cache/ up to 5.20 GHz,i9-10900F,Launched,Q2'20,10,20,2.80 GHz,5.20 GHz,5.00 GHz
Intel® Xeon® Processor E3-1505L v6 8M Cache/ 2.20 GHz,E3-1505LV6,Launched,Q1'17,4,8,2.20 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i7-990X Processor Extreme Edition 12M Cache/ 3.46 GHz/ 6.40 GT/s Intel® QPI,i7-990X,Discontinued,Q1'11,6,12,3.46 GHz,3.73 GHz,notFound
Intel® Pentium® D Processor 960 4M Cache/ 3.60 GHz/ 800 MHz FSB,960,Discontinued,Q2'06,2,notFound,3.60 GHz,notFound,notFound
Intel® Celeron® Processor ULV 763 1M Cache/ 1.40 GHz/ 800 MHz FSB,763,Discontinued,Q1'11,1,notFound,1.40 GHz,notFound,notFound
Intel® Core™ i3-8130U Processor 4M Cache/ up to 3.40 GHz,i3-8130U,Launched,Q1'18,2,4,2.20 GHz,3.40 GHz,3.40 GHz
Intel® Pentium® Processor 3550M 2M Cache/ 2.30 GHz,3550M,Discontinued,Q4'13,2,2,2.30 GHz,notFound,notFound
Intel® Core™ m5-6Y54 Processor 4M Cache/ up to 2.70 GHz,M5-6Y54,Discontinued,Q3'15,2,4,1.10 GHz,2.70 GHz,2.70 GHz
Intel® Xeon® D-2177NT Processor 19.25M Cache/ 1.90 GHz,D-2177NT,Launched,Q1'18,14,28,1.90 GHz,3.00 GHz,notFound
Intel® Core™ i5-10400H Processor 8M Cache/ up to 4.60 GHz,i5-10400H,Launched,Q2'20,4,8,2.60 GHz,4.60 GHz,4.60 GHz
Intel® Core™ i7-10700 Processor 16M Cache/ up to 4.80 GHz,i7-10700,Launched,Q2'20,8,16,2.90 GHz,4.80 GHz,4.70 GHz
Intel® Xeon Phi™ Processor 7230 16GB/ 1.30 GHz/ 64 core,7230,Discontinued,Q2'16,64,notFound,1.30 GHz,1.50 GHz,notFound
Intel® Core™2 Extreme Processor QX9650 12M Cache/ 3.00 GHz/ 1333 MHz FSB,QX9650,Discontinued,Q4'07,4,notFound,3.00 GHz,notFound,notFound
Intel® Celeron® Processor 2950M 2M Cache/ 2.00 GHz,2950M,Discontinued,Q4'13,2,2,2.00 GHz,notFound,notFound
Intel® Xeon® Processor X5690 12M Cache/ 3.46 GHz/ 6.40 GT/s Intel® QPI,X5690,Discontinued,Q1'11,6,12,3.46 GHz,3.73 GHz,notFound
Intel® Core™2 Duo Processor SP9300 6M Cache/ 2.26 GHz/ 1066 MHz FSB,SP9300,Discontinued,Q3'08,2,notFound,2.26 GHz,notFound,notFound
Intel® Core™ i3-1115G4 Processor 6M Cache/  up to 4.10 GHz/ with IPU,i3-1115G4,Launched,Q3'20,2,4,notFound,4.10 GHz,notFound
Intel® Core™ i5-2430M Processor 3M Cache/ up to 3.00 GHz,i5-2430M,Discontinued,Q4'11,2,4,2.40 GHz,3.00 GHz,3.00 GHz
Intel® Xeon® Processor E5607 8M Cache/ 2.26 GHz/ 4.80 GT/s Intel® QPI,E5607,Discontinued,Q1'11,4,4,2.26 GHz,notFound,notFound
Intel® Itanium® Processor 9550 32M Cache/ 2.40 GHz,9550,Discontinued,Q4'12,4,8,2.40 GHz,notFound,notFound
Intel® Celeron® Processor 1017U 2M Cache/ 1.60 GHz,1017U,Discontinued,Q3'13,2,2,1.60 GHz,notFound,notFound
Intel® Core™ i3-8100B Processor 4M Cache/ 3.60 GHz,i3-8100B,Launched,Q3'18,4,4,3.60 GHz,notFound,notFound
Intel® Core™ i3-7320 Processor 4M Cache/ 4.10 GHz,i3-7320,Discontinued,Q1'17,2,4,4.10 GHz,notFound,notFound
Intel® Xeon Phi™ Processor 7210 16GB/ 1.30 GHz/ 64 core,7210,Discontinued,Q2'16,64,notFound,1.30 GHz,1.50 GHz,notFound
Intel® Xeon® Processor E5-2699 v4 55M Cache/ 2.20 GHz,E5-2699V4,Launched,Q1'16,22,44,2.20 GHz,3.60 GHz,3.60 GHz
Intel Atom® Processor E3825 1M Cache/ 1.33 GHz,E3825,Launched,Q4'13,2,2,1.33 GHz,notFound,notFound
Intel® Core™ i5-10310U Processor 6M Cache/ up to 4.40 GHz,i5-10310U,Launched,Q2'20,4,8,1.70 GHz,4.40 GHz,notFound
Intel® Core™ i5-10600K Processor 12M Cache/ up to 4.80 GHz,i5-10600K,Launched,Q2'20,6,12,4.10 GHz,4.80 GHz,4.80 GHz
Intel® Core™ i5-4288U Processor 3M Cache/ up to 3.10 GHz,i5-4288U,Discontinued,Q3'13,2,4,2.60 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® E-2286M Processor 16M Cache/ 2.40 GHz,E-2286M,Launched,Q2'19,8,16,2.40 GHz,5.00 GHz,notFound
Intel® Xeon® E-2286M Processor 16M Cache/ 2.40 GHz,E-2286M,Launched,Q2'19,8,16,2.40 GHz,5.00 GHz,notFound
Intel® Xeon® Processor EC5549 8M Cache/ 2.53 GHz/ 5.87 GT/s Intel® QPI,EC5549,Discontinued,Q1'10,4,8,2.53 GHz,2.93 GHz,notFound
Intel® Xeon® Processor E3-1220 v6 8M Cache/ 3.00 GHz,E3-1220V6,Launched,Q1'17,4,4,3.00 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® D-2143IT Processor 11M Cache/ 2.20 GHz,D-2143IT,Launched,Q1'18,8,16,2.20 GHz,3.00 GHz,notFound
Intel® Pentium® Gold G7400 Processor 6M Cache/ 3.70 GHz,G7400,Launched,Q1'22,2,4,notFound,notFound,notFound
Intel® Xeon Phi™ Coprocessor 3120P 6GB/ 1.100 GHz/ 57 core,3120P,Discontinued,Q2'13,57,notFound,1.10 GHz,notFound,notFound
Intel® Pentium® Processor G2100T 3M Cache/ 2.60 GHz,G2100T,Discontinued,Q3'12,2,2,2.60 GHz,notFound,notFound
Intel® Core™ i7-965 Processor Extreme Edition 8M Cache/ 3.20 GHz/ 6.40 GT/s Intel® QPI,i7-965,Discontinued,Q4'08,4,8,3.20 GHz,3.46 GHz,notFound
Intel® Xeon® Processor E5-1620 v3 10M Cache/ 3.50 GHz,E5-1620V3,Discontinued,Q3'14,4,8,3.50 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® Processor L5238 6M Cache/ 2.66 GHz/ 1333 MHz FSB,L5238,Discontinued,Q1'08,2,notFound,2.66 GHz,notFound,notFound
Intel® Core™ i7-4790S Processor 8M Cache/ up to 4.00 GHz,i7-4790S,Launched,Q2'14,4,8,3.20 GHz,4.00 GHz,4.00 GHz
Intel® Celeron® Processor N3010 2M Cache/ up to 2.24 GHz,N3010,Launched,Q1'16,2,2,1.04 GHz,notFound,notFound
Intel® Xeon® W-1270E Processor 16M Cache/ up to 4.80 GHz,W-1270E,Launched,Q2'20,8,16,3.40 GHz,4.80 GHz,notFound
Intel® Core™ i5-11600T Processor 12M Cache/ up to 4.10 GHz,i5-11600T,Launched,Q1'21,6,12,1.70 GHz,4.10 GHz,4.10 GHz
Intel® Core™ i3-4360T Processor 4M Cache/ 3.20 GHz,i3-4360T,Discontinued,Q3'14,2,4,3.20 GHz,notFound,notFound
Intel® Core™ i7-2617M Processor 4M Cache/ up to 2.60 GHz,i7-2617M,Discontinued,Q1'11,2,4,1.50 GHz,2.60 GHz,2.60 GHz
Intel® Celeron® Processor E3500 1M Cache/ 2.70 GHz/ 800 MHz FSB,E3500,Discontinued,Q3'10,2,notFound,2.70 GHz,notFound,notFound
Intel® Core™ i3-2330E Processor 3M Cache/ 2.20 GHz,i3-2330E,Discontinued,Q2'11,2,4,2.20 GHz,notFound,notFound
Intel® Core™ i5-3317U Processor 3M Cache/ up to 2.60 GHz,i5-3317U,Discontinued,Q2'12,2,4,1.70 GHz,2.60 GHz,2.60 GHz
Intel® Xeon® Platinum 8176 Processor 38.5M Cache/ 2.10 GHz,8176,Launched,Q3'17,28,56,2.10 GHz,3.80 GHz,notFound
Intel® Xeon® Processor E5-1620 10M Cache/ 3.60 GHz/ 0.0 GT/s Intel® QPI,E5-1620,Discontinued,Q1'12,4,8,3.60 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i9-12900F Processor 30M Cache/ up to 5.10 GHz,i9-12900F,Launched,Q1'22,16,24,notFound,5.10 GHz,notFound
Intel® Core™ i3-4005U Processor 3M Cache/ 1.70 GHz,i3-4005U,Discontinued,Q3'13,2,4,1.70 GHz,notFound,notFound
Intel® Celeron® D Processor 341 256K Cache/ 2.93 GHz/ 533 MHz FSB,341,Discontinued,Q2'04,1,notFound,2.93 GHz,notFound,notFound
Intel® Core™ i3-5020U Processor 3M Cache/ 2.20 GHz,i3-5020U,Discontinued,Q1'15,2,4,2.20 GHz,notFound,notFound
Intel® Xeon® W-1290E Processor 20M Cache/ up to 4.80 GHz,W-1290E,Launched,Q2'20,10,20,3.50 GHz,4.80 GHz,notFound
Intel® Xeon® Processor E5-1630 v3 10M Cache/ 3.70 GHz,E5-1630V3,Discontinued,Q3'14,4,8,3.70 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i5-12600H Processor 18M Cache/ up to 4.50 GHz,i5-12600H,Launched,Q1'22,12,16,notFound,notFound,notFound
Intel® Core™ i5-11500HE Processor 12M Cache/ up to 4.50 GHz,i5-11500HE,Launched,Q3'21,6,12,notFound,4.50 GHz,notFound
Intel® Core™ i7-3920XM Processor Extreme Edition 8M Cache/ up to 3.80 GHz,i7-3920XM,Discontinued,Q2'12,4,8,2.90 GHz,3.80 GHz,3.80 GHz
Intel® Core™2 Quad Processor Q9505S 6M Cache/ 2.83 GHz/ 1333 MHz FSB,Q9505S,Discontinued,Q3'09,4,notFound,2.83 GHz,notFound,notFound
Intel® Pentium® Processor E5400 2M Cache/ 2.70 GHz/ 800 MHz FSB,E5400,Discontinued,Q1'09,2,notFound,2.70 GHz,notFound,notFound
Intel® Xeon® W-2155 Processor 13.75M Cache/ 3.30 GHz,W-2155,Launched,Q3'17,10,20,3.30 GHz,4.50 GHz,notFound
Intel® Celeron® Processor 1019Y 2M Cache/ 1.00 GHz,1019Y,Discontinued,Q2'13,2,2,1.00 GHz,notFound,notFound
Intel Atom® Processor P5921B 9M Cache/ 2.20 GHz,P5921B,Launched,Q1'20,8,8,2.20 GHz,notFound,notFound
Intel® Celeron® Processor G6900TE 4M Cache/ 2.40 GHz,G6900TE,Launched,Q1'22,2,2,notFound,notFound,notFound
Intel® Core™ i5-4410E Processor 3M Cache/ up to 2.90 GHz,i5-4410E,Launched,Q2'14,2,4,2.90 GHz,notFound,notFound
Intel® Xeon® Processor E5-1620 v4 10M Cache/ 3.50 GHz,E5-1620V4,Launched,Q2'16,4,8,3.50 GHz,3.80 GHz,notFound
Intel® Xeon® E-2226GE Processor 12M Cache/ 3.40 GHz,E-2226GE,Launched,Q2'19,6,6,3.40 GHz,4.60 GHz,4.60 GHz
Intel® Core™ i5-8250U Processor 6M Cache/ up to 3.40 GHz,i5-8250U,Launched,Q3'17,4,8,1.60 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i7-5930K Processor 15M Cache/ up to 3.70 GHz,i7-5930K,Discontinued,Q3'14,6,12,3.50 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® W-2235 Processor 8.25M Cache/ 3.80 GHz,W-2235,Launched,Q4'19,6,12,3.80 GHz,4.60 GHz,notFound
Intel® Core™2 Duo Processor E8300 6M Cache/ 2.83 GHz/ 1333 MHz FSB,E8300,Discontinued,Q2'08,2,notFound,2.83 GHz,notFound,notFound
Intel® Core™ i3-3110M Processor 3M Cache/ 2.40 GHz,i3-3110M,Discontinued,Q2'12,2,4,2.40 GHz,notFound,notFound
Intel® Core™ i7-2649M Processor 4M Cache/ up to 3.20 GHz,i7-2649M,Discontinued,Q1'11,2,4,2.30 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i3-4360 Processor 4M Cache/ 3.70 GHz,i3-4360,Launched,Q2'14,2,4,3.70 GHz,notFound,notFound
Intel® Core™ i3-2330M Processor 3M Cache/ 2.20 GHz,i3-2330M,Discontinued,Q2'11,2,4,2.20 GHz,notFound,notFound
Intel® Core™ i7-12700T Processor 25M Cache/ up to 4.70 GHz,i7-12700T,Launched,Q1'22,12,20,notFound,4.70 GHz,notFound
Intel® Core™ i9-9940X X-series Processor 19.25M Cache/ up to 4.50 GHz,i9-9940X,Discontinued,Q4'18,14,28,3.30 GHz,4.40 GHz,notFound
Intel® Core™ i3-5010U Processor 3M Cache/ 2.10 GHz,i3-5010U,Launched,Q1'15,2,4,2.10 GHz,notFound,notFound
Intel® Core™ i3-5010U Processor 3M Cache/ 2.10 GHz,i3-5010U,Launched,Q1'15,2,4,2.10 GHz,notFound,notFound
Intel® Xeon® Processor X5270 6M Cache/ 3.50 GHz/ 1333 MHz FSB,X5270,Discontinued,Q3'08,2,notFound,3.50 GHz,notFound,notFound
Intel® Celeron® Processor N2940 2M Cache/ up to 2.25 GHz,N2940,Discontinued,Q3'14,4,4,1.83 GHz,notFound,notFound
Intel® Core™ i5-750S Processor 8M Cache/ 2.40 GHz,i5-750S,Discontinued,Q1'10,4,4,2.40 GHz,3.20 GHz,notFound
Intel® Core™ i7-3615QE Processor 6M Cache/ up to 3.30 GHz,i7-3615QE,Launched,Q2'12,4,8,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Celeron® Processor 3205U 2M Cache/ 1.50 GHz,3205U,Discontinued,Q1'15,2,2,1.50 GHz,notFound,notFound
Intel® Xeon® Platinum 8170 Processor 35.75M Cache/ 2.10 GHz,8170,Launched,Q3'17,26,52,2.10 GHz,3.70 GHz,notFound
Intel® Core™ i7-2637M Processor 4M Cache/ up to 2.80 GHz,i7-2637M,Discontinued,Q2'11,2,4,1.70 GHz,2.80 GHz,2.80 GHz
Intel® Core™2 Quad Processor Q8200S 4M Cache/ 2.33 GHz/ 1333 MHz FSB,Q8200S,Discontinued,Q1'09,4,notFound,2.33 GHz,notFound,notFound
Intel Atom® x6211E Processor 1.5M Cache/ up to 3.00 GHz,6211E,Launched,Q1'21,2,2,1.30 GHz,notFound,notFound
Intel® Xeon® Gold 6240R Processor 35.75M Cache/ 2.40 GHz,6240R,Launched,Q1'20,24,48,2.40 GHz,4.00 GHz,notFound
Intel® Core™ i7-1060NG7 Processor 8M Cache/ up to 3.80 GHz,i7-1060NG7,Launched,Q2'20,4,8,1.20 GHz,3.80 GHz,notFound
Intel® Core™ i5-11600KF Processor 12M Cache/ up to 4.90 GHz,i5-11600KF,Launched,Q1'21,6,12,3.90 GHz,4.90 GHz,4.90 GHz
Intel® Xeon® Processor E5-2450L 20M Cache/ 1.80 GHz/ 8.00 GT/s Intel® QPI,E5-2450L,Discontinued,Q2'12,8,16,1.80 GHz,2.30 GHz,2.30 GHz
Intel® Celeron® D Processor 330/330J 256K Cache/ 2.66 GHz/ 533 MHz FSB,330,Discontinued,Q2'04,1,notFound,2.66 GHz,notFound,notFound
Intel® Core™ i7-4790 Processor 8M Cache/ up to 4.00 GHz,i7-4790,Discontinued,Q2'14,4,8,3.60 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i7-920 Processor 8M Cache/ 2.66 GHz/ 4.80 GT/s Intel® QPI,i7-920,Discontinued,Q4'08,4,8,2.66 GHz,2.93 GHz,notFound
Intel® Xeon® Platinum 8358 Processor 48M Cache/ 2.60 GHz,8358,Launched,Q2'21,32,64,2.60 GHz,3.40 GHz,notFound
Intel® Xeon® Processor X3440 8M Cache/ 2.53 GHz,X3440,Discontinued,Q3'09,4,8,2.53 GHz,2.93 GHz,notFound
Intel® Pentium® D Processor 920 4M Cache/ 2.8 GHz/ 800 MHz FSB,920,Discontinued,Q1'06,2,notFound,2.80 GHz,notFound,notFound
Intel® Core™ i7-8700B Processor 12M Cache/ up to 4.60 GHz,i7-8700B,Launched,Q2'18,6,12,3.20 GHz,4.60 GHz,4.60 GHz
Intel® Xeon® Silver 4210T Processor 13.75M Cache/ 2.30 GHz,4210T,Launched,Q1'20,10,20,2.30 GHz,3.20 GHz,notFound
Intel Atom® x6212RE Processor 1.5M Cache/ 1.20 GHz,6212RE,Launched,Q1'21,2,2,1.20 GHz,notFound,notFound
Intel® Xeon® Platinum 8160 Processor 33M Cache/ 2.10 GHz,8160,Launched,Q3'17,24,48,2.10 GHz,3.70 GHz,notFound
Intel® Core™ i3-4110E Processor 3M Cache/ 2.60 GHz,i3-4110E,Launched,Q2'14,2,4,2.60 GHz,notFound,notFound
Intel® Core™ i5-8350U Processor 6M Cache/ up to 3.60 GHz,i5-8350U,Launched,Q3'17,4,8,1.70 GHz,3.60 GHz,3.60 GHz
Intel® Celeron® Processor N2840 1M Cache/ up to 2.58 GHz,N2840,Discontinued,Q3'14,2,2,2.16 GHz,notFound,notFound
Intel® Core™ i7-12700 Processor 25M Cache/ up to 4.90 GHz,i7-12700,Launched,Q1'22,12,20,notFound,4.90 GHz,notFound
Intel® Core™ i7-9800X X-series Processor 16.5M Cache/ up to 4.50 GHz,i7-9800X,Discontinued,Q4'18,8,16,3.80 GHz,4.40 GHz,notFound
Intel® Pentium® Gold 5405U Processor 2M Cache/ 2.30 GHz,5405U,Launched,Q1'19,2,4,2.30 GHz,notFound,notFound
Intel® Pentium® M Processor 725 2M Cache/ 1.60A GHz/ 400 MHz FSB,725,Discontinued,Q2'04,1,notFound,1.60 GHz,notFound,notFound
Intel® Core™2 Solo Processor SU3500 3M Cache/ 1.30 GHz/ 800 MHz FSB,SU3500,Discontinued,Q2'09,1,notFound,1.30 GHz,notFound,notFound
Intel® Xeon® Processor E5-2630L v2 15M Cache/ 2.40 GHz,E5-2630LV2,Discontinued,Q3'13,6,12,2.40 GHz,2.80 GHz,2.80 GHz
Intel® Xeon® Gold 6338 Processor 48M Cache/ 2.00 GHz,6338,Launched,Q2'21,32,64,2.00 GHz,3.20 GHz,notFound
Intel® Pentium® Gold 6500Y Processor 4M Cache/ up to 3.40 GHz,6500Y,Launched,Q1'21,2,4,1.10 GHz,3.40 GHz,3.40 GHz
Intel® Pentium® Processor T2330 1M Cache/ 1.60 GHz/ 533 MHz FSB,T2330,Discontinued,Q4'07,2,notFound,1.60 GHz,notFound,notFound
Intel® Core™ i7-3820QM Processor 8M Cache/ up to 3.70 GHz,i7-3820QM,Discontinued,Q2'12,4,8,2.70 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i5-2557M Processor 3M Cache/ up to 2.70 GHz,i5-2557M,Discontinued,Q2'11,2,4,1.70 GHz,2.70 GHz,2.70 GHz
Intel® Quark™ SoC X1021D 16K Cache/ 400 MHz,X1021D,Discontinued,Q2'14,1,1,400 MHz,notFound,notFound
Intel® Xeon® Processor E3-1258L v4 6M Cache/ 1.80 GHz,E3-1258LV4,Launched,Q2'15,4,8,1.80 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® W-11865MRE Processor 24M Cache/ up to 4.70 GHz,W-11865MRE,Launched,Q3'21,8,16,notFound,4.70 GHz,notFound
Intel® Core™ i5-12600HE Processor 18M Cache/ up to 4.50 GHz,i5-12600HE,Launched,Q1'22,12,16,notFound,4.50 GHz,notFound
Intel® Celeron® Processor G1840T 2M Cache/ 2.50 GHz,G1840T,Discontinued,Q2'14,2,2,2.50 GHz,notFound,notFound
Intel® Celeron® D Processor 330J 256K Cache/ 2.66 GHz/ 533 MHz FSB,330J,Discontinued,Q4'04,1,notFound,2.66 GHz,notFound,notFound
Intel® Core™ i7-4930MX Processor Extreme Edition 8M Cache/ up to 3.90 GHz,i7-4930MX,Discontinued,Q2'13,4,8,3.00 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor E5-2420 15M Cache/ 1.90 GHz/ 7.20 GT/s Intel® QPI,E5-2420,Discontinued,Q2'12,6,12,1.90 GHz,2.40 GHz,notFound
Intel® Core™ i5-1035G4 Processor 6M Cache/ up to 3.70 GHz,i5-1035G4,Launched,Q3'19,4,8,1.10 GHz,3.70 GHz,notFound
Intel® Core™ i5-11400F Processor 12M Cache/ up to 4.40 GHz,i5-11400F,Launched,Q1'21,6,12,2.60 GHz,4.40 GHz,4.40 GHz
Intel® Celeron® Processor 1005M 2M Cache/ 1.90 GHz,1005M,Discontinued,Q3'13,2,2,1.90 GHz,notFound,notFound
Intel® Itanium® Processor 9540 24M Cache/ 2.13 GHz,9540,Discontinued,Q4'12,8,16,2.13 GHz,notFound,notFound
Intel® Xeon® Processor E5606 8M Cache/ 2.13 GHz/ 4.80 GT/s Intel® QPI,E5606,Discontinued,Q1'11,4,4,2.13 GHz,notFound,notFound
Intel® Core™ i7-1165G7 Processor 12M Cache/ up to 4.70 GHz/ with IPU,i7-1165G7,Launched,Q3'20,4,8,notFound,4.70 GHz,notFound
Intel® Core™ i7-1165G7 Processor 12M Cache/ up to 4.70 GHz/ with IPU,i7-1165G7,Launched,Q3'20,4,8,notFound,4.70 GHz,notFound
Intel® Xeon® Processor E3-1285 v6 8M Cache/ 4.10 GHz,E3-1285V6,Launched,Q3'17,4,8,4.10 GHz,4.50 GHz,4.50 GHz
Intel® Xeon® Processor X5675 12M Cache/ 3.06 GHz/ 6.40 GT/s Intel® QPI,X5675,Discontinued,Q1'11,6,12,3.06 GHz,3.46 GHz,notFound
Intel® Core™2 Duo Processor T9500 6M Cache/ 2.60 GHz/ 800 MHz FSB,T9500,Discontinued,Q1'08,2,notFound,2.60 GHz,notFound,notFound
Intel® Core™ i3-10305 Processor 8M Cache/ up to 4.50 GHz,i3-10305,Launched,Q1'21,4,8,3.80 GHz,4.50 GHz,4.50 GHz
Intel® Core™ i5-4258U Processor 3M Cache/ up to 2.90 GHz,i5-4258U,Discontinued,Q3'13,2,4,2.40 GHz,2.90 GHz,2.90 GHz
Intel® Xeon® D-2141I Processor 11M Cache/ 2.20 GHz,D-2141I,Launched,Q1'18,8,16,2.20 GHz,3.00 GHz,notFound
Intel® Xeon® Gold 6250 Processor 35.75M Cache/ 3.90 GHz,6250,Launched,Q1'20,8,16,3.90 GHz,4.50 GHz,notFound
Intel® Xeon® Processor E5420 12M Cache/ 2.50 GHz/ 1333 MHz FSB,E5420,Discontinued,Q4'07,4,notFound,2.50 GHz,notFound,notFound
Intel® Xeon® Processor E5-2660 v4 35M Cache/ 2.00 GHz,E5-2660V4,Launched,Q1'16,14,28,2.00 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i3-7100T Processor 3M Cache/ 3.40 GHz,i3-7100T,Discontinued,Q1'17,2,4,3.40 GHz,notFound,notFound
Intel® Xeon® Processor E5-2695 v4 45M Cache/ 2.10 GHz,E5-2695V4,Launched,Q1'16,18,36,2.10 GHz,3.30 GHz,3.30 GHz
Intel Atom® Processor E3845 2M Cache/ 1.91 GHz,E3845,Launched,Q4'13,4,4,1.91 GHz,notFound,notFound
Intel® Core™ i7-6950X Processor Extreme Edition 25M Cache/ up to 3.50 GHz,i7-6950X,Discontinued,Q2'16,10,20,3.00 GHz,3.50 GHz,notFound
Intel® Xeon® Processor W5580 8M Cache/ 3.20 GHz/ 6.40 GT/s Intel® QPI,W5580,Discontinued,Q1'09,4,8,3.20 GHz,3.46 GHz,notFound
Intel® Core™ i5-2510E Processor 3M Cache/ up to 3.10 GHz,i5-2510E,Discontinued,Q1'11,2,4,2.50 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Processor E5603 4M Cache/ 1.60 GHz/ 4.80 GT/s Intel® QPI,E5603,Discontinued,Q1'11,4,4,1.60 GHz,notFound,notFound
Intel® Core™ i9-10900 Processor 20M Cache/ up to 5.20 GHz,i9-10900,Launched,Q2'20,10,20,2.80 GHz,5.20 GHz,5.00 GHz
Intel® Core™2 Duo Processor SU9400 3M Cache/ 1.40 GHz/ 800 MHz FSB,SU9400,Discontinued,Q3'08,2,notFound,1.40 GHz,notFound,notFound
Intel® Core™2 Duo Processor U7700 2M Cache/ 1.33 GHz/ 533 MHz FSB Socket P,U7700,Discontinued,Q1'08,2,notFound,1.33 GHz,notFound,notFound
Intel® Xeon® Processor E5-2628L v4 30M Cache/ 1.90 GHz,E5-2628LV4,Launched,Q1'16,12,24,1.90 GHz,2.40 GHz,2.40 GHz
Intel® Pentium® Processor A1020 2M Cache/ up to 2.66 GHz,A1020,Discontinued,Q1'16,4,4,2.41 GHz,notFound,notFound
Intel® Xeon Phi™ Processor 7250 16GB/ 1.40 GHz/ 68 core,7250,Discontinued,Q2'16,68,notFound,1.40 GHz,1.60 GHz,notFound
Intel® Xeon® Gold 6256 Processor 33M Cache/ 3.60 GHz,6256,Launched,Q1'20,12,24,3.60 GHz,4.50 GHz,notFound
Intel® Core™ i7-3820 Processor 10M Cache/ up to 3.80 GHz,i7-3820,Discontinued,Q1'12,4,8,3.60 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® D-2163IT Processor 16.5M Cache/ 2.10 GHz,D-2163IT,Launched,Q1'18,12,24,2.10 GHz,3.00 GHz,notFound
Intel® Xeon® Processor E3-1225 v6 8M Cache/ 3.30 GHz,E3-1225V6,Launched,Q1'17,4,4,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i3-10105 Processor 6M Cache/ up to 4.40 GHz,i3-10105,Launched,Q1'21,4,8,3.70 GHz,4.40 GHz,4.40 GHz
Intel® Core™ i7-2670QM Processor 6M Cache/ up to 3.10 GHz,i7-2670QM,Discontinued,Q4'11,4,8,2.20 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Processor E5-2699R v4 55M Cache/ 2.20 GHz,E5-2699RV4,Launched,04'16,22,44,2.20 GHz,3.60 GHz,3.60 GHz
Intel® Pentium® D Processor 915 4M Cache/ 2.80 GHz/ 800 MHz FSB,915,Discontinued,Q3'06,2,notFound,2.80 GHz,notFound,notFound
Intel® Core™ i3-2365M Processor 3M Cache/ 1.40 GHz,i3-2365M,Discontinued,Q3'12,2,4,1.40 GHz,notFound,notFound
Intel® Xeon® Processor L5420 12M Cache/ 2.50 GHz/ 1333 MHz FSB,L5420,Discontinued,Q1'08,4,notFound,2.50 GHz,notFound,notFound
Intel® Core™2 Quad Processor Q6700 8M Cache/ 2.66 GHz/ 1066 MHz FSB,Q6700,Discontinued,Q3'07,4,notFound,2.66 GHz,notFound,notFound
Intel® Core™ i5-3340S Processor 6M Cache/ up to 3.30 GHz,i5-3340S,Discontinued,Q3'13,4,4,2.80 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i7-2610UE Processor 4M Cache/ up to 2.40 GHz,i7-2610UE,Discontinued,Q1'11,2,4,1.50 GHz,2.40 GHz,2.40 GHz
Intel® Core™2 Duo Processor T8100 3M Cache/ 2.10 GHz/ 800 MHz FSB,T8100,Discontinued,Q1'08,2,notFound,2.10 GHz,notFound,notFound
Intel® Pentium® Processor 997 2M Cache/ 1.60 GHz,997,Discontinued,Q3'12,2,2,1.60 GHz,notFound,notFound
Intel® Xeon® Platinum 8160T Processor 33M Cache/ 2.10 GHz,8160T,Launched,Q3'17,24,48,2.10 GHz,3.70 GHz,notFound
Intel® Xeon® Processor X5672 12M Cache/ 3.20 GHz/ 6.40 GT/s Intel® QPI,X5672,Discontinued,Q1'11,4,8,3.20 GHz,3.60 GHz,notFound
Intel® Core™ i7-2655LE Processor 4M Cache/ up to 2.90 GHz,i7-2655LE,Discontinued,Q1'11,2,4,2.20 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i7-3960X Processor Extreme Edition 15M Cache/ up to 3.90 GHz,i7-3960X,Discontinued,Q4'11,6,12,3.30 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® D-2166NT Processor 16.5M Cache/ 2.00 GHz,D-2166NT,Launched,Q1'18,12,24,2.00 GHz,3.00 GHz,notFound
Intel® Xeon® Processor E3-1275 v6 8M Cache/ 3.80 GHz,E3-1275V6,Launched,Q1'17,4,8,3.80 GHz,4.20 GHz,4.20 GHz
Intel® Celeron® Processor G1630 2M Cache/ 2.80 GHz,G1630,Discontinued,Q3'13,2,2,2.80 GHz,notFound,notFound
Intel® Xeon® Processor X3230 8M Cache/ 2.66 GHz/ 1066 MHz FSB,X3230,Discontinued,Q3'07,4,notFound,2.66 GHz,notFound,notFound
Intel® Pentium® D Processor 820 2M Cache/ 2.80 GHz/ 800 MHz FSB,820,Discontinued,Q2'05,2,notFound,2.80 GHz,notFound,notFound
Intel® Pentium® Processor G870 3M Cache/ 3.10 GHz,G870,Discontinued,Q2'12,2,2,3.10 GHz,notFound,notFound
Intel® Celeron® Processor 847E 2M Cache/ 1.10 GHz,847E,Discontinued,Q2'11,2,2,1.10 GHz,notFound,notFound
Intel® Core™ M-5Y10a Processor 4M Cache/ up to 2.00 GHz,5Y10a,Discontinued,Q3'14,2,4,800 MHz,2.00 GHz,2.00 GHz
Intel® Pentium® Silver N5000 Processor 4M Cache/ up to 2.70 GHz,N5000,Launched,Q4'17,4,4,1.10 GHz,notFound,notFound
Intel® Xeon® Silver 4108 Processor 11M Cache/ 1.80 GHz,4108,Launched,Q3'17,8,16,1.80 GHz,3.00 GHz,notFound
Intel® Celeron® D Processor 365 512K Cache/ 3.60 GHz/ 533 MHz FSB,365,Discontinued,Q1'07,1,notFound,3.60 GHz,notFound,notFound
Intel® Core™2 Duo Processor E8500 6M Cache/ 3.16 GHz/ 1333 MHz FSB,E8500,Discontinued,Q1'08,2,notFound,3.16 GHz,notFound,notFound
Intel® Xeon® Processor D-1577 24M Cache/ 1.30 GHz,D-1577,Launched,Q1'16,16,32,1.30 GHz,2.10 GHz,2.10 GHz
Intel® Xeon® E-2234 Processor 8M Cache/ 3.60 GHz,E-2234,Launched,Q2'19,4,8,3.60 GHz,4.80 GHz,4.80 GHz
Intel® Xeon® Processor X5680 12M Cache/ 3.33 GHz/ 6.40 GT/s Intel® QPI,X5680,Discontinued,Q1'10,6,12,3.33 GHz,3.60 GHz,notFound
Intel® Pentium® Processor E5500 2M Cache/ 2.80 GHz/ 800 MHz FSB,E5500,Discontinued,Q2'10,2,notFound,2.80 GHz,notFound,notFound
Intel® Core™ i5-7360U Processor 4M Cache/ up to 3.60 GHz,i5-7360U,Launched,Q1'17,2,4,2.30 GHz,3.60 GHz,3.60 GHz
Intel® Pentium® Processor B915C 3M Cache/ 1.50 GHz,B915C,Discontinued,Q2'12,2,4,1.50 GHz,notFound,notFound
Intel® Pentium® Processor G3220T 3M Cache/ 2.60 GHz,G3220T,Discontinued,Q3'13,2,2,2.60 GHz,notFound,notFound
Intel® Celeron® Processor J4125 4M Cache/ up to 2.70 GHz,J4125,Launched,Q4'19,4,4,2.00 GHz,notFound,notFound
Intel® Xeon® Processor E3-1220 v5 8M Cache/ 3.00 GHz,E3-1220V5,Discontinued,Q4'15,4,4,3.00 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® Gold 5222 Processor 16.5M Cache/ 3.80 GHz,5222,Launched,Q2'19,4,8,3.80 GHz,3.90 GHz,notFound
Intel® Core™ Duo Processor T2500 2M Cache/ 2.00 GHz/ 667 MHz FSB,T2500,Discontinued,Q1'06,2,notFound,2.00 GHz,notFound,notFound
Intel® Celeron® Processor G1820T 2M Cache/ 2.40 GHz,G1820T,Discontinued,Q1'14,2,2,2.40 GHz,notFound,notFound
Intel® Core™ i7-2700K Processor 8M Cache/ up to 3.90 GHz,i7-2700K,Discontinued,Q4'11,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Pentium® 4 Processor 520J supporting HT Technology 1M Cache/ 2.80 GHz/ 800 MHz FSB,520J,Discontinued,Q4'04,1,notFound,2.80 GHz,notFound,notFound
Intel® Core™ i7-840QM Processor 8M Cache/ 1.86 GHz,i7-840QM,Discontinued,Q3'10,4,8,1.86 GHz,3.20 GHz,notFound
Intel® Xeon® Processor X5677 12M Cache/ 3.46 GHz/ 6.40 GT/s Intel® QPI,X5677,Discontinued,Q1'10,4,8,3.46 GHz,3.73 GHz,notFound
Intel® Core™ i7-4930K Processor 12M Cache/ up to 3.90 GHz,i7-4930K,Discontinued,Q3'13,6,12,3.40 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i5-6500TE Processor 6M Cache/ up to 3.30 GHz,i5-6500TE,Launched,Q4'15,4,4,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Core™2 Duo Processor SL9600 6M Cache/ 2.13 GHz/ 1066 MHz FSB,SL9600,Discontinued,Q1'09,2,notFound,2.13 GHz,notFound,notFound
Intel® Xeon® W-3245M Processor 22M Cache/ 3.20 GHz,W-3245M,Launched,Q2'19,16,32,3.20 GHz,4.40 GHz,notFound
Intel® Core™ i7-8665U Processor 8M Cache/ up to 4.80 GHz,i7-8665U,Launched,Q2'19,4,8,1.90 GHz,4.80 GHz,notFound
Intel® Core™ i7-8665U Processor 8M Cache/ up to 4.80 GHz,i7-8665U,Launched,Q2'19,4,8,1.90 GHz,4.80 GHz,notFound
Intel® Core™ i5-7442EQ Processor 6M Cache/ up to 2.90 GHz,i5-7442EQ,Launched,Q1'17,4,4,2.10 GHz,2.90 GHz,2.90 GHz
Intel® Celeron® Processor 725C 1.5M Cache/ 1.30 GHz,725C,Discontinued,Q2'12,1,2,1.30 GHz,notFound,notFound
Intel® Pentium® Processor E6600 2M Cache/ 3.06 GHz/ 1066 FSB,E6600,Discontinued,Q1'10,2,notFound,3.06 GHz,notFound,notFound
Intel® Xeon® Processor E5-2438L v3 25M Cache/ 1.80 GHz,E5-2438LV3,Launched,Q1'15,10,20,1.80 GHz,notFound,notFound
Intel® Xeon® Processor X3480 8M Cache/ 3.06 GHz,X3480,Discontinued,Q2'10,4,8,3.06 GHz,3.73 GHz,notFound
Intel® Core™ i5-8600 Processor 9M Cache/ up to 4.30 GHz,i5-8600,Discontinued,Q2'18,6,6,3.10 GHz,4.30 GHz,4.30 GHz
Intel® Xeon® Processor E3-1575M v5 8M Cache/ 3.00 GHz,E3-1575MV5,Launched,Q1'16,4,8,3.00 GHz,3.90 GHz,3.90 GHz
Intel® Pentium® 4 Processor 519K 1M Cache/ 3.06 GHz/ 533 MHz FSB,519K,Discontinued,Q4'04,1,notFound,3.06 GHz,notFound,notFound
Intel® Xeon® Gold 5218B Processor 22M Cache/ 2.30 GHz,5218B,Launched,Q2'19,16,32,2.30 GHz,3.90 GHz,notFound
Intel® Core™ i3-6100TE Processor 4M Cache/ 2.70 GHz,i3-6100TE,Launched,Q4'15,2,4,2.70 GHz,notFound,notFound
Intel® Xeon® Processor E5205 6M Cache/ 1.86 GHz/ 1066 MHz FSB,E5205,Discontinued,Q4'07,2,notFound,1.86 GHz,notFound,notFound
Intel® Core™ i3-6300T Processor 4M Cache/ 3.30 GHz,i3-6300T,Discontinued,Q3'15,2,4,3.30 GHz,notFound,notFound
Intel® Core™ i7-720QM Processor 6M Cache/ 1.60 GHz,i7-720QM,Discontinued,Q3'09,4,8,1.60 GHz,2.80 GHz,notFound
Intel® Pentium® 4 Processor 540J supporting HT Technology 1M Cache/ 3.20 GHz/ 800 MHz FSB,540J,Discontinued,Q4'05,1,notFound,3.20 GHz,notFound,notFound
Intel® Core™2 Extreme Processor QX9300 12M Cache/ 2.53 GHz/ 1066 MHz FSB,QX9300,Discontinued,Q3'08,4,notFound,2.53 GHz,notFound,notFound
Intel® Core™ i7-930 Processor 8M Cache/ 2.80 GHz/ 4.80 GT/s Intel® QPI,i7-930,Discontinued,Q1'10,4,8,2.80 GHz,3.06 GHz,notFound
Intel® Core™2 Extreme Processor X7900 4M Cache/ 2.80 GHz/ 800 MHz FSB,X7900,Discontinued,Q3'07,2,notFound,2.80 GHz,notFound,notFound
Intel® Xeon® Gold 6244 Processor 24.75M Cache/ 3.60 GHz,6244,Launched,Q2'19,8,16,3.60 GHz,4.40 GHz,notFound
Intel® Xeon® Processor E3-1246 v3 8M Cache/ 3.50 GHz,E3-1246V3,Discontinued,Q2'14,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i5-650 Processor 4M Cache/ 3.20 GHz,i5-650,Discontinued,Q1'10,2,4,3.20 GHz,3.46 GHz,notFound
Intel® Pentium® Processor G3220 3M Cache/ 3.00 GHz,G3220,Discontinued,Q3'13,2,2,3.00 GHz,notFound,notFound
Intel® Xeon® Processor E3-1260L v5 8M Cache/ 2.90 GHz,E3-1260LV5,Launched,Q4'15,4,8,2.90 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor L5630 12M Cache/ 2.13 GHz/ 5.86 GT/s Intel® QPI,L5630,Discontinued,Q1'10,4,8,2.13 GHz,2.40 GHz,notFound
Intel® Core™ i5-6600 Processor 6M Cache/ up to 3.90 GHz,i5-6600,Discontinued,Q3'15,4,4,3.30 GHz,3.90 GHz,3.90 GHz
Intel Atom® x7-Z8750 Processor 2M Cache/ up to 2.56 GHz,x7-Z8750,Launched,Q1'16,4,notFound,1.60 GHz,notFound,notFound
Intel Atom® Processor D2700 1M Cache/ 2.13 GHz,D2700,Discontinued,Q3'11,2,4,2.13 GHz,notFound,notFound
Intel® Xeon® Processor E7540 18M Cache/ 2.00 GHz/ 6.40 GT/s Intel® QPI,E7540,Discontinued,Q1'10,6,12,2.00 GHz,2.27 GHz,notFound
Intel® Celeron® Processor 847 2M Cache/ 1.10 GHz,847,Discontinued,Q2'11,2,notFound,1.10 GHz,notFound,notFound
Intel® Xeon® Platinum 8260Y Processor 35.75M Cache/ 2.40 GHz,8260Y,Launched,Q2'19,24,48,2.40 GHz,3.90 GHz,notFound
Intel® Xeon® E-2224G Processor 8M Cache/ 3.50 GHz,E-2224G,Launched,Q2'19,4,4,3.50 GHz,4.70 GHz,4.70 GHz
Intel® Xeon® Processor W3670 12M Cache/ 3.20 GHz/ 4.80 GT/s Intel® QPI,W3670,Discontinued,Q3'10,6,12,3.20 GHz,3.46 GHz,notFound
Intel® Xeon® W-3375 Processor 57M Cache/ up to 4.00 GHz,W-3375,Launched,Q3'21,38,76,2.50 GHz,4.00 GHz,notFound
Intel® Pentium® Processor B950 2M Cache/ 2.10 GHz,B950,Discontinued,Q2'11,2,2,2.10 GHz,notFound,notFound
Intel® Xeon® Platinum 8260 Processor 35.75M Cache/ 2.40 GHz,8260,Launched,Q2'19,24,48,2.40 GHz,3.90 GHz,notFound
Intel® Core™ i3-10105F Processor 6M Cache/ up to 4.40 GHz,i3-10105F,Launched,Q1'21,4,8,3.70 GHz,4.40 GHz,4.40 GHz
Intel® Xeon® Processor W5590 8M Cache/ 3.33 GHz/ 6.40 GT/s Intel® QPI,W5590,Discontinued,Q3'09,4,8,3.33 GHz,3.60 GHz,notFound
Intel® Pentium® 4 Processor 506 1M Cache/ 2.66 GHz/ 533 MHz FSB,506,Discontinued,Q2'05,1,notFound,2.66 GHz,notFound,notFound
Intel® Xeon® Processor E7440 16M Cache/ 2.40 GHz/ 1066 MHz FSB,E7440,Discontinued,Q3'08,4,notFound,2.40 GHz,notFound,notFound
Intel® Core™ i3-4340TE Processor 4M Cache/ 2.60 GHz,i3-4340TE,Launched,Q2'14,2,4,2.60 GHz,notFound,notFound
Intel® Pentium® 4 Processor 550 supporting HT Technology 1M Cache/ 3.40 GHz/ 800 MHz FSB,550,Discontinued,Q2'04,1,notFound,3.40 GHz,notFound,notFound
Intel® Celeron® Processor 430 512K Cache/ 1.80 GHz/ 800 MHz FSB,430,Discontinued,Q2'07,1,notFound,1.80 GHz,notFound,notFound
Intel® Xeon® Processor X5670 12M Cache/ 2.93 GHz/ 6.40 GT/s Intel® QPI,X5670,Discontinued,Q1'10,6,12,2.93 GHz,3.33 GHz,notFound
Intel Atom® Processor Z3460 1M Cache/ up to 1.60 GHz,Z3460,Discontinued,Q1'14,2,notFound,notFound,notFound,notFound
Intel® Pentium® 4 Processor 517 supporting HT Technology 1M Cache/ 2.93 GHz/ 533 MHz FSB,517,Discontinued,Q3'05,1,notFound,2.93 GHz,notFound,notFound
Intel® Core™ i5-8500 Processor 9M Cache/ up to 4.10 GHz,i5-8500,Launched,Q2'18,6,6,3.00 GHz,4.10 GHz,4.10 GHz
Intel® Xeon® Bronze 3206R Processor 11M Cache/ 1.90 GHz,3206R,Launched,Q1'20,8,8,1.90 GHz,1.90 GHz,notFound
Intel® Xeon® Processor E5502 4M Cache/ 1.86 GHz/ 4.80 GT/s Intel® QPI,E5502,Discontinued,Q1'09,2,2,1.86 GHz,notFound,notFound
Intel® Core™ i3-10100F Processor 6M Cache/ up to 4.30 GHz,i3-10100F,Launched,Q4'20,4,8,3.60 GHz,4.30 GHz,4.30 GHz
Intel® Core™ i5-8365U Processor 6M Cache/ up to 4.10 GHz,i5-8365U,Launched,Q2'19,4,8,1.60 GHz,4.10 GHz,notFound
Intel® Core™ i5-8365U Processor 6M Cache/ up to 4.10 GHz,i5-8365U,Launched,Q2'19,4,8,1.60 GHz,4.10 GHz,notFound
Intel® Pentium® Processor E6700 2M Cache/ 3.20 GHz/ 1066 FSB,E6700,Discontinued,Q2'10,2,notFound,3.20 GHz,notFound,notFound
Intel® Xeon® Processor X6550 18M Cache/ 2.00 GHz/ 6.40 GT/s Intel® QPI,X6550,Discontinued,Q1'10,8,16,2.00 GHz,2.40 GHz,notFound
Intel® Core™ i5-2400 Processor 6M Cache/ up to 3.40 GHz,i5-2400,Discontinued,Q1'11,4,4,3.10 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i7-4720HQ Processor 6M Cache/ up to 3.60 GHz,i7-4720HQ,Discontinued,Q1'15,4,8,2.60 GHz,3.60 GHz,notFound
Intel® Xeon® Processor E5-2667 v2 25M Cache/ 3.30 GHz,E5-2667V2,Discontinued,Q3'13,8,16,3.30 GHz,4.00 GHz,4.00 GHz
Intel® Core™2 Duo Processor T5600 2M Cache/ 1.83 GHz/ 667 MHz FSB,T5600,Discontinued,notFound,2,notFound,1.83 GHz,notFound,notFound
Intel® Xeon® Platinum 8352M Processor 48M Cache/ 2.30 GHz,8352M,Launched,Q2'21,32,64,2.30 GHz,3.50 GHz,notFound
Intel® Core™ i5-3230M Processor 3M Cache/ up to 3.20 GHz BGA,i5-3230M,Discontinued,Q1'13,2,4,2.60 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i5-2405S Processor 6M Cache/ up to 3.30 GHz,i5-2405S,Discontinued,Q2'11,4,4,2.50 GHz,3.30 GHz,3.30 GHz
Intel® Celeron® Processor 867 2M Cache/ 1.30 GHz,867,Discontinued,Q1'12,2,2,1.30 GHz,notFound,notFound
Intel® Xeon® Processor E7-8867L 30M Cache/ 2.13 GHz/ 6.40 GT/s Intel® QPI,E7-8867L,Discontinued,Q2'11,10,20,2.13 GHz,2.53 GHz,notFound
Intel® Xeon® Processor E5-4627 v2 16M Cache/ 3.30 GHz,E5-4627V2,Discontinued,Q1'14,8,8,3.30 GHz,3.60 GHz,3.60 GHz
Intel Atom® Processor C3508 8M Cache/ up to 1.60 GHz,C3508,Launched,Q3'17,4,4,1.60 GHz,1.60 GHz,notFound
Intel Atom® Processor D425 512K Cache/ 1.80 GHz,D425,Discontinued,Q2'10,1,2,1.80 GHz,notFound,notFound
Intel® Core™ i3-9100 Processor 6M Cache/ up to 4.20 GHz,i3-9100,Launched,Q2'19,4,4,3.60 GHz,4.20 GHz,4.20 GHz
Intel® Pentium® Processor G2010 3M Cache/ 2.80 GHz,G2010,Discontinued,Q1'13,2,2,2.80 GHz,notFound,notFound
Intel® Xeon Phi™ Processor 7290F 16GB/ 1.50 GHz/ 72 core,7290F,Discontinued,Q4'16,72,notFound,1.50 GHz,1.70 GHz,notFound
Intel® Xeon® Gold 6240L Processor 24.75M Cache/ 2.60 GHz,6240L,Launched,Q2'19,18,36,2.60 GHz,3.90 GHz,notFound
Intel Atom® Processor C2758 4M Cache/ 2.40 GHz,C2758,Launched,Q3'13,8,8,2.40 GHz,notFound,notFound
Intel® Celeron® G4900T Processor 2M Cache/ 2.90 GHz,G4900T,Launched,Q2'18,2,2,2.90 GHz,notFound,notFound
Intel® Pentium® D Processor 935 4M Cache/ 3.20 GHz/ 800 MHz FSB,935,Discontinued,Q1'07,2,notFound,3.20 GHz,notFound,notFound
Intel® Xeon® Gold 6142 Processor 22M Cache/ 2.60 GHz,6142,Launched,Q3'17,16,32,2.60 GHz,3.70 GHz,notFound
Intel® Core™ i5-5287U Processor 3M Cache/ up to 3.30 GHz,i5-5287U,Discontinued,Q1'15,2,4,2.90 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® Gold 5118 Processor 16.5M Cache/ 2.30 GHz,5118,Launched,Q3'17,12,24,2.30 GHz,3.20 GHz,notFound
Intel Atom® x5-E3940 Processor 2M Cache/ up to 1.80 GHz,E3940,Launched,Q4'16,4,4,1.60 GHz,notFound,notFound
Intel® Core™2 Duo Processor T7500 4M Cache/ 2.20 GHz/ 800 MHz FSB,T7500,Discontinued,Q3'06,2,notFound,2.20 GHz,notFound,notFound
Intel® Core™ i3-1115G4 Processor 6M Cache/ up to 4.10 GHz,i3-1115G4,Launched,Q3'20,2,4,notFound,4.10 GHz,notFound
Intel® Core™ i3-1115G4 Processor 6M Cache/ up to 4.10 GHz,i3-1115G4,Launched,Q3'20,2,4,notFound,4.10 GHz,notFound
Intel® Core™2 Duo Processor P8600 3M Cache/ 2.40 GHz/ 1066 MHz FSB,P8600,Discontinued,Q3'08,2,notFound,2.40 GHz,notFound,notFound
Intel Atom® x3-C3265RK Processor 1M Cache/ up to 1.1 Ghz,x3-C3265RK,Discontinued,Q4'16,4,notFound,notFound,notFound,notFound
Intel® Core™2 Duo Processor T7100 2M Cache/ 1.80 GHz/ 800 MHz FSB,T7100,Discontinued,Q2'07,2,notFound,1.80 GHz,notFound,notFound
Intel® Core™ i5-8400H Processor 8M Cache/ up to 4.20 GHz,i5-8400H,Launched,Q2'18,4,8,2.50 GHz,4.20 GHz,4.20 GHz
Intel® Xeon® Processor E5-4627 v4 25M Cache/ 2.60 GHz,E5-4627V4,Launched,Q2'16,10,10,2.60 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Processor E7-2860 24M Cache/ 2.26 GHz/ 6.40 GT/s Intel® QPI,E7-2860,Discontinued,Q2'11,10,20,2.26 GHz,2.67 GHz,notFound
Intel Atom® Processor C3558 8M Cache/ up to 2.20 GHz,C3558,Launched,Q3'17,4,4,2.20 GHz,2.20 GHz,notFound
Intel® Xeon® Platinum 9222 Processor 71.5M Cache/ 2.30 GHz,9222,Launched,Q3'19,32,64,2.30 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i7-4770TE Processor 8M Cache/ up to 3.30 GHz,i7-4770TE,Launched,Q2'13,4,8,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i7-4712MQ Processor 6M Cache/ up to 3.30 GHz,i7-4712MQ,Discontinued,Q2'14,4,8,2.30 GHz,3.30 GHz,3.30 GHz
Intel Atom® x3-C3295RK Processor 1M Cache/ up to 1.1 GHz,x3-C3295RK,Launched,Q4'16,4,notFound,notFound,notFound,notFound
Intel® Core™ i7-7500U Processor 4M Cache/ up to 3.50 GHz ,i7-7500U,Launched,Q3'16,2,4,2.70 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i3-4012Y Processor 3M Cache/ 1.50 GHz,i3-4012Y,Discontinued,Q3'13,2,4,1.50 GHz,notFound,notFound
Intel® Xeon® Gold 5120 Processor 19.25M Cache/ 2.20 GHz,5120,Launched,Q3'17,14,28,2.20 GHz,3.20 GHz,notFound
Intel® Core™ i7-6970HQ Processor 8M Cache/ up to 3.70 GHz,i7-6970HQ,Discontinued,Q1'16,4,8,2.80 GHz,3.70 GHz,3.70 GHz
Intel® Celeron® Processor B720 1.5M Cache/ 1.70 GHz,B720,Discontinued,Q1'12,1,1,1.70 GHz,notFound,notFound
Intel® Core™ i3-330UM Processor 3M cache/ 1.20 GHz,i3-330UM,Discontinued,Q2'10,2,4,1.20 GHz,notFound,notFound
Intel® Core™ i7-4610M Processor 4M Cache/ up to 3.70 GHz,i7-4610M,Discontinued,Q1'14,2,4,3.00 GHz,3.70 GHz,3.70 GHz
Intel® Core™2 Duo Processor P9500 6M Cache/ 2.53 GHz/ 1066 MHz FSB,P9500,Discontinued,Q3'08,2,notFound,2.53 GHz,notFound,notFound
Intel Atom® Processor E640T 512K Cache/ 1.00 GHz,E640T,Discontinued,Q3'10,1,2,1.00 GHz,notFound,notFound
Intel® Core™2 Solo Processor U2200 1M Cache/ 1.20 GHz/ 533 MHz FSB,U2200,Discontinued,Q3'07,1,notFound,1.20 GHz,notFound,notFound
Intel® Xeon® Processor E5-2603 10M Cache/ 1.80 GHz/ 6.40 GT/s Intel® QPI,E5-2603,Discontinued,Q1'12,4,4,1.80 GHz,notFound,notFound
Intel® Xeon® Gold 6330H Processor 33M Cache/ 2.00 GHz,6330H,Launched,Q3'20,24,48,2.00 GHz,3.70 GHz,notFound
Intel® Xeon® Gold 6148 Processor 27.5M Cache/ 2.40 GHz,6148,Launched,Q3'17,20,40,2.40 GHz,3.70 GHz,notFound
Intel® Pentium® Processor N3710 2M Cache/ up to 2.56 GHz,N3710,Launched,Q1'16,4,4,1.60 GHz,notFound,notFound
Intel® Celeron® Processor E1200 512K Cache/ 1.60 GHz/ 800 MHz FSB,E1200,Discontinued,Q1'08,2,notFound,1.60 GHz,notFound,notFound
Intel® Xeon® Processor E7-2890 v2 37.5M Cache/ 2.80 GHz,E7-2890V2,Launched,Q1'14,15,30,2.80 GHz,3.40 GHz,3.40 GHz
Intel® Celeron® Processor G470 1.5M Cache/ 2.00 GHz,G470,Discontinued,Q2'13,1,2,2.00 GHz,notFound,notFound
Intel® Core™ i7-1180G7 Processor 12M Cache/ up to 4.60 GHz/ with IPU,i7-1180G7,Launched,Q1'21,4,8,notFound,4.60 GHz,notFound
Intel® Xeon® Processor E5-2623 v3 10M Cache/ 3.00 GHz,E5-2623V3,Discontinued,Q3'14,4,8,3.00 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® Gold 6226 Processor 19.25M Cache/ 2.70 GHz,6226,Launched,Q2'19,12,24,2.70 GHz,3.70 GHz,notFound
Intel® Xeon® Processor L5618 12M Cache/ 1.87 GHz/ 5.86 GT/s Intel® QPI,L5618,Discontinued,Q1'10,4,8,1.87 GHz,2.26 GHz,notFound
Intel Atom® Processor C2738 4M Cache/ 2.40 GHz,C2738,Launched,Q3'13,8,8,2.40 GHz,notFound,notFound
Intel® Xeon® Processor E7-4870 30M Cache/ 2.40 GHz/ 6.40 GT/s Intel® QPI,E7-4870,Discontinued,Q2'11,10,20,2.40 GHz,2.80 GHz,notFound
Intel® Xeon® Processor E5-4650 v2 25M Cache/ 2.40 GHz,E5-4650V2,Discontinued,Q1'14,10,20,2.40 GHz,2.90 GHz,2.90 GHz
Intel® Xeon® Processor E7-8890 v4 60M Cache/ 2.20 GHz,E7-8890V4,Launched,Q2'16,24,48,2.20 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® Processor D-1518 6M Cache/ 2.20 GHz,D-1518,Launched,Q4'15,4,8,2.20 GHz,2.20 GHz,notFound
Intel® Core™ i7-3612QM Processor 6M Cache/ up to 3.10 GHz BGA,i7-3612QM,Discontinued,Q2'12,4,8,2.10 GHz,3.10 GHz,3.10 GHz
Intel® Core™ i3-3130M Processor 3M Cache/ 2.60 GHz,i3-3130M,Discontinued,Q1'13,2,4,2.60 GHz,notFound,notFound
Intel® Core™ i3-2105 Processor 3M Cache/ 3.10 GHz,i3-2105,Discontinued,Q2'11,2,4,3.10 GHz,notFound,notFound
Intel® Core™ i5-4310M Processor 3M Cache/ up to 3.40 GHz,i5-4310M,Discontinued,Q1'14,2,4,2.70 GHz,3.40 GHz,3.40 GHz
Intel® Pentium® Processor 977 2M Cache/ 1.40 GHz,977,Discontinued,Q1'12,2,2,1.40 GHz,notFound,notFound
Intel® Core™ i5-2500 Processor 6M Cache/ up to 3.70 GHz,i5-2500,Discontinued,Q1'11,4,4,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® Processor D-1523N 6M Cache/ 2.00 GHz,D-1523N,Launched,Q3'17,4,8,2.00 GHz,2.60 GHz,2.60 GHz
Intel® Xeon® Processor E5-2609 v3 15M Cache/ 1.90 GHz,E5-2609V3,Discontinued,Q3'14,6,6,1.90 GHz,notFound,notFound
Intel® Celeron® Processor 1000M 2M Cache/ 1.80 GHz,1000M,Discontinued,Q1'13,2,2,1.80 GHz,notFound,notFound
Intel® Xeon® Processor E7-4809 v2 12M Cache/ 1.90 GHz,E7-4809V2,Launched,Q1'14,6,12,1.90 GHz,notFound,notFound
Intel® Xeon® Processor X5472 12M Cache/ 3.00 GHz/ 1600 MHz FSB,X5472,Discontinued,Q4'07,4,notFound,3.00 GHz,notFound,notFound
Intel® Core™ i7-2620M Processor 4M Cache/ up to 3.40 GHz,i7-2620M,Discontinued,Q1'11,2,4,2.70 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i5-6685R Processor 6M Cache/ up to 3.80 GHz,i5-6685R,Discontinued,Q2'16,4,4,3.20 GHz,3.80 GHz,3.80 GHz
Intel® Celeron® Processor 2002E 2M Cache/ 1.50 GHz,2002E,Launched,Q1'14,2,2,1.50 GHz,notFound,notFound
Intel® Xeon® Platinum 8376H Processor 38.5M Cache/ 2.60 GHz,8376H,Launched,Q2'20,28,56,2.60 GHz,4.30 GHz,notFound
Intel® Xeon® Processor L7345 8M Cache/ 1.86 GHz/ 1066 MHz FSB,L7345,Discontinued,Q3'07,4,notFound,1.86 GHz,notFound,notFound
Intel® Core™ i3-9100TE Processor 6M Cache/ up to 3.20 GHz,i3-9100TE,Launched,Q2'19,4,4,2.20 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Processor E5-2670 20M Cache/ 2.60 GHz/ 8.00 GT/s Intel® QPI,E5-2670,Discontinued,Q1'12,8,16,2.60 GHz,3.30 GHz,3.30 GHz
Intel Atom® Processor E640 512K Cache/ 1.00 GHz,E640,Discontinued,Q3'10,1,2,1.00 GHz,notFound,notFound
Intel® Core™ i5-9500T Processor 9M Cache/ up to 3.70 GHz,i5-9500T,Launched,Q2'19,6,6,2.20 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® Processor E5335 8M Cache/ 2.00 GHz/ 1333 MHz FSB,E5335,Discontinued,Q1'07,4,notFound,2.00 GHz,notFound,notFound
Intel® Core™ i7-8705G Processor with Radeon™ RX Vega M GL graphics 8M Cache/ up to 4.10 GHz,i7-8705G,Discontinued,Q1'18,4,8,3.10 GHz,4.10 GHz,4.10 GHz
Intel® Core™ i7-8705G Processor with Radeon™ RX Vega M GL graphics 8M Cache/ up to 4.10 GHz,i7-8705G,Discontinued,Q1'18,4,8,3.10 GHz,4.10 GHz,4.10 GHz
Intel® Core™ i5-4670K Processor 6M Cache/ up to 3.80 GHz,i5-4670K,Discontinued,Q2'13,4,4,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i7-4770HQ Processor 6M Cache/ up to 3.40 GHz,i7-4770HQ,Discontinued,Q3'14,4,8,2.20 GHz,3.40 GHz,3.40 GHz
Intel Atom® Processor C3808 12M Cache/ up to 2.0 GHz,C3808,Launched,Q3'17,12,12,2.00 GHz,2.00 GHz,notFound
Intel® Xeon® Processor E5-2698 v3 40M Cache/ 2.30 GHz,E5-2698V3,Discontinued,Q3'14,16,32,2.30 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® Gold 5220S Processor 24.75M Cache/ 2.70 GHz,5220S,Launched,Q2'19,18,36,2.70 GHz,3.90 GHz,notFound
Intel® Core™2 Duo Processor L7500 4M Cache/ 1.60 GHz/ 800 MHz FSB,L7500,Discontinued,Q3'06,2,notFound,1.60 GHz,notFound,notFound
Intel Atom® Processor C2538 2M Cache/ 2.40 GHz,C2538,Launched,Q3'13,4,4,2.40 GHz,notFound,notFound
Intel® Celeron® Processor G4950 2M Cache/ 3.30 GHz,G4950,Launched,Q2'19,2,2,3.30 GHz,notFound,notFound
Intel® Core™ i7-1185G7 Processor 12M Cache/ up to 4.80 GHz/ with IPU,i7-1185G7,Launched,Q3'20,4,8,notFound,4.80 GHz,notFound
Intel® Core™ i7-1185G7 Processor 12M Cache/ up to 4.80 GHz/ with IPU,i7-1185G7,Launched,Q3'20,4,8,notFound,4.80 GHz,notFound
Intel® Celeron® Processor 420 512K Cache/ 1.60 GHz/ 800 MHz FSB,420,Discontinued,Q2'07,1,notFound,1.60 GHz,notFound,notFound
Intel® Xeon® Processor X5660 12M Cache/ 2.80 GHz/ 6.40 GT/s Intel® QPI,X5660,Discontinued,Q1'10,6,12,2.80 GHz,3.20 GHz,notFound
Intel® Core™ i5-7640X X-series Processor 6M Cache/ up to 4.20 GHz,i5-7640X,Discontinued,Q2'17,4,notFound,4.00 GHz,4.20 GHz,4.20 GHz
Intel® Pentium® 4 Processor 541 supporting HT Technology 1M Cache/ 3.20 GHz/ 800 MHz FSB,541,Discontinued,Q3'04,1,notFound,3.20 GHz,notFound,notFound
Intel® Xeon® Processor D-1557 18M Cache/ 1.50 GHz,D-1557,Launched,Q1'16,12,24,1.50 GHz,2.10 GHz,2.10 GHz
Intel® Core™2 Solo Processor ULV SU3300 3M Cache/ 1.20 GHz/ 800 MHz FSB,SU3300,Discontinued,Q3'08,1,notFound,1.20 GHz,notFound,notFound
Intel® Core™ i7-8665UE Processor 8M Cache/ up to 4.40 GHz,i7-8665UE,Launched,Q2'19,4,8,1.70 GHz,4.40 GHz,notFound
Intel® Core™ i3-6100H Processor 3M Cache/ 2.70 GHz,i3-6100H,Discontinued,Q3'15,2,4,2.70 GHz,notFound,notFound
Intel® Core™2 Duo Processor T6600 2M Cache/ 2.20 GHz/ 800 MHz FSB,T6600,Discontinued,Q1'09,2,notFound,2.20 GHz,notFound,notFound
Intel® Xeon® Processor L7555 24M Cache/ 1.86 GHz/ 5.86 GT/s Intel® QPI,L7555,Discontinued,Q1'10,8,16,1.87 GHz,2.53 GHz,notFound
Intel Atom® Processor Z3480 1M Cache/ up to 2.13 GHz,Z3480,Discontinued,Q1'14,2,notFound,notFound,notFound,notFound
Intel® Xeon® Platinum 8280L Processor 38.5M Cache/ 2.70 GHz,8280L,Launched,Q2'19,28,56,2.70 GHz,4.00 GHz,notFound
Intel® Xeon® Silver 4214R Processor 16.5M Cache/ 2.40 GHz,4214R,Launched,Q1'20,12,24,2.40 GHz,3.50 GHz,notFound
Intel® Core™ i5-8600T Processor 9M Cache/ up to 3.70 GHz,i5-8600T,Discontinued,Q2'18,6,6,2.30 GHz,3.70 GHz,3.70 GHz
Intel Atom® Processor D2500 1M Cache/ 1.86 GHz,D2500,Discontinued,Q3'11,2,2,1.86 GHz,notFound,notFound
Intel® Xeon® Processor E7420 8M Cache/ 2.13 GHz/ 1066 MHz FSB,E7420,Discontinued,Q3'08,4,notFound,2.13 GHz,notFound,notFound
Intel® Xeon Phi™ Coprocessor 7120D 16GB/ 1.238 GHz/ 61 core,7120D,Discontinued,Q1'14,61,notFound,1.24 GHz,1.33 GHz,notFound
Intel® Celeron® Processor G5920 2M Cache/ 3.50 GHz,G5920,Launched,Q2'20,2,2,3.50 GHz,notFound,notFound
Intel® Xeon® Processor L5640 12M Cache/ 2.26 GHz/ 5.86 GT/s Intel® QPI,L5640,Discontinued,Q1'10,6,12,2.26 GHz,2.80 GHz,notFound
Intel® Core™ i5-6600T Processor 6M Cache/ up to 3.50 GHz,i5-6600T,Discontinued,Q3'15,4,4,2.70 GHz,3.50 GHz,3.50 GHz
Intel® Celeron® M Processor 530 1M Cache/ 1.73 GHz/ 533 MHz FSB Socket M,530,Discontinued,Q3'06,1,notFound,1.73 GHz,notFound,notFound
Intel® Pentium® Processor B940 2M Cache/ 2.00 GHz,B940,Discontinued,Q2'11,2,2,2.00 GHz,notFound,notFound
Intel® Xeon® W-3323 Processor 21M Cache/ up to 3.90 GHz,W-3323,Launched,Q3'21,12,24,3.50 GHz,3.90 GHz,notFound
Intel® Xeon® Processor E5503 4M Cache/ 2.00 GHz/ 4.80 GT/s Intel® QPI,E5503,Discontinued,Q1'10,2,2,2.00 GHz,notFound,notFound
Intel® Xeon® Platinum 8276L Processor 38.5M Cache/ 2.20 GHz,8276L,Launched,Q2'19,28,56,2.20 GHz,4.00 GHz,notFound
Intel Atom® Processor Z2760 1M Cache/ 1.80 GHz,Z2760,Discontinued,Q3'12,2,4,1.80 GHz,notFound,notFound
Intel® Pentium® 4 Processor 505/505J 1M Cache/ 2.66 GHz/ 533 MHz FSB,505J,Discontinued,Q1'05,1,notFound,2.66 GHz,notFound,notFound
Intel Atom® Processor N470 512K Cache/ 1.83 GHz,N470,Discontinued,Q1'10,1,2,1.83 GHz,notFound,notFound
Intel® Xeon® Processor L7545 18M Cache/ 1.86 GHz/ 5.86 GT/s Intel® QPI,L7545,Discontinued,Q1'10,6,12,1.87 GHz,2.53 GHz,notFound
Intel® Core™ i5-8260U Processor 6M Cache/ up to 3.90 GHz,i5-8260U,Launched,Q4'19,4,8,1.60 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i5-8260U Processor 6M Cache/ up to 3.90 GHz,i5-8260U,Launched,Q4'19,4,8,1.60 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor X5667 12M Cache/ 3.06 GHz/ 6.40 GT/s Intel® QPI,X5667,Discontinued,Q1'10,4,8,3.06 GHz,3.46 GHz,notFound
Intel® Xeon® E-2224 Processor 8M Cache/ 3.40 GHz,E-2224,Launched,Q2'19,4,4,3.40 GHz,4.60 GHz,4.60 GHz
Intel® Core™ i3-4170T Processor 3M Cache/ 3.20 GHz,i3-4170T,Discontinued,Q1'15,2,4,3.20 GHz,notFound,notFound
Intel® Xeon® Silver 4214Y Processor 16.5M Cache/ 2.20 GHz,4214Y,Launched,Q2'19,12,24,2.20 GHz,3.20 GHz,notFound
Intel® Xeon® Platinum 8268 Processor 35.75M Cache/ 2.90 GHz,8268,Launched,Q2'19,24,48,2.90 GHz,3.90 GHz,notFound
Intel® Core™2 Quad Processor Q8300 4M Cache/ 2.50 GHz/ 1333 MHz FSB,Q8300,Discontinued,Q4'08,4,notFound,2.50 GHz,notFound,notFound
Intel® Xeon® Processor D-1571 24M Cache/ 1.30 GHz,D-1571,Launched,Q1'16,16,32,1.30 GHz,2.10 GHz,2.10 GHz
Intel® Pentium® 4 Processor 520 supporting HT Technology 1M Cache/ 2.80 GHz/ 800 MHz FSB,520,Discontinued,Q2'04,1,notFound,2.80 GHz,notFound,notFound
Intel® Xeon® Processor E5-2428L v3 20M Cache/ 1.80 GHz,E5-2428LV3,Launched,Q1'15,8,16,1.80 GHz,notFound,notFound
Intel® Core™ i7-880 Processor 8M Cache/ 3.06 GHz,i7-880,Discontinued,Q2'10,4,8,3.06 GHz,3.73 GHz,notFound
Intel® Pentium® Processor E6500K 2M Cache/ 2.93 GHz/ 1066 MHz FSB,E6500K,Discontinued,Q3'09,2,notFound,2.93 GHz,notFound,notFound
Intel® Quark™ SoC X1020 16K Cache/ 400 MHz,X1020,Discontinued,Q2'14,1,1,400 MHz,notFound,notFound
Intel® Itanium® Processor 9150M 24M Cache/ 1.66 GHz/ 667 MHz FSB,9150M,Discontinued,Q4'07,2,notFound,1.66 GHz,notFound,notFound
Intel® Pentium® Processor 1405 v2 6M Cache/ 1.40 GHz,1405V2,Launched,Q1'14,2,notFound,1.40 GHz,notFound,notFound
Intel® Pentium® 4 Processor 540/540J supporting HT Technology 1M Cache/ 3.20 GHz/ 800 MHz FSB,540,Discontinued,Q2'04,1,notFound,3.20 GHz,notFound,notFound
Intel® Xeon® Processor E3-1270 v5 8M Cache/ 3.60 GHz,E3-1270V5,Discontinued,Q4'15,4,8,3.60 GHz,4.00 GHz,4.00 GHz
Intel® Xeon® Gold 6240 Processor 24.75M Cache/ 2.60 GHz,6240,Launched,Q2'19,18,36,2.60 GHz,3.90 GHz,notFound
Intel® Xeon® Processor E3-1226 v3 8M Cache/ 3.30 GHz,E3-1226V3,Discontinued,Q2'14,4,4,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i3-6100U Processor 3M Cache/ 2.30 GHz,i3-6100U,Launched,Q3'15,2,4,2.30 GHz,notFound,notFound
Intel® Core™ i3-6100U Processor 3M Cache/ 2.30 GHz,i3-6100U,Launched,Q3'15,2,4,2.30 GHz,notFound,notFound
Intel® Quark™ Microcontroller D1000,D1000,Discontinued,Q3'15,1,notFound,33 MHz,notFound,notFound
Intel® Core™2 Duo Processor SU9600 3M Cache/ 1.60 GHz/ 800 MHz/ FSB,SU9600,Discontinued,Q1'09,2,notFound,1.60 GHz,notFound,notFound
Intel® Celeron® Processor 4305UE 2M Cache/ 2.00 GHz,4305UE,Launched,Q2'19,2,2,2.00 GHz,notFound,notFound
Intel® Core™ i3-6100 Processor 3M Cache/ 3.70 GHz,i3-6100,Launched,Q3'15,2,4,3.70 GHz,notFound,notFound
Intel® Core™2 Quad Processor Q9400 6M Cache/ 2.66 GHz/ 1333 MHz FSB,Q9400,Discontinued,Q3'08,4,notFound,2.66 GHz,notFound,notFound
Intel® Xeon® Processor W3680 12M Cache/ 3.33 GHz/ 6.40 GT/s Intel® QPI,W3680,Discontinued,Q1'10,6,12,3.33 GHz,3.60 GHz,notFound
Intel® Core™ i3-4370T Processor 4M Cache/ 3.30 GHz,i3-4370T,Discontinued,Q1'15,2,4,3.30 GHz,notFound,notFound
Intel® Xeon® E-2226G Processor 12M Cache/ 3.40 GHz,E-2226G,Launched,Q2'19,6,6,3.40 GHz,4.70 GHz,4.70 GHz
Intel® Core™ i5-7600 Processor 6M Cache/ up to 4.10 GHz,i5-7600,Discontinued,Q1'17,4,4,3.50 GHz,4.10 GHz,4.10 GHz
Intel® Core™ i3-2115C Processor 3M Cache/ 2.00 GHz,i3-2115C,Launched,Q2'12,2,4,2.00 GHz,notFound,notFound
Intel® Celeron® Processor G3900TE 2M Cache/ 2.30 GHz,G3900TE,Launched,Q4'15,2,2,2.30 GHz,notFound,notFound
Intel Atom® Processor E3805 1M Cache/ 1.33 GHz,E3805,Launched,Q4'14,2,2,1.33 GHz,notFound,notFound
Intel® Pentium® Processor E5700 2M Cache/ 3.00 GHz/ 800 MHz FSB,E5700,Discontinued,Q3'10,2,notFound,3.00 GHz,notFound,notFound
Intel® Xeon® Processor D-1559 18M Cache/ 1.50 GHz,D-1559,Launched,Q2'16,12,24,1.50 GHz,2.10 GHz,2.10 GHz
Intel® Core™ i7-6820HQ Processor 8M Cache/ up to 3.60 GHz,i7-6820HQ,Discontinued,Q3'15,4,8,2.70 GHz,3.60 GHz,3.60 GHz
Intel® Pentium® Processor 957 2M Cache/ 1.20 GHz,957,Discontinued,Q2'11,2,2,1.20 GHz,notFound,notFound
Intel® Core™ i7-4820K Processor 10M Cache/ up to 3.90 GHz,i7-4820K,Discontinued,Q3'13,4,8,3.70 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor L5609 12M Cache/ 1.86 GHz/ 4.80 GT/s Intel® QPI,L5609,Discontinued,Q1'10,4,4,1.86 GHz,1.86 GHz,notFound
Intel® Core™ i9-10885H Processor 16M Cache/ up to 5.30 GHz,i9-10885H,Launched,Q2'20,8,16,2.40 GHz,5.30 GHz,notFound
Intel® Core™ i5-6400T Processor 6M Cache/ up to 2.80 GHz,i5-6400T,Discontinued,Q3'15,4,4,2.20 GHz,2.80 GHz,2.80 GHz
Intel® Xeon® W-3265M Processor 33M Cache/ 2.70 GHz,W-3265M,Launched,Q2'19,24,48,2.70 GHz,4.40 GHz,notFound
Intel® Xeon® Gold 5218 Processor 22M Cache/ 2.30 GHz,5218,Launched,Q2'19,16,32,2.30 GHz,3.90 GHz,notFound
Intel® Core™ Duo Processor T2600 2M Cache/ 2.16 GHz/ 667 MHz FSB,T2600,Discontinued,notFound,2,notFound,2.16 GHz,notFound,notFound
Intel® Xeon® Processor E3-1231 v3 8M Cache/ 3.40 GHz,E3-1231V3,Discontinued,Q2'14,4,8,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Pentium® Processor G3420 3M Cache/ 3.20 GHz,G3420,Launched,Q3'13,2,2,3.20 GHz,notFound,notFound
Intel® Xeon® Processor E3-1245 v5 8M Cache/ 3.50 GHz,E3-1245V5,Discontinued,Q4'15,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Pentium® Silver J5040 Processor 4M Cache/ up to 3.20 GHz,J5040,Launched,Q4'19,4,4,2.00 GHz,notFound,notFound
Intel® Core™ i7-820QM Processor 8M Cache/ 1.73 GHz,i7-820QM,Discontinued,Q3'09,4,8,1.73 GHz,3.06 GHz,notFound
Intel® Pentium® 4 Processor 521 supporting HT Technology 1M Cache/ 2.80 GHz/ 800 MHz FSB,521,Discontinued,Q3'05,1,notFound,2.80 GHz,notFound,notFound
Intel® Core™ i5-8259U Processor 6M Cache/ up to 3.80 GHz,i5-8259U,Launched,Q2'18,4,8,2.30 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i5-8259U Processor 6M Cache/ up to 3.80 GHz,i5-8259U,Launched,Q2'18,4,8,2.30 GHz,3.80 GHz,3.80 GHz
Intel® Pentium® Gold G5600T Processor 4M Cache/ 3.30 GHz,G5600T,Launched,Q2'19,2,4,3.30 GHz,notFound,notFound
Intel® Celeron® Processor G1820TE 2M Cache/ 2.20 GHz,G1820TE,Launched,Q1'14,2,2,2.20 GHz,notFound,notFound
Intel® Xeon® Processor E5-2620 15M Cache/ 2.00 GHz/ 7.20 GT/s Intel® QPI,E5-2620,Discontinued,Q1'12,6,12,2.00 GHz,2.50 GHz,notFound
Intel® Itanium® Processor 9150N 24M Cache/ 1.60 GHz/ 533 MHz FSB,9150N,Discontinued,Q4'07,2,notFound,1.60 GHz,notFound,notFound
Intel® Xeon® Platinum 8356H Processor 35.75M Cache/ 3.90 GHz,8356H,Launched,Q3'20,8,16,3.90 GHz,4.40 GHz,notFound
Intel® Xeon® Platinum 9242 Processor 71.5M Cache/ 2.30 GHz,9242,Launched,Q2'19,48,96,2.30 GHz,3.80 GHz,3.80 GHz
Intel Atom® Processor E620T 512K Cache/ 600 MHz,E620T,Discontinued,Q3'10,1,2,600 MHz,notFound,notFound
Intel® Core™2 Duo Processor T9800 6M Cache/ 2.93 GHz/ 1066 MHz FSB,T9800,Discontinued,Q4'08,2,notFound,2.93 GHz,notFound,notFound
Intel® Xeon® Processor X5450 12M Cache/ 3.00 GHz/ 1333 MHz FSB,X5450,Discontinued,Q4'07,4,notFound,3.00 GHz,notFound,notFound
Intel® Celeron® Processor 1007U 2M Cache/ 1.50 GHz,1007U,Discontinued,Q1'13,2,2,1.50 GHz,notFound,notFound
Intel® Core™2 Quad Processor Q8200 4M Cache/ 2.33 GHz/ 1333 MHz FSB,Q8200,Discontinued,Q3'08,4,notFound,2.33 GHz,notFound,notFound
Intel® Xeon® Silver 4216 Processor 22M Cache/ 2.10 GHz,4216,Launched,Q2'19,16,32,2.10 GHz,3.20 GHz,notFound
Intel® Core™ i7-6785R Processor 8M Cache/ up to 3.90 GHz,i7-6785R,Discontinued,Q2'16,4,8,3.30 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor E5-2699 v3 45M Cache/ 2.30 GHz,E5-2699V3,Discontinued,Q3'14,18,36,2.30 GHz,3.60 GHz,3.60 GHz
Intel Atom® Processor C3750 16M Cache/ up to 2.40 GHz,C3750,Launched,Q3'17,8,8,2.20 GHz,2.40 GHz,2.40 GHz
Intel® Xeon® Processor E5-4660 v4 40M Cache/ 2.20 GHz,E5-4660V4,Launched,Q2'16,16,32,2.20 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i7-4870HQ Processor 6M Cache/ up to 3.70 GHz,i7-4870HQ,Discontinued,Q3'14,4,8,2.50 GHz,3.70 GHz,3.70 GHz
Intel® Celeron® Processor G4930 2M Cache/ 3.20 GHz,G4930,Launched,Q2'19,2,2,3.20 GHz,notFound,notFound
Intel® Xeon® Gold 6252N Processor 35.75M Cache/ 2.30 GHz,6252N,Launched,Q2'19,24,48,2.30 GHz,3.60 GHz,notFound
Intel® Xeon® Processor E5-2620 v3 15M Cache/ 2.40 GHz,E5-2620V3,Launched,Q3'14,6,12,2.40 GHz,3.20 GHz,3.20 GHz
Intel® Core™2 Duo Processor L7300 4M Cache/ 1.40 GHz/ 800 MHz FSB,L7300,Discontinued,Q2'07,2,notFound,1.40 GHz,notFound,notFound
Intel Atom® Processor C2530 2M Cache/ 1.70 GHz,C2530,Launched,Q3'13,4,4,1.70 GHz,2.40 GHz,2.40 GHz
Intel® Core™2 Duo Processor L7400 4M Cache/ 1.50 GHz/ 667 MHz FSB,L7400,Discontinued,Q3'06,2,notFound,1.50 GHz,notFound,notFound
Intel® Core™ i5-4670S Processor 6M Cache/ up to 3.80 GHz,i5-4670S,Discontinued,Q2'13,4,4,3.10 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Gold 5215L Processor 13.75M Cache/ 2.50 GHz,5215L,Launched,Q2'19,10,20,2.50 GHz,3.40 GHz,notFound
Intel® Core™ i7-2920XM Processor Extreme Edition 8M Cache/ up to 3.50 GHz,i7-2920XM,Discontinued,Q1'11,4,8,2.50 GHz,3.50 GHz,3.50 GHz
Intel® Pentium® Processor P6300 3M Cache/ 2.27 GHz,P6300,Discontinued,Q1'11,2,2,2.27 GHz,notFound,notFound
Intel® Celeron® Processor J3355E 2M Cache/ up to 2.50 GHz,J3355E,Discontinued,Q3'19,2,2,2.00 GHz,2.50 GHz,notFound
Intel® Core™ i7-8550U Processor 8M Cache/ up to 4.00 GHz,i7-8550U,Launched,Q3'17,4,8,1.80 GHz,4.00 GHz,4.00 GHz
Intel® Celeron® Processor N3160 2M Cache/ up to 2.24 GHz,N3160,Launched,Q1'16,4,4,1.60 GHz,notFound,notFound
Intel® Core™2 Duo Processor E4700 2M Cache/ 2.60 GHz/ 800 MHz FSB,E4700,Discontinued,Q1'08,2,notFound,2.60 GHz,notFound,notFound
Intel® Xeon® Processor E5-2697 v3 35M Cache/ 2.60 GHz,E5-2697V3,Discontinued,Q3'14,14,28,2.60 GHz,3.60 GHz,3.60 GHz
Intel Atom® Processor E660 512K Cache/ 1.30 GHz,E660,Discontinued,Q3'10,1,2,1.30 GHz,notFound,notFound
Intel® Xeon® Gold 5320H Processor 27.5M Cache/ 2.40 GHz,5320H,Launched,Q2'20,20,40,2.40 GHz,4.20 GHz,notFound
Intel® Xeon® Processor E5-2630 15M Cache/ 2.30 GHz/ 7.20 GT/s Intel® QPI,E5-2630,Discontinued,Q1'12,6,12,2.30 GHz,2.80 GHz,notFound
Intel® Itanium® Processor 9110N 12M Cache/ 1.60 GHz/ 533 MHz FSB,9110N,Discontinued,Q4'07,1,notFound,1.60 GHz,notFound,notFound
Intel® Xeon® Gold 6246 Processor 24.75M Cache/ 3.30 GHz,6246,Launched,Q2'19,12,24,3.30 GHz,4.20 GHz,notFound
Intel® Pentium® Processor T2060 1M Cache/ 1.60 GHz/ 533 MHz FSB,T2060,Discontinued,Q1'07,2,notFound,1.60 GHz,notFound,notFound
Intel® Celeron® Processor 797 1.5M Cache/ 1.50 GHz,797,Discontinued,Q1'12,1,1,1.40 GHz,notFound,notFound
Intel® Xeon® Processor D-1539 12M Cache/ 1.60 GHz,D-1539,Launched,Q2'16,8,16,1.60 GHz,2.20 GHz,2.20 GHz
Intel® Pentium® Processor 2030M 2M Cache/ 2.50 GHz,2030M,Discontinued,Q1'13,2,2,2.50 GHz,notFound,notFound
Intel® Core™ i7-3615QM Processor 6M Cache/ up to 3.30 GHz,i7-3615QM,Discontinued,Q2'12,4,8,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® Processor D-1543N 12M Cache/ 1.90 GHz,D-1543N,Launched,Q3'17,8,16,1.90 GHz,2.50 GHz,2.50 GHz
Intel® Core™ i5-2400S Processor 6M Cache/ up to 3.30 GHz,i5-2400S,Discontinued,Q1'11,4,4,2.50 GHz,3.30 GHz,3.30 GHz
Intel Atom® Processor C2750 4M Cache/ 2.40 GHz,C2750,Launched,Q3'13,8,8,2.40 GHz,2.60 GHz,2.60 GHz
Intel® Xeon® Processor L5638 12M Cache/ 2.00 GHz/ 5.86 GT/s Intel® QPI,L5638,Discontinued,Q1'10,6,12,2.00 GHz,2.40 GHz,notFound
Intel® Pentium® Processor T4400 1M Cache/ 2.20 GHz/ 800 MHz FSB Socket P,T4400,Discontinued,Q4'09,2,notFound,2.20 GHz,notFound,notFound
Intel® Core™ i7-1165G7 Processor 12M Cache/ up to 4.70 GHz,i7-1165G7,Launched,Q3'20,4,8,notFound,4.70 GHz,notFound
Intel® Core™ i7-1165G7 Processor 12M Cache/ up to 4.70 GHz,i7-1165G7,Launched,Q3'20,4,8,notFound,4.70 GHz,notFound
Intel® Xeon® Processor E7-8893 v4 60M Cache/ 3.20 GHz,E7-8893V4,Launched,Q2'16,4,8,3.20 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i7-4980HQ Processor 6M Cache/ up to 4.00 GHz,i7-4980HQ,Discontinued,Q3'14,4,8,2.80 GHz,4.00 GHz,4.00 GHz
Intel® Xeon® Processor E5-4640 v2 20M Cache/ 2.20 GHz,E5-4640V2,Discontinued,Q1'14,10,20,2.20 GHz,2.70 GHz,2.70 GHz
Intel® Xeon® Processor E7-2870 30M Cache/ 2.40 GHz/ 6.40 GT/s Intel® QPI,E7-2870,Discontinued,Q2'11,10,20,2.40 GHz,2.80 GHz,notFound
Intel® Xeon® Processor E5-2670 v2 25M Cache/ 2.50 GHz,E5-2670V2,Discontinued,Q3'13,10,20,2.50 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® Processor E5-1428L 15M Cache/ 1.8 GHz,E5-1428L,Discontinued,Q2'12,6,12,1.80 GHz,notFound,notFound
Intel® Core™2 Extreme Processor QX6700 8M Cache/ 2.66 GHz/ 1066 MHz FSB,QX6700,Discontinued,Q4'06,4,notFound,2.66 GHz,notFound,notFound
Intel® Core™ i5-10210U Processor 6M Cache/ up to 4.20 GHz,i5-10210U,Launched,Q3'19,4,8,1.60 GHz,4.20 GHz,notFound
Intel® Core™ i5-10210U Processor 6M Cache/ up to 4.20 GHz,i5-10210U,Launched,Q3'19,4,8,1.60 GHz,4.20 GHz,notFound
Intel® Core™ i5-4670 Processor 6M Cache/ up to 3.80 GHz,i5-4670,Discontinued,Q2'13,4,4,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i7-4712HQ Processor 6M Cache/ up to 3.30 GHz,i7-4712HQ,Discontinued,Q2'14,4,8,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i5-8300H Processor 8M Cache/ up to 4.00 GHz,i5-8300H,Launched,Q2'18,4,8,2.30 GHz,4.00 GHz,4.00 GHz
Intel® Xeon® Processor E5-2695 v2 30M Cache/ 2.40 GHz,E5-2695V2,Discontinued,Q3'13,12,24,2.40 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Processor E7-4860 24M Cache/ 2.26 GHz/ 6.40 GT/s Intel® QPI,E7-4860,Discontinued,Q2'11,10,20,2.26 GHz,2.67 GHz,notFound
Intel Atom® Processor C3858 12M Cache/ up to 2.0 GHz,C3858,Launched,Q3'17,12,12,2.00 GHz,2.00 GHz,notFound
Intel® Xeon® Processor E5-4640 v4 30M Cache/ 2.10 GHz,E5-4640V4,Launched,Q2'16,12,24,2.10 GHz,2.60 GHz,2.60 GHz
Intel® Core™ i7-610E Processor 4M Cache/ 2.53 GHz,i7-610E,Discontinued,Q1'10,2,4,2.53 GHz,3.20 GHz,notFound
Intel® Xeon® Silver 4116 Processor 16.5M Cache/ 2.10 GHz,4116,Launched,Q3'17,12,24,2.10 GHz,3.00 GHz,notFound
Intel® Core™ i5-6585R Processor 6M Cache/ up to 3.60 GHz,i5-6585R,Discontinued,Q2'16,4,4,2.80 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i7-8706G Processor with Radeon™ Pro WX Vega M GL graphics 8M Cache/ up to 4.10 GHz,i7-8706G,Discontinued,Q3'18,4,8,3.10 GHz,4.10 GHz,4.10 GHz
Intel® Core™ i5-4340M Processor 3M Cache/ up to 3.60 GHz,i5-4340M,Discontinued,Q1'14,2,4,2.90 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i3-370M Processor 3M cache/ 2.40 GHz,i3-370M,Discontinued,Q3'10,2,4,2.40 GHz,notFound,notFound
Intel® Core™ i3-2125 Processor 3M Cache/ 3.30 GHz,i3-2125,Discontinued,Q3'11,2,4,3.30 GHz,notFound,notFound
Intel® Core™ i3-4020Y Processor 3M Cache/ 1.50 GHz,i3-4020Y,Discontinued,Q3'13,2,4,1.50 GHz,notFound,notFound
Intel® Xeon® Processor L5320 8M Cache/ 1.86 GHz/ 1066 MHz FSB,L5320,Discontinued,Q1'07,4,notFound,1.86 GHz,notFound,notFound
Intel® Core™ i5-655K Processor 4M Cache/ 3.20 GHz,i5-655K,Discontinued,Q2'10,2,4,3.20 GHz,3.46 GHz,notFound
Intel® Xeon® Gold 5122 Processor 16.5M Cache/ 3.60 GHz,5122,Launched,Q3'17,4,8,3.60 GHz,3.70 GHz,notFound
Intel® Xeon® E-2388G Processor 16M Cache/ 3.20 GHz,E-2388G,Launched,Q3'21,8,16,3.20 GHz,5.10 GHz,5.10 GHz
Intel® Celeron® Processor 3855U 2M Cache/ 1.60 GHz,3855U,Discontinued,Q4'15,2,2,1.60 GHz,notFound,notFound
Intel® Xeon® Processor E5-4620 v2 20M Cache/ 2.60 GHz,E5-4620V2,Discontinued,Q1'14,8,16,2.60 GHz,3.00 GHz,3.00 GHz
Intel® Core™2 Quad Processor Q9100 12M Cache/ 2.26 GHz/ 1066 MHz FSB,Q9100,Discontinued,Q3'08,4,notFound,2.26 GHz,notFound,notFound
Intel® Xeon® Processor E7-8837 24M Cache/ 2.66 GHz/ 6.40 GT/s Intel® QPI,E7-8837,Discontinued,Q2'11,8,8,2.66 GHz,2.80 GHz,notFound
Intel Atom® Processor C3830 12M Cache/ up to 2.30 GHz,C3830,Launched,Q3'17,12,12,1.90 GHz,2.30 GHz,2.30 GHz
Intel® Xeon® Gold 6238L Processor 30.25M Cache/ 2.10 GHz,6238L,Launched,Q2'19,22,44,2.10 GHz,3.70 GHz,notFound
Intel® Pentium® Processor E5300 2M Cache/ 2.60 GHz/ 800 MHz FSB,E5300,Discontinued,Q1'08,2,notFound,2.60 GHz,notFound,notFound
Intel Atom® Processor D2550 1M Cache/ 1.86 GHz,D2550,Discontinued,Q1'12,2,4,1.86 GHz,notFound,notFound
Intel® Xeon® Processor E5645 12M Cache/ 2.40 GHz/ 5.86 GT/s Intel® QPI,E5645,Discontinued,Q1'10,6,12,2.40 GHz,2.67 GHz,notFound
Intel® Xeon Phi™ Processor 7290 16GB/ 1.50 GHz/ 72 core,7290,Discontinued,Q4'16,72,notFound,1.50 GHz,1.70 GHz,notFound
Intel® Pentium® Processor G2020 3M Cache/ 2.90 GHz,G2020,Discontinued,Q1'13,2,2,2.90 GHz,notFound,notFound
Intel® Core™ i3-9100T Processor 6M Cache/ up to 3.70 GHz,i3-9100T,Launched,Q2'19,4,4,3.10 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i7-4722HQ Processor 6M Cache/ up to 3.40 GHz,i7-4722HQ,Discontinued,Q1'15,4,8,2.40 GHz,3.40 GHz,notFound
Intel® Core™ i5-2300 Processor 6M Cache/ up to 3.10 GHz,i5-2300,Discontinued,Q1'11,4,4,2.80 GHz,3.10 GHz,3.10 GHz
Intel® Core™ i5-4440S Processor 6M Cache/ up to 3.30 GHz,i5-4440S,Discontinued,Q3'13,4,4,2.80 GHz,3.30 GHz,3.30 GHz
Intel® Celeron® Processor B815 2M Cache/ 1.60 GHz,B815,Discontinued,Q1'12,2,2,1.60 GHz,notFound,notFound
Intel® Xeon® Processor E5-2660 v2 25M Cache/ 2.20 GHz,E5-2660V2,Discontinued,Q3'13,10,20,2.20 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i3-3227U Processor 3M Cache/ 1.90 GHz,i3-3227U,Discontinued,Q1'13,2,4,1.90 GHz,notFound,notFound
Intel® Core™2 Duo Processor T7200 4M Cache/ 2.00 GHz/ 667 MHz FSB,T7200,Discontinued,notFound,2,notFound,2.00 GHz,notFound,notFound
Intel® Core™ i3-6157U Processor 3M Cache/ 2.40 GHz,i3-6157U,Discontinued,Q3'16,2,4,2.40 GHz,notFound,notFound
Intel® Core™2 Duo Processor T7300 4M Cache/ 2.00 GHz/ 800 MHz FSB,T7300,Discontinued,Q2'07,2,notFound,2.00 GHz,notFound,notFound
Intel® Xeon® Processor E5-2695 v3 35M Cache/ 2.30 GHz,E5-2695V3,Discontinued,Q3'14,14,28,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Core™2 Duo Processor P8400 3M Cache/ 2.26 GHz/ 1066 MHz FSB,P8400,Discontinued,Q3'08,2,notFound,2.26 GHz,notFound,notFound
Intel® Core™ i5-8305G Processor with Radeon™ Pro WX Vega M GL graphics 6M Cache/ up to 3.80 GHz,i5-8305G,Discontinued,Q3'18,4,8,2.80 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i5-4310U Processor 3M Cache/ up to 3.00 GHz,i5-4310U,Discontinued,Q1'14,2,4,2.00 GHz,3.00 GHz,3.00 GHz
Intel® Pentium® Processor G6951 3M Cache/ 2.80 GHz,G6951,Discontinued,Q3'11,2,2,2.80 GHz,notFound,notFound
Intel® Core™ i7-6820HK Processor 8M Cache/ up to 3.60 GHz,i7-6820HK,Discontinued,Q3'15,4,8,2.70 GHz,3.60 GHz,3.60 GHz
Intel® Pentium® Processor B980 2M Cache/ 2.40 GHz,B980,Discontinued,Q2'12,2,2,2.40 GHz,notFound,notFound
Intel® Core™ i5-3339Y Processor 3M Cache/ up to 2.00 GHz,i5-3339Y,Discontinued,Q1'13,2,4,1.50 GHz,2.00 GHz,2.00 GHz
Intel® Xeon Phi™ Processor 7295 16GB/ 1.5 GHz/ 72 Core,7295,Launched,Q4'17,72,notFound,1.50 GHz,1.60 GHz,notFound
Intel® Core™ i7-4500U Processor 4M Cache/ up to 3.00 GHz,i7-4500U,Discontinued,Q3'13,2,4,1.80 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i7-10510Y Processor 8M Cache/ up to 4.50 GHz,i7-10510Y,Launched,Q3'19,4,8,1.20 GHz,4.50 GHz,notFound
Intel® Pentium® Processor E6300 2M Cache/ 2.80 GHz/ 1066 MHz FSB,E6300,Discontinued,Q2'09,2,notFound,2.80 GHz,notFound,notFound
Intel® Pentium® 4 Processor 630 supporting HT Technology 2M Cache/ 3.00 GHz/ 800 MHz FSB,630,Discontinued,Q4'05,1,notFound,3.00 GHz,notFound,notFound
Intel® Xeon® Processor E3-1241 v3 8M Cache/ 3.50 GHz,E3-1241V3,Discontinued,Q2'14,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Pentium® Gold G6500 Processor 4M Cache/ 4.10 GHz,G6500,Launched,Q2'20,2,4,4.10 GHz,notFound,notFound
Intel® Core™ i7-620LM Processor 4M Cache/ 2.00 GHz,i7-620LM,Discontinued,Q1'10,2,4,2.00 GHz,2.80 GHz,notFound
Intel® Pentium® Gold G6605 Processor 4M Cache/ 4.30 GHz,G6605,Launched,Q1'21,2,4,4.30 GHz,notFound,notFound
Intel® Pentium® Processor 3560M 2M Cache/ 2.40 GHz,3560M,Discontinued,Q2'14,2,2,2.40 GHz,notFound,notFound
Intel® Core™ i5-10600 Processor 12M Cache/ up to 4.80 GHz,i5-10600,Launched,Q2'20,6,12,3.30 GHz,4.80 GHz,4.80 GHz
Intel® Xeon® W-3235 Processor 19.25M Cache/ 3.30 GHz,W-3235,Launched,Q2'19,12,24,3.30 GHz,4.40 GHz,notFound
Intel® Pentium® Processor G3240T 3M Cache/ 2.70 GHz,G3240T,Discontinued,Q2'14,2,2,2.70 GHz,notFound,notFound
Intel Atom® Processor C3336 4M Cache/ 1.50 GHz,C3336,Launched,Q3'18,2,2,1.50 GHz,notFound,notFound
Intel® Celeron® Processor G3920 2M Cache/ 2.90 GHz,G3920,Discontinued,Q4'15,2,2,2.90 GHz,notFound,notFound
Intel® Core™ i3-1115G4E Processor 6M Cache/ up to 3.90 GHz,i3-1115G4E,Launched,Q3'20,2,4,2.20 GHz,3.90 GHz,notFound
Intel® Core™ i3-12300T Processor 12M Cache/ up to 4.20 GHz,i3-12300T,Launched,Q1'22,4,8,notFound,4.20 GHz,notFound
Intel® Pentium® Processor G6960 3M Cache/ 2.93 GHz,G6960,Discontinued,Q1'11,2,2,2.93 GHz,notFound,notFound
Intel® Core™ i3-10110Y Processor 4M Cache/ up to 4.00GHz,i3-10110Y,Launched,Q3'19,2,4,1.00 GHz,4.00 GHz,notFound
Intel® Xeon® Processor E3-1268L v3 8M Cache/ 2.30 GHz,E3-1268LV3,Launched,Q2'13,4,8,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® Platinum 8253 Processor 22M Cache/ 2.20 GHz,8253,Launched,Q2'19,16,32,2.20 GHz,3.00 GHz,notFound
Intel® Xeon® Processor 5130 4M Cache/ 2.00 GHz/ 1333 MHz FSB,5130,Discontinued,Q2'06,2,notFound,2.00 GHz,notFound,notFound
Intel® Core™ i5-3439Y Processor 3M Cache/ up to 2.30 GHz,i5-3439Y,Discontinued,Q1'13,2,4,1.50 GHz,2.30 GHz,2.30 GHz
Intel® Pentium® Processor P6200 3M Cache/ 2.13 GHz,P6200,Discontinued,Q3'10,2,2,2.13 GHz,notFound,notFound
Intel® Celeron® Processor N2920 2M Cache/ up to 2.00 GHz,N2920,Discontinued,Q4'13,4,4,1.86 GHz,notFound,notFound
Intel® Pentium® Processor G4500 3M Cache/ 3.50 GHz,G4500,Discontinued,Q3'15,2,2,3.50 GHz,notFound,notFound
Intel® Xeon® W-1250 Processor 12M Cache/ 3.30 GHz,W-1250,Launched,Q2'20,6,12,3.30 GHz,4.70 GHz,4.70 GHz
Intel® Core™ m7-6Y75 Processor 4M Cache/ up to 3.10 GHz,M7-6Y75,Discontinued,Q3'15,2,4,1.20 GHz,3.10 GHz,3.10 GHz
Intel® Core™ i5-520E Processor 3M Cache/ 2.40 GHz,i5-520E,Discontinued,Q1'10,2,4,2.40 GHz,2.93 GHz,notFound
Intel® Celeron® Processor 2970M 2M Cache/ 2.20 GHz,2970M,Discontinued,Q2'14,2,2,2.20 GHz,notFound,notFound
Intel® Core™ i3-10320 Processor 8M Cache/ up to 4.60 GHz,i3-10320,Launched,Q2'20,4,8,3.80 GHz,4.60 GHz,4.60 GHz
Intel® Xeon Phi™ Coprocessor 7120X 16GB/ 1.238 GHz/ 61 core,7120X,Discontinued,Q2'13,61,notFound,1.24 GHz,1.33 GHz,notFound
Intel® Pentium® Gold G6505T Processor 4M Cache/ 3.60 GHz,G6505T,Launched,Q1'21,2,4,3.60 GHz,notFound,notFound
Intel® Core™ Duo Processor L2400 2M Cache/ 1.66 GHz/ 667 MHz FSB,L2400,Discontinued,Q1'06,2,notFound,1.66 GHz,notFound,notFound
Intel® Core™ i7-7700HQ Processor 6M Cache/ up to 3.80 GHz,i7-7700HQ,Launched,Q1'17,4,8,2.80 GHz,3.80 GHz,3.80 GHz
Intel® Core™2 Duo Processor T7250 2M Cache/ 2.00 GHz/ 800 MHz FSB,T7250,Discontinued,Q3'07,2,notFound,2.00 GHz,notFound,notFound
Intel® Core™ i3-1120G4 Processor 8M Cache/ up to 3.50 GHz/ with IPU,i3-1120G4,Launched,Q1'21,4,8,notFound,3.50 GHz,notFound
Intel® Pentium® 4 Processor 650 supporting HT Technology 2M Cache/ 3.40 GHz/ 800 MHz FSB,650,Discontinued,Q1'05,1,notFound,3.40 GHz,notFound,notFound
Intel® Xeon® Processor E5440 12M Cache/ 2.83 GHz/ 1333 MHz FSB,E5440,Discontinued,Q1'08,4,notFound,2.83 GHz,notFound,notFound
Intel® Core™ i3-3250T Processor 3M Cache/ 3.00 GHz,i3-3250T,Discontinued,Q2'13,2,4,3.00 GHz,notFound,notFound
Intel® Xeon® W-3225 Processor 16.5M Cache/ 3.70 GHz,W-3225,Launched,Q2'19,8,16,3.70 GHz,4.30 GHz,notFound
Intel® Core™ i5-6300U Processor 3M Cache/ up to 3.00 GHz,i5-6300U,Launched,Q3'15,2,4,2.40 GHz,3.00 GHz,3.00 GHz
Intel® Xeon® Processor E3-1281 v3 8M Cache/ 3.70 GHz,E3-1281V3,Discontinued,Q2'14,4,8,3.70 GHz,4.10 GHz,4.10 GHz
Intel® Xeon Phi™ Processor 7210F 16GB/ 1.30 GHz/ 64 core,7210F,Discontinued,Q4'16,64,notFound,1.30 GHz,1.50 GHz,notFound
Intel® Xeon® Gold 6212U Processor 35.75M Cache/ 2.40 GHz,6212U,Launched,Q2'19,24,48,2.40 GHz,3.90 GHz,notFound
Intel® Core™ i5-1030G4 Processor 6M Cache/ up to 3.50 GHz,i5-1030G4,Discontinued,Q3'19,4,8,700 MHz,3.50 GHz,notFound
Intel® Pentium® Gold G6400T Processor 4M Cache/ 3.40 GHz,G6400T,Launched,Q2'20,2,4,3.40 GHz,notFound,notFound
Intel® Xeon® Processor E3-1240 8M Cache/ 3.30 GHz,E3-1240,Discontinued,Q2'11,4,8,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Pentium® Processor 987 2M Cache/ 1.50 GHz,987,Discontinued,Q3'12,2,2,1.50 GHz,notFound,notFound
Intel® Pentium® 4 Processor 571 supporting HT Technology 1M Cache/ 3.80 GHz/ 800 MHz FSB,571,Discontinued,Q3'05,1,notFound,3.80 GHz,notFound,notFound
Intel® Core™ i7-4940MX Processor Extreme Edition 8M Cache/ up to 4.00 GHz,i7-4940MX,Discontinued,Q1'14,4,8,3.10 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i9-9900K Processor 16M Cache/ up to 5.00 GHz,i9-9900K,Launched,Q4'18,8,16,3.60 GHz,5.00 GHz,5.00 GHz
Intel® Core™ i3-L13G4 Processor 4M Cache/ up to 2.8GHz,i3-L13G4,Launched,Q2'20,5,5,800 MHz,2.80 GHz,2.80 GHz
Intel® Core™ i5-7400 Processor 6M Cache/ up to 3.50 GHz,i5-7400,Discontinued,Q1'17,4,4,3.00 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i5-7440EQ Processor 6M Cache/ up to 3.60 GHz,i5-7440EQ,Launched,Q1'17,4,4,2.90 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i7-6700HQ Processor 6M Cache/ up to 3.50 GHz,i7-6700HQ,Discontinued,Q3'15,4,8,2.60 GHz,3.50 GHz,3.50 GHz
Intel® Core™2 Duo Processor E7500 3M Cache/ 2.93 GHz/ 1066 MHz FSB,E7500,Discontinued,Q1'09,2,notFound,2.93 GHz,notFound,notFound
Intel® Xeon® Processor E3-1245 8M Cache/ 3.30 GHz,E3-1245,Discontinued,Q2'11,4,8,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Celeron® Processor B820 2M Cache/ 1.70 GHz,B820,Discontinued,Q3'12,2,2,1.70 GHz,notFound,notFound
Intel® Pentium® 4 Processor 551 supporting HT Technology 1M Cache/ 3.40 GHz/ 800 MHz FSB,551,Discontinued,Q2'05,1,notFound,3.40 GHz,notFound,notFound
Intel® Core™ i5-660 Processor 4M Cache/ 3.33 GHz,i5-660,Discontinued,Q1'10,2,4,3.33 GHz,3.60 GHz,notFound
Intel® Quark™ SoC X1001 16K Cache/ 400 MHz,X1001,Discontinued,Q2'14,1,1,400 MHz,notFound,notFound
Intel® Core™ m5-6Y57 Processor 4M Cache/ up to 2.80 GHz,M5-6Y57,Discontinued,Q3'15,2,4,1.10 GHz,2.80 GHz,2.80 GHz
Intel® Core™ m5-6Y57 Processor 4M Cache/ up to 2.80 GHz,M5-6Y57,Discontinued,Q3'15,2,4,1.10 GHz,2.80 GHz,2.80 GHz
Intel® Pentium® Processor 967 2M Cache/ 1.30 GHz,967,Discontinued,Q4'11,2,2,1.30 GHz,notFound,notFound
Intel® Core™ i5-3210M Processor 3M Cache/ up to 3.10 GHz/ rPGA,i5-3210M,Discontinued,Q2'12,2,4,2.50 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Processor E5472 12M Cache/ 3.00 GHz/ 1600 MHz FSB,E5472,Discontinued,Q4'07,4,notFound,3.00 GHz,notFound,notFound
Intel® Core™ i5-11300H Processor 8M Cache/ up to 4.40 GHz/ with IPU,i5-11300H,Launched,Q1'21,4,8,notFound,4.40 GHz,notFound
Intel® Pentium® 4 Processor 661 supporting HT Technology 2M Cache/ 3.60 GHz/ 800 MHz FSB,661,Discontinued,Q1'06,1,notFound,3.60 GHz,notFound,notFound
Intel® Core™ i5-1030G7 Processor 6M Cache/ up to 3.50 GHz,i5-1030G7,Discontinued,Q3'19,4,8,800 MHz,3.50 GHz,notFound
Intel® Core™ i3-380M Processor 3M Cache/ 2.53 GHz,i3-380M,Discontinued,Q3'10,2,4,2.53 GHz,notFound,notFound
Intel® Xeon® Silver 4116T Processor 16.5M cache/ 2.10 GHz,4116T,Launched,Q3'17,12,24,2.10 GHz,3.00 GHz,notFound
Intel® Core™ i7-4700EQ Processor 6M Cache/ up to 3.40 GHz,i7-4700EQ,Launched,Q2'13,4,8,2.40 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i3-2328M Processor 3M Cache/ 2.20 GHz,i3-2328M,Discontinued,Q3'12,2,4,2.20 GHz,notFound,notFound
Intel® Pentium® Processor E6800 2M Cache/ 3.33 GHz/ 1066 FSB,E6800,Discontinued,Q3'10,2,notFound,3.33 GHz,notFound,notFound
Intel® Pentium® Gold Processor 4410Y 2M Cache/ 1.50 GHz,4410Y,Launched,Q1'17,2,4,1.50 GHz,notFound,notFound
Intel® Core™ i7-3630QM Processor 6M Cache/ up to 3.40 GHz,i7-3630QM,Discontinued,Q3'12,4,8,2.40 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i7-5700HQ Processor 6M Cache/ up to 3.50 GHz,i7-5700HQ,Discontinued,Q2'15,4,8,2.70 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i5-10500E Processor 12M Cache/ up to 4.20 GHz,i5-10500E,Launched,Q2'20,6,12,3.10 GHz,4.20 GHz,4.20 GHz
Intel® Xeon Phi™ Processor 7250F 16GB/ 1.40 GHz/ 68 core,7250F,Discontinued,Q4'16,68,notFound,1.40 GHz,1.60 GHz,notFound
Intel® Celeron® Processor G4930T 2M Cache/ 3.00 GHz,G4930T,Launched,Q2'19,2,2,3.00 GHz,notFound,notFound
Intel® Pentium® Processor G2020T 3M Cache/ 2.50 GHz,G2020T,Discontinued,Q1'13,2,2,2.50 GHz,notFound,notFound
Intel Atom® Processor N455 512K Cache/ 1.66 GHz,N455,Discontinued,Q2'10,1,2,1.66 GHz,notFound,notFound
Intel® Celeron® Processor N2830 1M Cache/ up to 2.41 GHz,N2830,Discontinued,Q1'14,2,2,2.16 GHz,notFound,notFound
Intel Atom® Processor C3338 4M Cache/ up to 2.20 GHz,C3338,Launched,Q1'17,2,2,1.50 GHz,2.20 GHz,2.20 GHz
Intel® Core™ i3-3240 Processor 3M Cache/ 3.40 GHz,i3-3240,Discontinued,Q3'12,2,4,3.40 GHz,notFound,notFound
Intel® Core™ i3-2310M Processor 3M Cache/ 2.10 GHz,i3-2310M,Discontinued,Q1'11,2,4,2.10 GHz,notFound,notFound
Intel® Xeon® Silver 4210 Processor 13.75M Cache/ 2.20 GHz,4210,Launched,Q2'19,10,20,2.20 GHz,3.20 GHz,notFound
Intel® Core™ i5-5350U Processor 3M Cache/ up to 2.90 GHz,i5-5350U,Launched,Q1'15,2,4,1.80 GHz,2.90 GHz,2.90 GHz
Intel® Celeron® Processor N4505 4M Cache/ up to 2.90 GHz,N4505,Launched,Q1'21,2,2,2.00 GHz,notFound,notFound
Intel® Xeon® Processor E7-8857 v2 30M Cache/ 3.00 GHz,E7-8857V2,Launched,Q1'14,12,12,3.00 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® E-2246G Processor 12M Cache/ 3.60 GHz,E-2246G,Launched,Q2'19,6,12,3.60 GHz,4.80 GHz,4.80 GHz
Intel® Xeon® Platinum 8380H Processor 38.5M Cache/ 2.90 GHz,8380H,Launched,Q2'20,28,56,2.90 GHz,4.30 GHz,notFound
Intel® Xeon® Processor E5504 4M Cache/ 2.00 GHz/ 4.80 GT/s Intel® QPI,E5504,Discontinued,Q1'09,4,4,2.00 GHz,notFound,notFound
Intel® Xeon® E-2136 Processor 12M Cache/ up to 4.50 GHz,E-2136,Launched,Q3'18,6,12,3.30 GHz,4.50 GHz,4.50 GHz
Intel® Xeon® Processor E5-2660 20M Cache/ 2.20 GHz/ 8.00 GT/s Intel® QPI,E5-2660,Discontinued,Q1'12,8,16,2.20 GHz,3.00 GHz,3.00 GHz
Intel® Xeon® Processor E7-2803 18M Cache/ 1.73 GHz/ 4.80 GT/s Intel® QPI,E7-2803,Discontinued,Q2'11,6,12,1.73 GHz,notFound,notFound
Intel® Pentium® Gold G6400TE Processor 4M Cache/ 3.20 GHz,G6400TE,Launched,Q2'20,2,4,3.20 GHz,notFound,notFound
Intel® Core™ i7-8709G Processor with Radeon™ RX Vega M GH graphics 8M Cache/ up to 4.10 GHz,i7-8709G,Discontinued,Q1'18,4,8,3.10 GHz,4.10 GHz,4.10 GHz
Intel® Celeron® Processor 2955U 2M Cache/ 1.40 GHz,2955U,Discontinued,Q3'13,2,2,1.40 GHz,notFound,notFound
Intel® Xeon® Processor L7455 12M Cache/ 2.13 GHz/ 1066 MHz FSB,L7455,Discontinued,Q3'08,6,notFound,2.13 GHz,notFound,notFound
Intel® Xeon® Processor E5320 8M Cache/ 1.86 GHz/ 1066 MHz FSB,E5320,Discontinued,Q4'06,4,notFound,1.86 GHz,notFound,notFound
Intel® Xeon® Processor E5-2680 20M Cache/ 2.70 GHz/ 8.00 GT/s Intel® QPI,E5-2680,Discontinued,Q1'12,8,16,2.70 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i9-9900T Processor 16M Cache/ up to 4.40 GHz,i9-9900T,Launched,Q2'19,8,16,2.10 GHz,4.40 GHz,4.40 GHz
Intel® Core™ i5-4202Y Processor 3M Cache/ up to 2.00 GHz,i5-4202Y,Discontinued,Q3'13,2,4,1.60 GHz,2.00 GHz,2.00 GHz
Intel® Core™ m3-7Y30 Processor 4M Cache/ 2.60 GHz ,M3-7Y30,Launched,Q3'16,2,4,1.00 GHz,2.60 GHz,2.60 GHz
Intel® Core™ m3-7Y30 Processor 4M Cache/ 2.60 GHz ,M3-7Y30,Launched,Q3'16,2,4,1.00 GHz,2.60 GHz,2.60 GHz
Intel® Pentium® Processor T3400 1M Cache/ 2.16 GHz/ 667 MHz FSB Socket P,T3400,Discontinued,Q4'08,2,notFound,2.16 GHz,notFound,notFound
Intel® Xeon® Processor E7-8850 v2 24M Cache/ 2.30 GHz,E7-8850V2,Discontinued,Q1'14,12,24,2.30 GHz,2.80 GHz,2.80 GHz
Intel® Core™ i3-3217U Processor 3M Cache/ 1.80 GHz,i3-3217U,Discontinued,Q2'12,2,4,1.80 GHz,notFound,notFound
Intel® Core™ i3-3217U Processor 3M Cache/ 1.80 GHz,i3-3217U,Discontinued,Q2'12,2,4,1.80 GHz,notFound,notFound
Intel® Core™ i7-2820QM Processor 8M Cache/ up to 3.40 GHz,i7-2820QM,Discontinued,Q1'11,4,8,2.30 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i7-11600H Processor 18M Cache/ up to 4.60 GHz,i7-11600H,Launched,Q3'21,6,12,notFound,4.60 GHz,notFound
Intel® Xeon® Platinum 8360H Processor 33M Cache/ 3.00 GHz,8360H,Launched,Q3'20,24,48,3.00 GHz,4.20 GHz,notFound
Intel® Xeon® E-2186M Processor 12M Cache/ up to 4.80 GHz,E-2186M,Launched,Q2'18,6,12,2.90 GHz,4.80 GHz,notFound
Intel® Xeon® Gold 5220T Processor 24.75M Cache/ 1.90 GHz,5220T,Launched,Q2'19,18,36,1.90 GHz,3.90 GHz,notFound
Intel® Core™ i7-7567U Processor 4M Cache/ up to 4.00 GHz,i7-7567U,Launched,Q1'17,2,4,3.50 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i7-7567U Processor 4M Cache/ up to 4.00 GHz,i7-7567U,Launched,Q1'17,2,4,3.50 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i3-7101TE Processor 3M Cache/ 3.40 GHz,i3-7101TE,Launched,Q1'17,2,4,3.40 GHz,notFound,notFound
Intel® Core™ i3-7020U Processor 3M Cache/ 2.30 GHz,i3-7020U,Launched,Q2'18,2,4,2.30 GHz,notFound,notFound
Intel® Core™ i3-8100T Processor 6M Cache/ 3.10 GHz,i3-8100T,Launched,Q2'18,4,4,3.10 GHz,notFound,notFound
Intel Atom® Processor C3558R 8M Cache/ 2.40 GHz,C3558R,Launched,Q2'20,4,4,2.40 GHz,notFound,notFound
Intel® Xeon® Processor W3580 8M Cache/ 3.33 GHz/ 6.40 GT/s Intel® QPI,W3580,Discontinued,Q3'09,4,8,3.33 GHz,3.60 GHz,notFound
Intel® Xeon® Gold 6152 Processor 30.25M Cache/ 2.10 GHz,6152,Launched,Q3'17,22,44,2.10 GHz,3.70 GHz,notFound
Intel® Core™ i7-640M Processor 4M Cache/ 2.80 GHz,i7-640M,Discontinued,Q3'10,2,4,2.80 GHz,3.46 GHz,notFound
Intel Atom® Processor C3758 16M Cache/ up to 2.20 GHz,C3758,Launched,Q3'17,8,8,2.20 GHz,2.20 GHz,notFound
Intel® Core™ i7-3540M Processor 4M Cache/ up to 3.70 GHz,i7-3540M,Discontinued,Q1'13,2,4,3.00 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® E-2146G Processor 12M Cache/ up to 4.50 GHz,E-2146G,Launched,Q3'18,6,12,3.50 GHz,4.50 GHz,4.50 GHz
Intel® Core™ i7-5775R Processor 6M Cache/ up to 3.80 GHz,i7-5775R,Discontinued,Q2'15,4,8,3.30 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i5-2500S Processor 6M Cache/ up to 3.70 GHz,i5-2500S,Discontinued,Q1'11,4,4,2.70 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i5-8500B Processor 9M Cache/ up to 4.10 GHz,i5-8500B,Discontinued,Q2'18,6,6,3.00 GHz,4.10 GHz,4.10 GHz
Intel® Xeon® Processor E3-1280 v3 8M Cache/ 3.60 GHz,E3-1280 v3,Discontinued,Q2'13,4,8,3.60 GHz,4.00 GHz,4.00 GHz
Intel® Itanium® Processor 9152M 24M Cache/ 1.66 GHz/ 667 MHz FSB,9152M,Discontinued,Q4'07,2,notFound,1.66 GHz,notFound,notFound
Intel® Xeon® Processor E5-2450L v2 25M Cache/ 1.70 GHz,E5-2450LV2,Discontinued,Q1'14,10,20,1.70 GHz,2.10 GHz,2.10 GHz
Intel® Core™ i7-5950HQ Processor 6M Cache/ up to 3.80 GHz,i7-5950HQ,Discontinued,Q2'15,4,8,2.90 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Platinum 8180 Processor 38.5M Cache/ 2.50 GHz,8180,Launched,Q3'17,28,56,2.50 GHz,3.80 GHz,notFound
Intel® Core™ i5-2520M Processor 3M Cache/ up to 3.20 GHz,i5-2520M,Discontinued,Q1'11,2,4,2.50 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i3-8300T Processor 8M Cache/ 3.20 GHz,i3-8300T,Discontinued,Q2'18,4,4,3.20 GHz,notFound,notFound
Intel® Core™ i7-7700T Processor 8M Cache/ up to 3.80 GHz,i7-7700T,Launched,Q1'17,4,8,2.90 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i5-11400H Processor 12M Cache/ up to 4.50 GHz,i5-11400H,Launched,Q2'21,6,12,notFound,4.50 GHz,notFound
Intel® Core™ i5-11400H Processor 12M Cache/ up to 4.50 GHz,i5-11400H,Launched,Q2'21,6,12,notFound,4.50 GHz,notFound
Intel® Xeon® Processor E7430 12M Cache/ 2.13 GHz/ 1066 MHz FSB,E7430,Discontinued,Q3'08,4,notFound,2.13 GHz,notFound,notFound
Intel® Core™ i5-4670T Processor 6M Cache/ up to 3.30 GHz,i5-4670T,Discontinued,Q2'13,4,4,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i5-9500 Processor 9M Cache/ up to 4.40 GHz,i5-9500,Launched,Q2'19,6,6,3.00 GHz,4.40 GHz,4.40 GHz
Intel® Core™ i7-8809G Processor with Radeon™ RX Vega M GH graphics 8M Cache/ up to 4.20 GHz,i7-8809G,Discontinued,Q1'18,4,8,3.10 GHz,4.20 GHz,4.20 GHz
Intel® Core™ i7-8809G Processor with Radeon™ RX Vega M GH graphics 8M Cache/ up to 4.20 GHz,i7-8809G,Discontinued,Q1'18,4,8,3.10 GHz,4.20 GHz,4.20 GHz
Intel® Xeon® Processor L5518 8M Cache/ 2.13 GHz/ 5.86 GT/s Intel® QPI,L5518,Discontinued,Q1'09,4,8,2.13 GHz,2.40 GHz,notFound
Intel® Celeron® Processor 1020E 2M Cache/ 2.20 GHz,1020E,Launched,Q1'13,2,2,2.20 GHz,notFound,notFound
Intel® Core™ i5-9300H Processor 8M Cache/ up to 4.10 GHz,i5-9300H,Launched,Q2'19,4,8,2.40 GHz,4.10 GHz,notFound
Intel® Core™ i5-9300H Processor 8M Cache/ up to 4.10 GHz,i5-9300H,Launched,Q2'19,4,8,2.40 GHz,4.10 GHz,notFound
Intel® Pentium® Processor 3556U 2M Cache/ 1.70 GHz,3556U,Discontinued,Q3'13,2,2,1.70 GHz,notFound,notFound
Intel® Xeon® E-2254ME Processor 8M Cache/ 2.60 GHz,E-2254ME,Launched,Q2'19,4,8,2.60 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i7-6700 Processor 8M Cache/ up to 4.00 GHz,i7-6700,Launched,Q3'15,4,8,3.40 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i7-4770R Processor 6M Cache/ up to 3.90 GHz,i7-4770R,Discontinued,Q2'13,4,8,3.20 GHz,3.90 GHz,3.90 GHz
Intel® Pentium® 4 Processor 660 supporting HT Technology 2M Cache/ 3.60 GHz/ 800 MHz FSB,660,Discontinued,Q1'05,1,notFound,3.60 GHz,notFound,notFound
Intel® Xeon® Processor E5462 12M Cache/ 2.80 GHz/ 1600 MHz FSB,E5462,Discontinued,Q4'07,4,notFound,2.80 GHz,notFound,notFound
Intel® Pentium® Processor 4405Y 2M Cache/ 1.50 GHz,4405Y,Discontinued,Q3'15,2,4,1.50 GHz,notFound,notFound
Intel® Xeon® Processor E3-1260L 8M Cache/ 2.40 GHz,E3-1260L,Discontinued,Q2'11,4,8,2.40 GHz,3.30 GHz,3.30 GHz
Intel® Celeron® Processor 877 2M Cache/ 1.40 GHz,877,Discontinued,Q2'12,2,2,1.40 GHz,notFound,notFound
Intel® Pentium® 4 Processor 550J supporting HT Technology 1M Cache/ 3.40 GHz/ 800 MHz FSB,550,Discontinued,Q4'04,1,notFound,3.40 GHz,notFound,notFound
Intel® Pentium® Processor 3561Y 2M Cache/ 1.20 GHz,3561Y,Discontinued,Q4'13,2,2,1.20 GHz,notFound,notFound
Intel® Celeron® Processor 550 1M Cache/ 2.00 GHz/ 533 MHz FSB,550,Discontinued,Q3'06,1,notFound,2.00 GHz,notFound,notFound
Intel® Quark™ SoC X1010 16K Cache/ 400 MHz,X1010,Discontinued,Q1'14,1,1,400 MHz,notFound,notFound
Intel® Core™ i5-4350U Processor 3M Cache/ up to 2.90 GHz,i5-4350U,Discontinued,Q3'13,2,4,1.40 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i7-3632QM Processor 6M Cache/ up to 3.20 GHz rPGA,i7-3632QM,Discontinued,Q3'12,4,8,2.20 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i7-1185G7E Processor 12M Cache/ up to 4.40 GHz,i7-1185G7E,Launched,Q3'20,4,8,1.80 GHz,4.40 GHz,notFound
Intel® Core™ i5-460M Processor 3M Cache/ 2.53 GHz,i5-460M,Discontinued,Q3'10,2,4,2.53 GHz,2.80 GHz,notFound
Intel® Xeon® Gold 5119T Processor 19.25M Cache/ 1.90 GHz,5119T,Launched,Q3'17,14,28,1.90 GHz,3.20 GHz,notFound
Intel® Core™ i7-1185GRE Processor 12M Cache/ up to 4.40 GHz,i7-1185GRE,Launched,Q3'20,4,8,1.80 GHz,4.40 GHz,notFound
Intel® Core™ i5-4570TE Processor 4M Cache/ up to 3.30 GHz,i5-4570TE,Launched,Q2'13,2,4,2.70 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i5-4360U Processor 3M Cache/ up to 3.00 GHz,i5-4360U,Discontinued,Q1'14,2,4,1.50 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i5-6300HQ Processor 6M Cache/ up to 3.20 GHz,i5-6300HQ,Discontinued,Q3'15,4,4,2.30 GHz,3.20 GHz,3.20 GHz
Intel® Pentium® Gold G6400 Processor 4M Cache/ 4.00 GHz,G6400,Launched,Q2'20,2,4,4.00 GHz,notFound,notFound
Intel® Core™ i5-670 Processor 4M Cache/ 3.46 GHz,i5-670,Discontinued,Q1'10,2,4,3.46 GHz,3.73 GHz,notFound
Intel® Core™ i7-1060G7 Processor 8M Cache/ up to 3.80 GHz,i7-1060G7,Launched,Q3'19,4,8,1.00 GHz,3.80 GHz,notFound
Intel® Xeon® Gold 6210U Processor 27.5M Cache/ 2.50 GHz,6210U,Launched,Q2'19,20,40,2.50 GHz,3.90 GHz,notFound
Intel® Core™ i7-9700K Processor 12M Cache/ up to 4.90 GHz,i7-9700K,Launched,Q4'18,8,8,3.60 GHz,4.90 GHz,4.90 GHz
Intel® Xeon® Processor E3-1235 8M Cache/ 3.20 GHz,E3-1235,Discontinued,Q2'11,4,8,3.20 GHz,3.60 GHz,3.60 GHz
Intel® Celeron® Processor G3900T 2M Cache/ 2.60 GHz,G3900T,Discontinued,Q4'15,2,2,2.60 GHz,notFound,notFound
Intel® Xeon® Processor E5450 12M Cache/ 3.00 GHz/ 1333 MHz FSB,E5450,Discontinued,Q4'07,4,notFound,3.00 GHz,notFound,notFound
Intel® Core™ i3-3250 Processor 3M Cache/ 3.50 GHz,i3-3250,Discontinued,Q2'13,2,4,3.50 GHz,notFound,notFound
Intel® Celeron® Processor G1850 2M Cache/ 2.90 GHz,G1850,Discontinued,Q2'14,2,2,2.90 GHz,notFound,notFound
Intel® Pentium® 4 Processor 651 supporting HT Technology 2M Cache/ 3.40 GHz/ 800 MHz FSB,651,Discontinued,Q2'06,1,notFound,3.40 GHz,notFound,notFound
Intel® Core™2 Duo Processor P7550 3M Cache/ 2.26 GHz/ 1066 MHz FSB,P7550,Discontinued,Q3'09,2,notFound,2.26 GHz,notFound,notFound
Intel® Xeon® W-3265 Processor 33M Cache/ 2.70 GHz,W-3265,Launched,Q2'19,24,48,2.70 GHz,4.40 GHz,notFound
Intel® Core™ i5-6600K Processor 6M Cache/ up to 3.90 GHz,i5-6600K,Discontinued,Q3'15,4,4,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i7-3635QM Processor 6M Cache/ up to 3.40 GHz,i7-3635QM,Discontinued,Q3'12,4,8,2.40 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® Processor E7-2850 v2 24M Cache/ 2.30 GHz,E7-2850V2,Discontinued,Q1'14,12,24,2.30 GHz,2.80 GHz,2.80 GHz
Intel® Core™ i9-7900X X-series Processor 13.75M Cache/ up to 4.30 GHz,i9-7900X,Discontinued,Q2'17,10,20,3.30 GHz,4.30 GHz,notFound
Intel® Itanium® Processor 9560 32M Cache/ 2.53 GHz,9560,Discontinued,Q4'12,8,16,2.53 GHz,notFound,notFound
Intel® Xeon® Silver 4114T Processor 13.75M Cache/ 2.20 GHz,4114T,Launched,Q3'17,10,20,2.20 GHz,3.00 GHz,notFound
Intel® Core™ i3-8140U Processor 4M Cache/ up to 3.90 GHz,i3-8140U,Launched,Q4'19,2,4,2.10 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i3-8140U Processor 4M Cache/ up to 3.90 GHz,i3-8140U,Launched,Q4'19,2,4,2.10 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i9-10850K Processor 20M Cache/ up to 5.20 GHz,i9-10850K,Launched,Q3'20,10,20,3.60 GHz,5.20 GHz,5.00 GHz
Intel® Xeon® Processor E3-1285L v3 8M Cache/ 3.10 GHz,E3-1285Lv3,Discontinued,Q2'13,4,8,3.10 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i3-560 Processor 4M Cache/ 3.33 GHz,i3-560,Discontinued,Q3'10,2,4,3.33 GHz,notFound,notFound
Intel® Core™ i7-620M Processor 4M Cache/ 2.66 GHz,i7-620M,Discontinued,Q1'10,2,4,2.66 GHz,3.33 GHz,notFound
Intel® Core™ i7-3689Y Processor 4M Cache/ up to 2.60 GHz,i7-3689Y,Discontinued,Q1'13,2,4,1.50 GHz,2.60 GHz,2.60 GHz
Intel® Xeon® Processor 5140 4M Cache/ 2.33 GHz/ 1333 MHz FSB,5140,Discontinued,Q2'06,2,notFound,2.33 GHz,notFound,notFound
Intel Atom® Processor N570 1M Cache/ 1.66 GHz,N570,Discontinued,Q1'11,2,4,1.66 GHz,notFound,notFound
Intel® Core™ i5-1145GRE Processor 8M Cache/ up to 4.10 GHz,i5-1145GRE,Launched,Q3'20,4,8,1.50 GHz,4.10 GHz,notFound
Intel® Core™ i3-12100T Processor 12M Cache/ up to 4.10 GHz,i3-12100T,Launched,Q1'22,4,8,notFound,4.10 GHz,notFound
Intel® Core™2 Duo Processor E7600 3M Cache/ 3.06 GHz/ 1066 MHz FSB,E7600,Discontinued,Q2'09,2,notFound,3.06 GHz,notFound,notFound
Intel® Core™ i5-10210Y Processor 6M Cache/ up to 4.00 GHz,i5-10210Y,Launched,Q3'19,4,8,1.00 GHz,4.00 GHz,notFound
Intel® Core™ i5-7400T Processor 6M Cache/ up to 3.00 GHz,i5-7400T,Discontinued,Q1'17,4,4,2.40 GHz,3.00 GHz,3.00 GHz
Intel® Core™2 Duo Processor T9900 6M Cache/ 3.06 GHz/ 1066 MHz FSB,T9900,Discontinued,Q2'09,2,notFound,3.06 GHz,notFound,notFound
Intel® Xeon Phi™ Coprocessor 5120D 8GB/ 1.053 GHz/ 60 core,5120D,Discontinued,Q2'13,60,notFound,1.05 GHz,notFound,notFound
Intel® Core™ i3-10300 Processor 8M Cache/ up to 4.40 GHz,i3-10300,Launched,Q2'20,4,8,3.70 GHz,4.40 GHz,4.40 GHz
Intel® Pentium® Gold G6505 Processor 4M Cache/ 4.20 GHz,G6505,Launched,Q1'21,2,4,4.20 GHz,notFound,notFound
Intel® Core™ i5-4200U Processor 3M Cache/ up to 2.60 GHz,i5-4200U,Discontinued,Q3'13,2,4,1.60 GHz,2.60 GHz,2.60 GHz
Intel® Core™2 Duo Processor T7800 4M Cache/ 2.60 GHz/ 800 MHz FSB,T7800,Discontinued,Q3'07,2,notFound,2.60 GHz,notFound,notFound
Intel® Celeron® Processor N2820 1M Cache/ up to 2.39 GHz,N2820,Discontinued,Q4'13,2,2,2.13 GHz,notFound,notFound
Intel® Core™ i3-6300 Processor 4M Cache/ 3.80 GHz,i3-6300,Discontinued,Q3'15,2,4,3.80 GHz,notFound,notFound
Intel® Core™ i7-4510U Processor 4M Cache/ up to 3.10 GHz,i7-4510U,Discontinued,Q2'14,2,4,2.00 GHz,3.10 GHz,3.10 GHz
Intel® Core™ i5-10500T Processor 12M Cache/ up to 3.80 GHz,i5-10500T,Launched,Q2'20,6,12,2.30 GHz,3.80 GHz,3.80 GHz
Intel® Pentium® Processor 2117U 2M Cache/ 1.80 GHz,2117U,Discontinued,Q3'12,2,2,1.80 GHz,notFound,notFound
Intel® Core™ m3-6Y30 Processor 4M Cache/ up to 2.20 GHz,M3-6Y30,Discontinued,Q3'15,2,4,900 MHz,2.20 GHz,2.20 GHz
Intel® Core™ m3-6Y30 Processor 4M Cache/ up to 2.20 GHz,M3-6Y30,Discontinued,Q3'15,2,4,900 MHz,2.20 GHz,2.20 GHz
Intel® Core™ i5-10310Y Processor 6M Cache/ up to 4.10 GHz,i5-10310Y,Discontinued,Q3'19,4,8,1.10 GHz,4.10 GHz,notFound
Intel® Core™ i5-L16G7 Processor 4M Cache/ up to 3.0GHz,i5-L16G7,Launched,Q2'20,5,5,1.40 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i3-3229Y Processor 3M Cache/ 1.40 GHz,i3-3229Y,Discontinued,Q1'13,2,4,1.40 GHz,notFound,notFound
Intel® Xeon® Processor E3-1225 v3 8M Cache/ 3.20 GHz,E3-1225V3,Launched,Q2'13,4,4,3.20 GHz,3.60 GHz,3.60 GHz
Intel® Core™ m3-8100Y Processor 4M Cache/ up to 3.40 GHz,m3-8100Y,Launched,Q3'18,2,4,1.10 GHz,3.40 GHz,3.40 GHz
Intel® Xeon Phi™ Processor 7285 16GB/ 1.3 GHz/ 68 Core,7285,Launched,Q4'17,68,notFound,1.30 GHz,1.40 GHz,notFound
Intel® Xeon® Processor L3110 6M Cache/ 3.00 GHz/ 1333 MHz FSB,L3110,Discontinued,Q1'09,2,notFound,3.00 GHz,notFound,notFound
Intel® Xeon® E-2276ML Processor 12M Cache/ 2.00 GHz,E-2276ML,Launched,Q2'19,6,12,2.00 GHz,4.20 GHz,4.20 GHz
Intel® Core™ i5-4210M Processor 3M Cache/ up to 3.20 GHz,i5-4210M,Discontinued,Q2'14,2,4,2.60 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Processor E5-2699A v4 55M Cache/ 2.40 GHz,E5-2699AV4,Launched,04'16,22,44,2.40 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i5-3470S Processor 6M Cache/ up to 3.60 GHz,i5-3470S,Discontinued,Q2'12,4,4,2.90 GHz,3.60 GHz,3.60 GHz
Intel® Pentium® Processor G3240 3M Cache/ 3.10 GHz,G3240,Discontinued,Q2'14,2,2,3.10 GHz,notFound,notFound
Intel® Xeon® Processor E5405 12M Cache/ 2.00 GHz/ 1333 MHz FSB,E5405,Discontinued,Q4'07,4,notFound,2.00 GHz,notFound,notFound
Intel® Pentium® 4 Processor 631 supporting HT Technology 2M Cache/ 3.00 GHz/ 800 MHz FSB,631,Discontinued,Q1'06,1,notFound,3.00 GHz,notFound,notFound
Intel® Pentium® Gold G6500T Processor 4M Cache/ 3.50 GHz,G6500T,Launched,Q2'20,2,4,3.50 GHz,notFound,notFound
Intel® Core™ i5-10500H Processor 12M Cache/ up to 4.50 GHz,i5-10500H,Launched,Q4'20,6,12,2.50 GHz,4.50 GHz,notFound
Intel® Core™ i5-7600T Processor 6M Cache/ up to 3.70 GHz,i5-7600T,Discontinued,Q1'17,4,4,2.80 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® Processor E3-1271 v3 8M Cache/ 3.60 GHz,E3-1271V3,Discontinued,Q2'14,4,8,3.60 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i5-7500 Processor 6M Cache/ up to 3.80 GHz,i5-7500,Launched,Q1'17,4,4,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i5-11500H Processor 12M Cache/ up to 4.60 GHz,i5-11500H,Launched,Q2'21,6,12,notFound,4.60 GHz,notFound
Intel® Core™ i3-3120ME Processor 3M Cache/ 2.40 GHz,i3-3120ME,Launched,Q3'12,2,4,2.40 GHz,notFound,notFound
Intel® Xeon® Platinum 8153 Processor 22M Cache/ 2.00 GHz,8153,Launched,Q3'17,16,32,2.00 GHz,2.80 GHz,notFound
Intel Atom® Processor Z615 512K Cache/ 1.60 GHz,Z615,Discontinued,Q2'10,1,2,1.60 GHz,notFound,notFound
Intel® Core™ i3-8300 Processor 8M Cache/ 3.70 GHz,i3-8300,Discontinued,Q2'18,4,4,3.70 GHz,notFound,notFound
Intel® Xeon® Gold 6238 Processor 30.25M Cache/ 2.10 GHz,6238,Launched,Q2'19,22,44,2.10 GHz,3.70 GHz,notFound
Intel® Xeon® E-2176G Processor 12M Cache/ up to 4.70 GHz,E-2176G,Launched,Q3'18,6,12,3.70 GHz,4.70 GHz,4.70 GHz
Intel® Xeon® Processor L5508 8M Cache/ 2.00 GHz/ 5.86 GT/s Intel® QPI,L5508,Discontinued,Q1'09,2,4,2.00 GHz,2.40 GHz,notFound
Intel® Core™2 Duo Processor SL9380 6M Cache/ 1.80 GHz/ 800 MHz FSB,SL9380,Discontinued,Q3'08,2,notFound,1.80 GHz,notFound,notFound
Intel® Celeron® Processor 2980U 2M Cache/ 1.60 GHz,2980U,Launched,Q3'13,2,2,1.60 GHz,notFound,notFound
Intel® Celeron® Processor 1047UE 2M Cache/ 1.40 GHz,1047UE,Launched,Q1'13,2,2,1.40 GHz,notFound,notFound
Intel® Xeon® Processor E3-1220L v3 4M Cache/ 1.10 GHz,E3-1220LV3,Discontinued,Q3'13,2,4,1.10 GHz,1.50 GHz,1.50 GHz
Intel® Core™ i5-9300HF Processor 8M Cache/ up to 4.10 GHz,i5-9300HF,Launched,Q2'19,4,8,2.40 GHz,4.10 GHz,notFound
Intel Atom® Processor Z650 512K Cache/ 1.20 GHz,Z650,Discontinued,Q2'11,1,2,1.20 GHz,notFound,notFound
Intel® Xeon® Gold 6230 Processor 27.5M Cache/ 2.10 GHz,6230,Launched,Q2'19,20,40,2.10 GHz,3.90 GHz,notFound
Intel® Xeon® Processor E5-2440 v2 20M Cache/ 1.90 GHz,E5-2440V2,Discontinued,Q1'14,8,16,1.90 GHz,2.40 GHz,2.40 GHz
Intel® Core™ i5-8305G Processor with Radeon™ RX Vega M GL graphics 6M Cache/ up to 3.80 GHz,i5-8305G,Announced,Q1'18,4,8,2.80 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Processor E3-1585 v5 8M Cache/ 3.50 GHz,E3-1585V5,Discontinued,Q2'16,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Pentium® Gold G5600 Processor 4M Cache/ 3.90 GHz,G5600,Discontinued,Q2'18,2,4,3.90 GHz,notFound,notFound
Intel® Xeon® Gold 6150 Processor 24.75M Cache/ 2.70 GHz,6150,Launched,Q3'17,18,36,2.70 GHz,3.70 GHz,notFound
Intel Atom® Processor C3758R 16M Cache/ 2.40 GHz,C3758R,Launched,Q2'20,8,8,2.40 GHz,notFound,notFound
Intel® Xeon® Processor W3570 8M Cache/ 3.20 GHz/ 6.40 GT/s Intel® QPI,W3570,Discontinued,Q1'09,4,8,3.20 GHz,3.46 GHz,notFound
Intel® Xeon® W-2195 Processor 24.75M Cache/ 2.30 GHz,W-2195,Launched,Q3'17,18,36,2.30 GHz,4.30 GHz,notFound
Intel® Xeon® Gold 6209U Processor 27.5M Cache/ 2.10 GHz,6209U,Launched,Q2'19,20,40,2.10 GHz,3.90 GHz,notFound
Intel® Core™2 Solo Processor U2100 1M Cache/ 1.06 GHz/ 533 MHz FSB,U2100,Discontinued,Q3'07,1,notFound,1.06 GHz,notFound,notFound
Intel® Core™ i7-7560U Processor 4M Cache/ up to 3.80 GHz,i7-7560U,Launched,Q1'17,2,4,2.40 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Gold 6328H Processor 22M Cache/ 2.80 GHz,6328H,Launched,Q2'20,16,32,2.80 GHz,4.30 GHz,notFound
Intel® Core™ i7-11800H Processor 24M Cache/ up to 4.60 GHz,i7-11800H,Launched,Q2'21,8,16,notFound,4.60 GHz,notFound
Intel® Core™ i7-11800H Processor 24M Cache/ up to 4.60 GHz,i7-11800H,Launched,Q2'21,8,16,notFound,4.60 GHz,notFound
Intel® Xeon® E-2134 Processor 8M Cache/ up to 4.50 GHz,E-2134,Launched,Q3'18,4,8,3.50 GHz,4.50 GHz,4.50 GHz
Intel® Core™ i7-4610Y Processor 4M Cache/ up to 2.90 GHz,i7-4610Y,Discontinued,Q3'13,2,4,1.70 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i7-7Y75 Processor 4M Cache/ up to 3.60 GHz,i7-7Y75,Launched,Q3'16,2,4,1.30 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® Gold 6142F Processor 22M Cache/ 2.60 GHz,6142F,Launched,Q3'17,16,32,2.60 GHz,3.70 GHz,notFound
Intel® Core™ i3-7102E Processor 3M Cache/ 2.10 GHz,i3-7102E,Launched,Q1'17,2,4,2.10 GHz,notFound,notFound
Intel® Core™ i5-9400T Processor 9M Cache/ up to 3.40 GHz,i5-9400T,Launched,Q2'19,6,6,1.80 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i5-2500K Processor 6M Cache/ up to 3.70 GHz,i5-2500K,Discontinued,Q1'11,4,4,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i7-4950HQ Processor 6M Cache/ up to 3.60 GHz,i7-4950HQ,Discontinued,Q3'13,4,8,2.40 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i7-5850HQ Processor 6M Cache/ up to 3.60 GHz,i7-5850HQ,Discontinued,Q2'15,4,8,2.70 GHz,3.60 GHz,3.60 GHz
Intel Atom® Processor Z670 512K Cache/ 1.50 GHz,Z670,Discontinued,Q2'11,1,2,1.50 GHz,notFound,notFound
Intel® Xeon® Processor E5-2450 v2 20M Cache/ 2.50 GHz,E5-2450V2,Discontinued,Q1'14,8,16,2.50 GHz,3.30 GHz,3.30 GHz
Intel Atom® Processor N270 512K Cache/ 1.60 GHz/ 533 MHz FSB,N270,Discontinued,Q2'08,1,notFound,1.60 GHz,notFound,notFound
Intel® Xeon® Processor E3-1270 v3 8M Cache/ 3.50 GHz,E3-1270 v3,Discontinued,Q2'13,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel Atom® Processor C3958 16M Cache/ up to 2.0 GHz,C3958,Launched,Q3'17,16,16,2.00 GHz,2.00 GHz,notFound
Intel® Xeon® Processor E5-4657L v2 30M Cache/ 2.40 GHz,E5-4657LV2,Discontinued,Q1'14,12,24,2.40 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i7-11375H Processor 12M Cache/ up to 5.00 GHz/ with IPU,i7-11375H,Launched,Q1'21,4,8,notFound,5.00 GHz,notFound
Intel® Xeon® E-2176M Processor 12M Cache/ up to 4.40 GHz,E-2176M,Launched,Q2'18,6,12,2.70 GHz,4.40 GHz,4.40 GHz
Intel® Xeon® Processor E5220 6M Cache/ 2.33 GHz/ 1333 MHz FSB,E5220,Discontinued,Q1'08,2,notFound,2.33 GHz,notFound,notFound
Intel® Core™ i7-2630QM Processor 6M Cache/ up to 2.90 GHz,i7-2630QM,Discontinued,Q1'11,4,8,2.00 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i7-8706G Processor with Radeon™ RX Vega M GL graphics 8M Cache/ up to 4.10 GHz,i7-8706G,Launched,Q1'18,4,8,3.10 GHz,4.10 GHz,4.10 GHz
Intel® Xeon® Processor E5310 8M Cache/ 1.60 GHz/ 1066 MHz FSB,E5310,Discontinued,Q4'06,4,notFound,1.60 GHz,notFound,notFound
Intel® Xeon® Gold 6238T Processor 30.25M Cache/ 1.90 GHz,6238T,Launched,Q2'19,22,44,1.90 GHz,3.70 GHz,notFound
Intel® Xeon® Processor E7-4807 18M Cache/ 1.86 GHz/ 4.80 GT/s Intel® QPI,E7-4807,Discontinued,Q2'11,6,12,1.86 GHz,notFound,notFound
Intel® Pentium® Processor T2080 1M Cache/ 1.73 GHz/ 533 MHz FSB,T2080,Discontinued,Q2'07,2,notFound,1.73 GHz,notFound,notFound
Intel® Xeon® W-1250TE Processor 12M Cache/ up to 3.80 GHz,W-1250TE,Launched,Q2'20,6,12,2.40 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i3-3217UE Processor 3M Cache/ 1.60 GHz,i3-3217UE,Launched,Q3'12,2,4,1.60 GHz,notFound,notFound
Intel® Xeon® Silver 4209T Processor 11M Cache/ 2.20 GHz,4209T,Launched,Q2'19,8,16,2.20 GHz,3.20 GHz,notFound
Intel® Xeon® Platinum 8156 Processor 16.5M Cache/ 3.60 GHz,8156,Launched,Q3'17,4,8,3.60 GHz,3.70 GHz,notFound
Intel® Xeon® Processor E5-2687W 20M Cache/ 3.10 GHz/ 8.00 GT/s Intel® QPI,E5-2687W,Discontinued,Q1'12,8,16,3.10 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i7-640UM Processor 4M Cache/ 1.20 GHz,i7-640UM,Discontinued,Q1'10,2,4,1.20 GHz,2.27 GHz,notFound
Intel® Core™ i5-4210Y Processor 3M Cache/ up to 1.90 GHz,i5-4210Y,Discontinued,Q3'13,2,4,1.50 GHz,1.90 GHz,1.90 GHz
Intel® Core™ i7-9750H Processor 12M Cache/ up to 4.50 GHz,i7-9750H,Launched,Q2'19,6,12,2.60 GHz,4.50 GHz,notFound
Intel® Core™ i7-9750H Processor 12M Cache/ up to 4.50 GHz,i7-9750H,Launched,Q2'19,6,12,2.60 GHz,4.50 GHz,notFound
Intel® Xeon Phi™ Processor 7230F 16GB/ 1.30 GHz/ 64 core,7230F,Discontinued,Q4'16,64,notFound,1.30 GHz,1.50 GHz,notFound
Intel Atom® Processor D525 1M Cache/ 1.80 GHz,D525,Discontinued,Q2'10,2,4,1.80 GHz,notFound,notFound
Intel® Xeon® W-1250E Processor 12M Cache/ up to 4.70 GHz,W-1250E,Launched,Q2'20,6,12,3.50 GHz,4.70 GHz,4.70 GHz
Intel Atom® Processor C3538 8M Cache/ up to 2.10 GHz,C3538,Launched,Q3'17,4,4,2.10 GHz,2.10 GHz,notFound
Intel® Xeon® Processor E5-2658A v3 30M Cache/ 2.20 GHz,E5-2658AV3,Launched,Q1'15,12,24,2.20 GHz,2.90 GHz,2.90 GHz
Intel® Core™2 Duo Processor U7500 2M Cache/ 1.06 GHz/ 533 MHz FSB Socket M,U7500,Discontinued,Q3'06,2,notFound,1.06 GHz,notFound,notFound
Intel Atom® Processor Z600 512K Cache/ 1.20 GHz,Z600,Discontinued,Q2'10,1,2,1.20 GHz,notFound,notFound
Intel® Core™ i7-5750HQ Processor 6M Cache/ up to 3.40 GHz,i7-5750HQ,Discontinued,Q2'15,4,8,2.50 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i7-4600U Processor 4M Cache/ up to 3.30 GHz,i7-4600U,Discontinued,Q3'13,2,4,2.10 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® E-2274G Processor 8M Cache/ 4.00 GHz,E-2274G,Launched,Q2'19,4,8,4.00 GHz,4.90 GHz,4.90 GHz
Intel® Xeon® Processor X3380 12M Cache/ 3.16 GHz/ 1333 MHz FSB,X3380,Discontinued,Q1'09,4,notFound,3.16 GHz,notFound,notFound
Intel® Xeon® Processor E5-2650L 20M Cache/ 1.80 GHz/ 8.00 GT/s Intel® QPI,E5-2650L,Discontinued,Q1'12,8,16,1.80 GHz,2.30 GHz,2.30 GHz
Intel® Xeon® Gold 5318H Processor 24.75M Cache/ 2.50 GHz,5318H,Launched,Q2'20,18,36,2.50 GHz,3.80 GHz,notFound
Intel® Xeon® E-2124 Processor 8M Cache/ up to 4.30 GHz,E-2124,Launched,Q3'18,4,4,3.30 GHz,4.30 GHz,4.30 GHz
Intel® Core™ i5-1035G1 Processor 6M Cache/ up to 3.60 GHz,i5-1035G1,Launched,Q3'19,4,8,1.00 GHz,3.60 GHz,notFound
Intel® Core™ i9-11900K Processor 16M Cache/ up to 5.30 GHz,i9-11900K,Launched,Q1'21,8,16,3.50 GHz,5.30 GHz,5.10 GHz
Intel Atom® Processor Z560 512K Cache/ 2.13 GHz/ 533 MHz FSB,Z560,Discontinued,Q2'10,1,notFound,2.13 GHz,notFound,notFound
Intel® Xeon® Silver 4214 Processor 16.5M Cache/ 2.20 GHz,4214,Launched,Q2'19,12,24,2.20 GHz,3.20 GHz,notFound
Intel® Core™2 Duo Processor P8800 3M Cache/ 2.66 GHz/ 1066 MHz FSB,P8800,Discontinued,Q2'09,2,notFound,2.66 GHz,notFound,notFound
Intel® Xeon® Processor E7-8870 v2 30M Cache/ 2.30 GHz,E7-8870V2,Launched,Q1'14,15,30,2.30 GHz,2.90 GHz,2.90 GHz
Intel® Celeron® D Processor 360 512K Cache/ 3.46 GHz/ 533 MHz FSB,360,Discontinued,Q4'06,1,notFound,3.46 GHz,notFound,notFound
Intel® Core™ i7-6660U Processor 4M Cache/ up to 3.40 GHz,i7-6660U,Discontinued,Q1'16,2,4,2.40 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® D-1637 Processor 9M Cache/ 2.90GHz,D-1637,Launched,Q2'19,6,12,2.90 GHz,3.20 GHz,3.20 GHz
Intel® Celeron® Processor 4205U 2M Cache/ 1.80 GHz,4205U,Launched,Q1'19,2,2,1.80 GHz,notFound,notFound
Intel® Xeon® Platinum 8380HL Processor 38.5M Cache/ 2.90 GHz,8380HL,Launched,Q2'20,28,56,2.90 GHz,4.30 GHz,notFound
Intel® Xeon® Gold 6338N Processor 48M Cache/ 2.20 GHz,6338N,Launched,Q2'21,32,64,2.20 GHz,3.50 GHz,notFound
Intel® Xeon® Processor E5-2620 v4 20M Cache/ 2.10 GHz,E5-2620V4,Launched,Q1'16,8,16,2.10 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i7-9700 Processor 12M Cache/ up to 4.70 GHz,i7-9700,Launched,Q2'19,8,8,3.00 GHz,4.70 GHz,4.70 GHz
Intel® Xeon® E-2356G Processor 12M Cache/ 3.20 GHz,E-2356G,Launched,Q3'21,6,12,3.20 GHz,5.00 GHz,5.00 GHz
Intel® Celeron® Processor G4930E 2M Cache/ 2.40 GHz,G4930E,Launched,Q2'19,2,2,2.40 GHz,2.40 GHz,notFound
Intel® Celeron® Processor G3902E 2M Cache/ 1.60 GHz,G3902E,Launched,Q1'16,2,2,1.60 GHz,notFound,notFound
Intel® Core™ i7-3770T Processor 8M Cache/ up to 3.70 GHz,i7-3770T,Discontinued,Q2'12,4,8,2.50 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® Processor E3-1275L v3 8M Cache/ 2.70 GHz,E3-1275LV3,Discontinued,Q2'14,4,8,2.70 GHz,3.90 GHz,3.90 GHz
Intel® Core™2 Duo Processor E4600 2M Cache/ 2.40 GHz/ 800 MHz FSB,E4600,Discontinued,Q4'07,2,notFound,2.40 GHz,notFound,notFound
Intel® Core™ i7-1195G7 Processor 12M Cache/ up to 5.00 GHz,i7-1195G7,Launched,Q2'21,4,8,notFound,5.00 GHz,notFound
Intel® Core™ i3-2100T Processor 3M Cache/ 2.50 GHz,i3-2100T,Discontinued,Q1'11,2,4,2.50 GHz,notFound,notFound
Intel® Xeon® Processor E5-2648L v3 30M Cache/ 1.80 GHz,E5-2648LV3,Launched,Q3'14,12,24,1.80 GHz,2.50 GHz,2.50 GHz
Intel® Pentium® Processor J3710 2M Cache/ up to 2.64 GHz,J3710,Launched,Q1'16,4,4,1.60 GHz,notFound,notFound
Intel® Core™ i3-12100TE Processor 12M Cache/ up to 4.00 GHz,i3-12100TE,Launched,Q1'22,4,8,notFound,4.00 GHz,notFound
Intel® Xeon® W-1390P Processor 16M Cache/ up to 5.30 GHz,W-1390P,Launched,Q2'21,8,16,3.50 GHz,5.30 GHz,5.10 GHz
Intel® Core™ i3-1005G1 Processor 4M Cache/ up to 3.40 GHz,i3-1005G1,Launched,Q3'19,2,4,1.20 GHz,3.40 GHz,notFound
Intel® Core™ i5-12500H Processor 18M Cache/ up to 4.50 GHz,i5-12500H,Launched,Q1'22,12,16,notFound,notFound,notFound
Intel® Core™ i5-4460S Processor 6M Cache/ up to 3.40 GHz,i5-4460S,Discontinued,Q2'14,4,4,2.90 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i9-7920X X-series Processor 16.5M Cache/ up to 4.30 GHz,i9-7920X,Discontinued,Q3'17,12,24,2.90 GHz,4.30 GHz,notFound
Intel® Core™ i5-6360U Processor 4M Cache/ up to 3.10 GHz,i5-6360U,Discontinued,Q3'15,2,4,2.00 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Processor E5-4660 v3 35M Cache/ 2.10 GHz,E5-4660V3,Discontinued,Q2'15,14,28,2.10 GHz,2.90 GHz,2.90 GHz
Intel® Xeon® Processor E3-1265L v2 8M Cache/ 2.50 GHz,E3-1265LV2,Discontinued,Q2'12,4,8,2.50 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® Processor E5-2618L v2 15M Cache/ 2.00 GHz,E5-2618LV2,Launched,Q3'13,6,12,2.00 GHz,2.00 GHz,notFound
Intel® Core™ i3-2102 Processor 3M Cache/ 3.10 GHz,i3-2102,Discontinued,Q2'11,2,4,3.10 GHz,notFound,notFound
Intel® Core™ i3-4110M Processor 3M Cache/ 2.60 GHz,i3-4110M,Discontinued,Q2'14,2,4,2.60 GHz,notFound,notFound
Intel® Xeon® Processor L5520 8M Cache/ 2.26 GHz/ 5.86 GT/s Intel® QPI,L5520,Discontinued,Q1'09,4,8,2.26 GHz,2.48 GHz,notFound
Intel® Pentium® Gold G7400TE Processor 6M Cache/ 3.00 GHz,G7400TE,Launched,Q1'22,2,4,notFound,notFound,notFound
Intel® Core™ i7-3612QE Processor 6M Cache/ up to 3.10 GHz,i7-3612QE,Launched,Q2'12,4,8,2.10 GHz,3.10 GHz,3.10 GHz
Intel® Core™ i5-4402E Processor 3M Cache/ up to 2.70 GHz,i5-4402E,Launched,Q3'13,2,4,1.60 GHz,2.70 GHz,2.70 GHz
Intel® Celeron® Processor 3215U 2M Cache/ 1.70 GHz,3215U,Discontinued,Q2'15,2,2,1.70 GHz,notFound,notFound
Intel® Core™2 Extreme Processor QX6800 8M Cache/ 2.93 GHz/ 1066 MHz FSB,QX6800,Discontinued,Q2'07,4,notFound,2.93 GHz,notFound,notFound
Intel® Xeon® Processor E5-2630 v4 25M Cache/ 2.20 GHz,E5-2630V4,Launched,Q1'16,10,20,2.20 GHz,3.10 GHz,3.10 GHz
Intel® Celeron® Processor J1900 2M Cache/ up to 2.42 GHz,J1900,Launched,Q4'13,4,4,2.00 GHz,notFound,notFound
Intel® Core™ i3-7130U Processor 3M Cache/ 2.70 GHz,i3-7130U,Launched,Q2'17,2,4,2.70 GHz,notFound,notFound
Intel® Xeon® Platinum 8376HL Processor 38.5M Cache/ 2.60 GHz,8376HL,Launched,Q2'20,28,56,2.60 GHz,4.30 GHz,notFound
Intel® Core™ i7-2720QM Processor 6M Cache/ up to 3.30 GHz,i7-2720QM,Discontinued,Q1'11,4,8,2.20 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i7-4550U Processor 4M Cache/ up to 3.00 GHz,i7-4550U,Discontinued,Q3'13,2,4,1.50 GHz,3.00 GHz,3.00 GHz
Intel® Xeon® D-1633N Processor 9M Cache/ 2.50GHz,D-1633N,Launched,Q2'19,6,12,2.50 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Processor E3-1285L v4 6M Cache/ 3.40 GHz,E3-1285LV4,Discontinued,Q2'15,4,8,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Processor X3460 8M Cache/ 2.80 GHz,X3460,Discontinued,Q3'09,4,8,2.80 GHz,3.46 GHz,notFound
Intel® Core™ i7-860S Processor 8M Cache/ 2.53 GHz,i7-860S,Discontinued,Q1'10,4,8,2.53 GHz,3.46 GHz,notFound
Intel® Xeon® Processor E5-4655 v3 30M Cache/ 2.90 GHz,E5-4655V3,Discontinued,Q2'15,6,12,2.90 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i7-11850HE Processor 24M Cache/ up to 4.70 GHz,i7-11850HE,Launched,Q3'21,8,16,notFound,4.70 GHz,notFound
Intel® Pentium® Processor G645 3M Cache/ 2.90 GHz,G645,Discontinued,Q3'12,2,2,2.90 GHz,notFound,notFound
Intel® Xeon® Gold 6338T Processor 36M Cache/ 2.10 GHz,6338T,Launched,Q2'21,24,48,2.10 GHz,3.40 GHz,notFound
Intel® Core™ i3-12100F Processor 12M Cache/ up to 4.30 GHz,i3-12100F,Launched,Q1'22,4,8,notFound,4.30 GHz,notFound
Intel® Xeon® Processor E5-4603 10M Cache/ 2.00 GHz/ 6.40 GT/s Intel® QPI,E5-4603,Discontinued,Q2'12,4,8,2.00 GHz,notFound,notFound
Intel® Xeon® Gold 5320 Processor 39M Cache/ 2.20 GHz,5320,Launched,Q2'21,26,52,2.20 GHz,3.40 GHz,notFound
Intel® Xeon® Processor E3-1275 v2 8M Cache/ 3.50 GHz,E3-1275V2,Launched,Q2'12,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Celeron® Processor T3500 1M Cache/ 2.10 GHz/ 800 MHz FSB,T3500,Discontinued,Q3'10,2,notFound,2.10 GHz,notFound,notFound
Intel® Xeon® Processor LC5518 8M Cache/ 1.73 GHz/ 4.80 GT/s Intel® QPI,LC5518,Discontinued,Q1'10,4,8,1.73 GHz,2.13 GHz,notFound
Intel® Xeon® Processor E5-2430L v2 15M Cache/ 2.40 GHz,E5-2430LV2,Discontinued,Q1'14,6,12,2.40 GHz,2.80 GHz,2.80 GHz
Intel® Xeon® Processor X3330 6M Cache/ 2.66 GHz/ 1333 MHz FSB,X3330,Discontinued,Q3'08,4,notFound,2.66 GHz,notFound,notFound
Intel® Celeron® 6600HE Processor 8M Cache/ up to 2.60 GHz,6600HE,Launched,Q3'21,2,2,2.60 GHz,notFound,notFound
Intel® Core™ i5-4590S Processor 6M Cache/ up to 3.70 GHz,i5-4590S,Launched,Q2'14,4,4,3.00 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i7-4770S Processor 8M Cache/ up to 3.90 GHz,i7-4770S,Launched,Q2'13,4,8,3.10 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Gold 5318Y Processor 36M Cache/ 2.10 GHz,5318Y,Launched,Q2'21,24,48,2.10 GHz,3.40 GHz,notFound
Intel® Itanium® Processor 9750 32M Cache/ 2.53 GHz,9750,Discontinued,Q2'17,4,8,2.53 GHz,notFound,notFound
Intel® Xeon® W-1370P Processor 16M Cache/ up to 5.20 GHz,W-1370P,Launched,Q2'21,8,16,3.60 GHz,5.20 GHz,5.10 GHz
Intel® Core™ i3-1000NG4 Processor 4M Cache/ up to 3.20 GHz,i3-1000NG4,Launched,Q2'20,2,4,1.10 GHz,3.20 GHz,notFound
Intel® Xeon® Gold 6246R Processor 35.75M Cache/ 3.40 GHz,6246R,Launched,Q1'20,16,32,3.40 GHz,4.10 GHz,notFound
Intel® Core™ i5-6442EQ Processor 6M Cache/ up to 2.70 GHz,i5-6442EQ,Launched,Q4'15,4,4,1.90 GHz,2.70 GHz,2.70 GHz
Intel® Core™ i7-3770 Processor 8M Cache/ up to 3.90 GHz,i7-3770,Discontinued,Q2'12,4,8,3.40 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i5-6440EQ Processor 6M Cache/ up to 3.40 GHz,i5-6440EQ,Launched,Q4'15,4,4,2.70 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® Processor E5-2608L v4 20M Cache/ 1.60 GHz,E5-2608LV4,Launched,Q1'16,8,16,1.60 GHz,1.70 GHz,1.70 GHz
Intel® Xeon® E-2314 Processor 8M Cache/ 2.80 GHz,E-2314,Launched,Q3'21,4,4,2.80 GHz,4.50 GHz,4.50 GHz
Intel® Core™ i9-12900HK Processor 24M Cache/ up to 5.00 GHz,i9-12900HK,Launched,Q1'22,14,20,notFound,notFound,notFound
Intel® Celeron® Processor G440 1M Cache/ 1.60 GHz,G440,Discontinued,Q3'11,1,1,1.60 GHz,notFound,notFound
Intel® Core™ i3-3240T Processor 3M Cache/ 2.90 GHz,i3-3240T,Discontinued,Q3'12,2,4,2.90 GHz,notFound,notFound
Intel® Core™ i5-12400 Processor 18M Cache/ up to 4.40 GHz,i5-12400,Launched,Q1'22,6,12,notFound,4.40 GHz,notFound
Intel® Core™ i7-6567U Processor 4M Cache/ up to 3.60 GHz,i7-6567U,Discontinued,Q3'15,2,4,3.30 GHz,3.60 GHz,3.60 GHz
Intel® Celeron® Processor G6900E 4M Cache/ 3.00 GHz,G6900E,Launched,Q1'22,2,2,notFound,notFound,notFound
Intel® Xeon® E-2378 Processor 16M Cache/ 2.60 GHz,E-2378,Launched,Q3'21,8,16,2.60 GHz,4.80 GHz,4.80 GHz
Intel® Xeon® Gold 6342 Processor 36M Cache/ 2.80 GHz,6342,Launched,Q2'21,24,48,2.80 GHz,3.50 GHz,notFound
Intel® Itanium® Processor 9760 32M Cache/ 2.66 GHz,9760,Launched,Q2'17,8,16,2.66 GHz,notFound,notFound
Intel® Xeon® Processor E5-4620 16M Cache/ 2.20 GHz/ 7.20 GT/s Intel® QPI,E5-4620,Discontinued,Q2'12,8,16,2.20 GHz,2.60 GHz,2.60 GHz
Intel® Core™ i7-4770K Processor 8M Cache/ up to 3.90 GHz,i7-4770K,Discontinued,Q2'13,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i7-860 Processor 8M Cache/ 2.80 GHz,i7-860,Discontinued,Q3'09,4,8,2.80 GHz,3.46 GHz,notFound
Intel® Celeron® D Processor 310 256K Cache/ 2.13 GHz/ 533 MHz FSB,310,Discontinued,Q4'05,1,notFound,2.13 GHz,notFound,notFound
Intel® Xeon® W-11555MLE Processor 12M Cache/ up to 4.40 GHz,W-11555MLE,Launched,Q3'21,6,12,1.90 GHz,4.40 GHz,notFound
Intel® Core™ i5-4690K Processor 6M Cache/ up to 3.90 GHz,i5-4690K,Discontinued,Q2'14,4,4,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Celeron® Processor N2910 2M Cache/ 1.60 GHz,N2910,Discontinued,Q3'13,4,4,1.60 GHz,notFound,notFound
Intel® Core™ i7-3610QM Processor 6M Cache/ up to 3.30 GHz,i7-3610QM,Discontinued,Q2'12,4,8,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i7-950 Processor 8M Cache/ 3.06 GHz/ 4.80 GT/s Intel® QPI,i7-950,Discontinued,Q2'09,4,8,3.06 GHz,3.33 GHz,notFound
Intel® Celeron® Processor G530T 2M Cache/ 2.00 GHz,G530T,Discontinued,Q3'11,2,2,2.00 GHz,notFound,notFound
Intel® Xeon® Processor EC5509 8M Cache/ 2.00 GHz/ 4.80 GT/s Intel® QPI,EC5509,Discontinued,Q1'10,4,4,2.00 GHz,notFound,notFound
Intel® Xeon® Processor E5-1660 v2 15M Cache/ 3.70 GHz,E5-1660V2,Discontinued,Q3'13,6,12,3.70 GHz,4.00 GHz,4.00 GHz
Intel® Xeon® Gold 6312U Processor 36M Cache/ 2.40 GHz,6312U,Launched,Q2'21,24,48,2.40 GHz,3.60 GHz,notFound
Intel® Xeon® Processor E7-8860 v3 40M Cache/ 2.20 GHz,E7-8860V3,Launched,Q2'15,16,32,2.20 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i5-6260U Processor 4M Cache/ up to 2.90 GHz,i5-6260U,Discontinued,Q3'15,2,4,1.80 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i5-6260U Processor 4M Cache/ up to 2.90 GHz,i5-6260U,Discontinued,Q3'15,2,4,1.80 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i9-12900E Processor 30M Cache/ up to 5.00 GHz,i9-12900E,Launched,Q1'22,16,24,notFound,5.00 GHz,5.00 GHz
Intel Atom® x3-C3230RK Processor 1M Cache/ up to 1.10 GHz,x3-C3230RK,Discontinued,Q1'15,4,notFound,notFound,notFound,notFound
Intel Atom® Processor E665C 512K Cache/ 1.3 GHz,E665C,Discontinued,Q4'10,1,2,1.30 GHz,notFound,notFound
Intel® Pentium® Processor G4400TE 3M Cache/ 2.40 GHz,G4400TE,Launched,Q4'15,2,2,2.40 GHz,notFound,notFound
Intel® Xeon® Processor E5-2680 v3 30M Cache/ 2.50 GHz,E5-2680V3,Launched,Q3'14,12,24,2.50 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® Processor D-1529 6M Cache/ 1.30 GHz,D-1529,Launched,Q2'16,4,8,1.30 GHz,1.30 GHz,notFound
Intel® Xeon® Gold 5220R Processor 35.75M Cache/ 2.20 GHz,5220R,Launched,Q1'20,24,48,2.20 GHz,4.00 GHz,notFound
Intel® Xeon® Processor E5-2428L v2 20M Cache/ 1.80 GHz,E5-2428LV2,Launched,Q1'14,8,16,1.80 GHz,2.30 GHz,2.30 GHz
Intel® Celeron® Processor J3455 2M Cache/ up to 2.30 GHz,J3455,Launched,Q3'16,4,4,1.50 GHz,notFound,notFound
Intel Atom® Processor Z3735F 2M Cache/ up to 1.83 GHz,Z3735F,Discontinued,Q1'14,4,notFound,1.33 GHz,notFound,notFound
Intel Atom® Processor Z3560 2M Cache/ up to 1.83 GHz,Z3560,Discontinued,Q2'14,4,notFound,notFound,notFound,notFound
Intel® Core™ i9-10940X X-series Processor 19.25M Cache/ 3.30 GHz,i9-10940X,Launched,Q4'19,14,28,3.30 GHz,4.60 GHz,notFound
Intel® Xeon® Processor E5-4650 v4 35M Cache/ 2.20 GHz,E5-4650V4,Launched,Q2'16,14,28,2.20 GHz,2.80 GHz,2.80 GHz
Intel® Core™ i5-7Y57 Processor 4M Cache/ up to 3.30 GHz,i5-7Y57,Launched,Q1'17,2,4,1.20 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i5-7Y57 Processor 4M Cache/ up to 3.30 GHz,i5-7Y57,Launched,Q1'17,2,4,1.20 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i5-9400F Processor 9M Cache/ up to 4.10 GHz,i5-9400F,Launched,Q1'19,6,6,2.90 GHz,4.10 GHz,4.10 GHz
Intel® Core™ i7-875K Processor 8M Cache/ 2.93 GHz,i7-875K,Discontinued,Q2'10,4,8,2.93 GHz,3.60 GHz,notFound
Intel® Xeon® Processor X5272 6M Cache/ 3.40 GHz/ 1600 MHz FSB,X5272,Discontinued,Q4'07,2,notFound,3.40 GHz,notFound,notFound
Intel® Celeron® J4105 Processor 4M Cache/ up to 2.50 GHz,J4105,Launched,Q4'17,4,4,1.50 GHz,notFound,notFound
Intel® Xeon® Processor E5540 8M Cache/ 2.53 GHz/ 5.86 GT/s Intel® QPI,E5540,Discontinued,Q1'09,4,8,2.53 GHz,2.80 GHz,notFound
Intel® Xeon® Processor E7-2820 18M Cache/ 2.00 GHz/ 5.86 GT/s Intel® QPI,E7-2820,Discontinued,Q2'11,8,16,2.00 GHz,2.27 GHz,notFound
Intel® Xeon® Processor E5-2670 v3 30M Cache/ 2.30 GHz,E5-2670V3,Discontinued,Q3'14,12,24,2.30 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Processor E3-1501L v6 6M Cache/ up to 2.90 GHz,E3-1501LV6,Launched,Q2'17,4,4,2.10 GHz,2.90 GHz,2.90 GHz
Intel® Celeron® Processor 575 1M Cache/ 2.00 GHz/ 667 MHz FSB,575,Discontinued,Q3'06,1,notFound,2.00 GHz,notFound,notFound
Intel® Celeron® Processor J6412 1.5M Cache/ up to 2.60 GHz,J6412,Launched,Q1'21,4,4,2.00 GHz,notFound,notFound
Intel® Core™ i5-9600KF Processor 9M Cache/ up to 4.60 GHz,i5-9600KF,Launched,Q1'19,6,6,3.70 GHz,4.60 GHz,4.60 GHz
Intel® Core™ i7-7600U Processor 4M Cache/ up to 3.90 GHz,i7-7600U,Launched,Q1'17,2,4,2.80 GHz,3.90 GHz,3.90 GHz
Intel® Pentium® Processor D1517 6M Cache/ 1.60 GHz,D1517,Launched,Q4'15,4,8,1.60 GHz,2.20 GHz,2.20 GHz
Intel® Core™2 Extreme Processor QX6850 8M Cache/ 3.00 GHz/ 1333 MHz FSB,QX6850,Discontinued,Q3'07,4,notFound,3.00 GHz,notFound,notFound
Intel® Xeon® Processor E5-2448L v2 25M Cache/ 1.80 GHz,E5-2448LV2,Launched,Q1'14,10,20,1.80 GHz,2.40 GHz,2.40 GHz
Intel Atom® Processor Z3735E 2M Cache/ up to 1.83 GHz,Z3735E,Discontinued,Q1'14,4,notFound,1.33 GHz,notFound,notFound
Intel® Xeon® Processor E5-2603 v2 10M Cache/ 1.80 GHz,E5-2603V2,Discontinued,Q3'13,4,4,1.80 GHz,notFound,notFound
Intel® Core™ i5-7440HQ Processor 6M Cache/ up to 3.80 GHz,i5-7440HQ,Launched,Q1'17,4,4,2.80 GHz,3.80 GHz,3.80 GHz
Intel® Celeron® Processor G3930E 2M Cache/ 2.90 GHz,G3930E,Launched,Q2'17,2,2,2.90 GHz,notFound,notFound
Intel® Xeon® Processor E5-2428L 15M/ 1.8 GHz/ 7.2 GT/s Intel® QPI,E5-2428L,Discontinued,Q2'12,6,12,1.80 GHz,2.00 GHz,2.00 GHz
Intel Atom® Processor Z520 512K Cache/ 1.33 GHz/ 533 MHz FSB,Z520,Discontinued,Q2'08,1,notFound,1.33 GHz,notFound,notFound
Intel® Xeon® W-1270P Processor 16M Cache/ 3.80 GHz,W-1270P,Launched,Q2'20,8,16,3.80 GHz,5.10 GHz,5.00 GHz
Intel® Xeon® Processor E7-2830 24M Cache/ 2.13 GHz/ 6.40 GT/s Intel® QPI,E7-2830,Discontinued,Q2'11,8,16,2.13 GHz,2.40 GHz,notFound
Intel® Xeon® Processor E5530 8M Cache/ 2.40 GHz/ 5.86 GT/s Intel® QPI,E5530,Discontinued,Q1'09,4,8,2.40 GHz,2.66 GHz,notFound
Intel® Core™ i5-2320 Processor 6M Cache/ up to 3.30 GHz,i5-2320,Discontinued,Q3'11,4,4,3.00 GHz,3.30 GHz,3.30 GHz
Intel Atom® x3-C3205RK Processor 1M Cache/ up to 1.20 GHz,x3-3205RK,Discontinued,Q4'16,4,notFound,notFound,notFound,notFound
Intel® Celeron® Processor 450 512K Cache/ 2.20 GHz/ 800 MHz FSB,450,Discontinued,Q3'08,1,notFound,2.20 GHz,notFound,notFound
Intel® Core™ i9-10900KF Processor 20M Cache/ up to 5.30 GHz,i9-10900KF,Launched,Q2'20,10,20,3.70 GHz,5.30 GHz,5.10 GHz
Intel® Pentium® Processor D1507 3M Cache/ 1.20 GHz,D1507,Launched,Q4'15,2,2,1.20 GHz,notFound,notFound
Intel® Xeon® Processor E5-2698 v4 50M Cache/ 2.20 GHz,E5-2698V4,Launched,Q1'16,20,40,2.20 GHz,3.60 GHz,3.60 GHz
Intel® Celeron® M Processor ULV 743 1M Cache/ 1.30 GHz/ 800 MHz FSB,743,Discontinued,Q3'09,1,notFound,1.30 GHz,notFound,notFound
Intel® Core™ i7-2675QM Processor 6M Cache/ up to 3.10 GHz,i7-2675QM,Discontinued,Q4'11,4,8,2.20 GHz,3.10 GHz,3.10 GHz
Intel® Core™ i7-7740X X-series Processor 8M Cache/ up to 4.50 GHz,i7-7740X,Discontinued,Q2'17,4,8,4.30 GHz,4.50 GHz,4.50 GHz
Intel® Celeron® Processor 540 1M Cache/ 1.86 GHz/ 533 MHz FSB,540,Discontinued,Q3'07,1,notFound,1.86 GHz,notFound,notFound
Intel® Xeon® Processor E5-2687W v2 25M Cache/ 3.40 GHz,E5-2687WV2,Discontinued,Q3'13,8,16,3.40 GHz,4.00 GHz,4.00 GHz
Intel® Xeon® Processor E7220 8M Cache/ 2.93 GHz/ 1066 MHz FSB,E7220,Discontinued,Q3'07,2,notFound,2.93 GHz,notFound,notFound
Intel® Xeon® Processor E5-4667 v4 45M Cache/ 2.20 GHz,E5-4667V4,Launched,Q2'16,18,36,2.20 GHz,3.00 GHz,3.00 GHz
Intel® Pentium® Processor G630T 3M Cache/ 2.30 GHz,G630T,Discontinued,Q3'11,2,2,2.30 GHz,notFound,notFound
Intel® Xeon® Processor E5-2680 v4 35M Cache/ 2.40 GHz,E5-2680V4,Launched,Q1'16,14,28,2.40 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® W-1290P Processor 20M Cache/ 3.70 GHz,W-1290P,Launched,Q2'20,10,20,3.70 GHz,5.30 GHz,5.10 GHz
Intel® Celeron® Processor T1600 1M Cache/ 1.66 GHz/ 667 MHz FSB,T1600,Discontinued,Q4'08,2,notFound,1.66 GHz,notFound,notFound
Intel® Core™ i5-2390T Processor 3M Cache/ up to 3.50 GHz,i5-2390T,Discontinued,Q1'11,2,4,2.70 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i7-8700K Processor 12M Cache/ up to 4.70 GHz,i7-8700K,Discontinued,Q4'17,6,12,3.70 GHz,4.70 GHz,4.70 GHz
Intel® Xeon® Processor E5-2648L v2 25M Cache/ 1.90 GHz,E5-2648LV2,Launched,Q3'13,10,20,1.90 GHz,2.50 GHz,2.50 GHz
Intel® Core™ i3-7300T Processor 4M Cache/ 3.50 GHz,i3-7300T,Discontinued,Q1'17,2,4,3.50 GHz,notFound,notFound
Intel® Core™2 Duo Processor SL9400 6M Cache/ 1.86 GHz/ 1066 MHz FSB,SL9400,Discontinued,Q3'08,2,notFound,1.86 GHz,notFound,notFound
Intel® Pentium® Processor G630 3M Cache/ 2.70 GHz,G630,Discontinued,Q3'11,2,2,2.70 GHz,notFound,notFound
Intel® Xeon® Platinum 8368 Processor 57M Cache/ 2.40 GHz,8368,Launched,Q2'21,38,76,2.40 GHz,3.40 GHz,notFound
Intel® Pentium® Processor D1519 6M Cache/ 1.50 GHz,D1519,Launched,Q2'16,4,8,1.50 GHz,2.10 GHz,2.10 GHz
Intel® Xeon® Processor E5-4620 v4 25M Cache/ 2.10 GHz,E5-4620V4,Launched,Q2'16,10,20,2.10 GHz,2.60 GHz,2.60 GHz
Intel® Celeron® Processor 220 512K Cache/ 1.20 GHz/ 533 MHz FSB,220,Discontinued,Q4'07,1,notFound,1.20 GHz,notFound,notFound
Intel® Xeon® D-2123IT Processor 8.25M Cache/ 2.20 GHz,D-2123IT,Launched,Q1'18,4,8,2.20 GHz,3.00 GHz,notFound
Intel® Xeon® Processor E3-1535M v6 8M Cache/ 3.10 GHz,E3-1535MV6,Launched,Q1'17,4,8,3.10 GHz,4.20 GHz,4.20 GHz
Intel® Core™ i3-4158U Processor 3M Cache/ 2.00 GHz,i3-4158U,Discontinued,Q3'13,2,4,2.00 GHz,notFound,notFound
Intel® Core™ i7-3667U Processor 4M Cache/ up to 3.20 GHz,i7-3667U,Discontinued,Q2'12,2,4,2.00 GHz,3.20 GHz,3.20 GHz
Intel® Celeron® Processor G530 2M Cache/ 2.40 GHz,G530,Discontinued,Q3'11,2,2,2.40 GHz,notFound,notFound
Intel® Core™ i7-960 Processor 8M Cache/ 3.20 GHz/ 4.80 GT/s Intel® QPI,i7-960,Discontinued,Q4'09,4,8,3.20 GHz,3.46 GHz,notFound
Intel® Core™ i5-2435M Processor 3M Cache/ up to 3.00 GHz,i5-2435M,Discontinued,Q4'11,2,4,2.40 GHz,3.00 GHz,3.00 GHz
Intel® Celeron® Processor N2810 1M Cache/ 2.00 GHz,N2810,Discontinued,Q3'13,2,2,2.00 GHz,notFound,notFound
Intel® Xeon® Silver 4310T Processor 15M Cache/ 2.30 GHz,4310T,Launched,Q2'21,10,20,2.30 GHz,3.40 GHz,notFound
Intel® Pentium® M Processor 760 2M Cache/ 2.00A GHz/ 533 MHz FSB,760,Discontinued,Q2'04,1,notFound,2.00 GHz,notFound,notFound
Intel® Core™ i5-3450S Processor 6M Cache/ up to 3.50 GHz,i5-3450S,Discontinued,Q2'12,4,4,2.80 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® Processor EC3539 8M Cache/ 2.13 GHz,EC3539,Discontinued,Q1'10,4,4,2.13 GHz,notFound,notFound
Intel® Xeon® Processor E5-1650 v2 12M Cache/ 3.50 GHz,E5-1650V2,Discontinued,Q3'13,6,12,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Itanium® Processor 9720 20M Cache/ 1.73 GHz,9720,Launched,Q2'17,4,8,1.73 GHz,notFound,notFound
Intel® Xeon® Silver 4310 Processor 18M Cache/ 2.10 GHz,4310,Launched,Q2'21,12,24,2.10 GHz,3.30 GHz,notFound
Intel® Xeon® Processor E5-4650L 20M Cache/ 2.60 GHz/ 8.00 GT/s Intel® QPI,E5-4650L,Discontinued,Q2'12,8,16,2.60 GHz,3.10 GHz,3.10 GHz
Intel® Core™ i7-12800HE Processor 24M Cache/ up to 4.60 GHz,i7-12800HE,Launched,Q1'22,14,20,notFound,4.60 GHz,notFound
Intel® Xeon® E-2374G Processor 8M Cache/ 3.70 GHz,E-2374G,Launched,Q3'21,4,8,3.70 GHz,5.00 GHz,5.00 GHz
Intel® Core™ i5-4690 Processor 6M Cache/ up to 3.90 GHz,i5-4690,Discontinued,Q2'14,4,4,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i5-12600 Processor 18M Cache/ up to 4.80 GHz,i5-12600,Launched,Q1'22,6,12,notFound,4.80 GHz,notFound
Intel® Xeon® W-11555MRE Processor 12M Cache/ up to 4.50 GHz,W-11555MRE,Launched,Q3'21,6,12,notFound,4.50 GHz,notFound
Intel® Core™ i7-4770 Processor 8M Cache/ up to 3.90 GHz,i7-4770,Discontinued,Q2'13,4,8,3.40 GHz,3.90 GHz,3.90 GHz
Intel® Celeron® D Processor 315 256K Cache/ 2.26 GHz/ 533 MHz FSB,315,Discontinued,Q3'04,1,notFound,2.26 GHz,notFound,notFound
Intel Atom® Processor E665CT 512K Cache/ 1.3 GHz,E665CT,Discontinued,Q4'10,1,2,1.30 GHz,notFound,notFound
Intel® Core™ i3-6100E Processor 3M Cache/ 2.70 GHz,i3-6100E,Launched,Q4'15,2,4,2.70 GHz,notFound,notFound
Intel® Core™ i5-4300U Processor 3M Cache/ up to 2.90 GHz,i5-4300U,Launched,Q3'13,2,4,1.90 GHz,2.90 GHz,2.90 GHz
Intel® Xeon® Processor D-1527 6M Cache/ 2.20 GHz,D-1527,Launched,Q4'15,4,8,2.20 GHz,2.70 GHz,2.70 GHz
Intel® Xeon® Processor E5-2687W v3 25M Cache/ 3.10 GHz,E5-2687WV3,Discontinued,Q3'14,10,20,3.10 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® Processor E7-8867 v3 45M Cache/ 2.50 GHz,E7-8867V3,Launched,Q2'15,16,32,2.50 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i3-390M Processor 3M Cache/ 2.66 GHz,i3-390M,Discontinued,Q1'11,2,4,2.66 GHz,notFound,notFound
Intel® Pentium® Processor J2900 2M Cache/ up to 2.67 GHz,J2900,Discontinued,Q4'13,4,4,2.41 GHz,notFound,notFound
Intel Atom® x3-C3445 Processor 1M Cache/ up to 1.40 GHz,x3-C3445,Announced,Q1'15,4,notFound,1.20 GHz,notFound,notFound
Intel® Core™ i7-4770T Processor 8M Cache/ up to 3.70 GHz,i7-4770T,Discontinued,Q2'13,4,8,2.50 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i5-4460 Processor 6M Cache/ up to 3.40 GHz,i5-4460,Discontinued,Q2'14,4,4,3.20 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i3-11100HE Processor 8M Cache/ up to 4.40 GHz,i3-11100HE,Launched,Q3'21,4,8,notFound,4.40 GHz,notFound
Intel® Xeon® W-1390 Processor 16M Cache/ up to 5.20 GHz,W-1390,Launched,Q2'21,8,16,2.80 GHz,5.20 GHz,5.00 GHz
Intel® Xeon® Processor E7-4880 v2 37.5M Cache/ 2.50 GHz,E7-4880V2,Discontinued,Q1'14,15,30,2.50 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Silver 4316 Processor 30M Cache/ 2.30 GHz,4316,Launched,Q2'21,20,40,2.30 GHz,3.40 GHz,notFound
Intel® Xeon® Processor E5-1650 12M Cache/ 3.20 GHz/ 0.0 GT/s Intel® QPI,E5-1650,Discontinued,Q1'12,6,12,3.20 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i5-3475S Processor 6M Cache/ up to 3.60 GHz,i5-3475S,Discontinued,Q2'12,4,4,2.90 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® Processor LC3528 4M Cache/ 1.73 GHz,LC3528,Discontinued,Q1'10,2,4,1.73 GHz,1.87 GHz,notFound
Intel® Xeon® Processor E5-2609 v2 10M Cache/ 2.50 GHz,E5-2609V2,Discontinued,Q3'13,4,4,2.50 GHz,2.50 GHz,notFound
Intel® Xeon® Gold 5320T Processor 30M Cache/ 2.30 GHz,5320T,Launched,Q2'21,20,40,2.30 GHz,3.50 GHz,notFound
Intel® Pentium® M Processor 745A 2M Cache/ 1.80 GHz/ 400 MHz FSB,745A,Discontinued,Q2'04,1,notFound,1.80 GHz,notFound,notFound
Intel® Xeon® Processor E3-1270 v2 8M Cache/ 3.50 GHz,E3-1270V2,Discontinued,Q2'12,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Celeron® Processor N2805 1M Cache/ 1.46 GHz,N2805,Discontinued,Q3'13,2,2,1.46 GHz,notFound,notFound
Intel® Xeon® Processor X3370 12M Cache/ 3.00 GHz/ 1333 MHz FSB,X3370,Discontinued,Q3'08,4,notFound,3.00 GHz,notFound,notFound
Intel® Core™ i9-12900H Processor 24M Cache/ up to 5.00 GHz,i9-12900H,Launched,Q1'22,14,20,notFound,notFound,notFound
Intel Atom® Processor Z3736F 2M Cache/ up to 2.16 GHz,Z3736F,Discontinued,Q2'14,4,notFound,1.33 GHz,notFound,notFound
Intel® Xeon® W-2225 Processor 8.25M Cache/ 4.10 GHz,W-2225,Launched,Q4'19,4,8,4.10 GHz,4.60 GHz,notFound
Intel® Core™ i5-480M Processor 3M Cache/ 2.66 GHz,i5-480M,Discontinued,Q1'11,2,4,2.66 GHz,2.93 GHz,notFound
Intel® Xeon® E-2334 Processor 8M Cache/ 3.40 GHz,E-2334,Launched,Q3'21,4,8,3.40 GHz,4.80 GHz,4.80 GHz
Intel® Xeon® Processor E5-2643 v4 20M Cache/ 3.40 GHz,E5-2643V4,Launched,Q1'16,6,12,3.40 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® Processor E7-8891 v3 45M Cache/ 2.80 GHz,E7-8891V3,Launched,Q2'15,10,20,2.80 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i5-12400F Processor 18M Cache/ up to 4.40 GHz,i5-12400F,Launched,Q1'22,6,12,notFound,4.40 GHz,notFound
Intel® Core™ i5-6267U Processor 4M Cache/ up to 3.30 GHz,i5-6267U,Launched,Q3'15,2,4,2.90 GHz,3.30 GHz,3.30 GHz
Intel® Pentium® Gold G5420T Processor 4M Cache/ 3.20 GHz,G5420T,Launched,Q2'19,2,4,3.20 GHz,notFound,notFound
Intel® Core™ M-5Y71 Processor 4M Cache/ up to 2.90 GHz,5Y71,Discontinued,Q4'14,2,4,1.20 GHz,2.90 GHz,2.90 GHz
Intel® Xeon® Gold 6242R Processor 35.75M Cache/ 3.10 GHz,6242R,Launched,Q1'20,20,40,3.10 GHz,4.10 GHz,notFound
Intel® Celeron® Processor 857 2M Cache/ 1.20 GHz,857,Discontinued,Q3'11,2,2,1.20 GHz,notFound,notFound
Intel® Core™ i7-11700T Processor 16M Cache/ up to 4.60 GHz,i7-11700T,Launched,Q1'21,8,16,1.40 GHz,4.60 GHz,4.50 GHz
Intel® Celeron® Processor J1800 1M Cache/ up to 2.58 GHz,J1800,Launched,Q4'13,2,2,2.41 GHz,notFound,notFound
Intel® Xeon® E-2278GE Processor 16M Cache/ 3.30 GHz,E-2278GE,Launched,Q2'19,8,16,3.30 GHz,4.70 GHz,4.70 GHz
Intel® Xeon® Processor E5-2623 v4 10M Cache/ 2.60 GHz,E5-2623V4,Launched,Q1'16,4,8,2.60 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i7-1195G7 Processor 12M Cache/ up to 5.00 GHz/ with IPU,i7-1195G7,Launched,Q2'21,4,8,notFound,5.00 GHz,notFound
Intel® Xeon® Processor E5520 8M Cache/ 2.26 GHz/ 5.86 GT/s Intel® QPI,E5520,Discontinued,Q1'09,4,8,2.26 GHz,2.53 GHz,notFound
Intel® Core™ i7-3770K Processor 8M Cache/ up to 3.90 GHz,i7-3770K,Discontinued,Q2'12,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Celeron® Processor 3755U 2M Cache/ 1.70 GHz,3755U,Discontinued,Q1'15,2,2,1.70 GHz,notFound,notFound
Intel® Core™ i7-3610QE Processor 6M Cache/ up to 3.30 GHz,i7-3610QE,Launched,Q2'12,4,8,2.30 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® W-11155MRE Processor 8M Cache/ up to 4.40 GHz,W-11155MRE,Launched,Q3'21,4,8,notFound,4.40 GHz,notFound
Intel® Xeon® Processor E5-4650 v3 30M Cache/ 2.10 GHz,E5-4650V3,Discontinued,Q2'15,12,24,2.10 GHz,2.80 GHz,2.80 GHz
Intel® Xeon® Gold 5318S Processor 36M Cache/ 2.10 GHz,5318S,Launched,Q2'21,24,48,2.10 GHz,3.40 GHz,notFound
Intel® Celeron® Processor J3060 2M Cache/ up to 2.48 GHz,J3060,Launched,Q1'16,2,2,1.60 GHz,notFound,notFound
Intel® Core™ i5-12450H Processor 12M Cache/ up to 4.40 GHz,i5-12450H,Launched,Q1'22,8,12,notFound,notFound,notFound
Intel® Xeon® Processor E5-4617 15M Cache/ 2.90 GHz/ 7.20 GT/s Intel® QPI,E5-4617,Discontinued,Q2'12,6,6,2.90 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i5-3320M Processor 3M Cache/ up to 3.30 GHz,i5-3320M,Discontinued,Q2'12,2,4,2.60 GHz,3.30 GHz,3.30 GHz
Intel® Core™2 Duo Processor L7700 4M Cache/ 1.80 GHz/ 800 MHz FSB,L7700,Discontinued,Q3'07,2,notFound,1.80 GHz,notFound,notFound
Intel® Xeon® Processor E3-1505L v5 8M Cache/ 2.00 GHz,E3-1505LV5,Launched,Q4'15,4,8,2.00 GHz,2.80 GHz,2.80 GHz
Intel® Core™ i7-3770S Processor 8M Cache/ up to 3.90 GHz,i7-3770S,Discontinued,Q2'12,4,8,3.10 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i3-2100 Processor 3M Cache/ 3.10 GHz,i3-2100,Discontinued,Q1'11,2,4,3.10 GHz,notFound,notFound
Intel® Xeon® Processor E5-2643 v3 20M Cache/ 3.40 GHz,E5-2643V3,Discontinued,Q3'14,6,12,3.40 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® Processor E7-8893 v3 45M Cache/ 3.20 GHz,E7-8893V3,Launched,Q2'15,4,8,3.20 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® D-1627 Processor 6M Cache/ 2.90GHz,D-1627,Launched,Q2'19,4,8,2.90 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i7-4650U Processor 4M Cache/ up to 3.30 GHz,i7-4650U,Launched,Q3'13,2,4,1.70 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i5-12600K Processor 20M Cache/ up to 4.90 GHz,i5-12600K,Launched,Q4'21,10,16,notFound,4.90 GHz,notFound
Intel® Core™ i9-11900T Processor 16M Cache/ up to 4.90 GHz,i9-11900T,Launched,Q1'21,8,16,1.50 GHz,4.90 GHz,4.80 GHz
Intel® Core™ i7-9850HL Processor 9M Cache/ up to 4.10 GHz,i7-9850HL,Launched,Q2'19,6,12,1.90 GHz,4.10 GHz,4.10 GHz
Intel® Xeon® Processor E5-1630 v4 10M Cache/ 3.70 GHz,E5-1630V4,Launched,Q2'16,4,8,3.70 GHz,4.00 GHz,notFound
Intel® Core™ i3-9320 Processor 8M Cache/ up to 4.40 GHz,i3-9320,Launched,Q2'19,4,4,3.70 GHz,4.40 GHz,4.40 GHz
Intel® Core™ i7-3720QM Processor 6M Cache/ up to 3.60 GHz,i7-3720QM,Discontinued,Q2'12,4,8,2.60 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® Processor E5-2620 v2 15M Cache/ 2.10 GHz,E5-2620V2,Discontinued,Q3'13,6,12,2.10 GHz,2.60 GHz,2.60 GHz
Intel® Xeon® Processor E3-1245 v2 8M Cache/ 3.40 GHz,E3-1245V2,Discontinued,Q2'12,4,8,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® W-1390T Processor 16M Cache/ up to 4.90 GHz,W-1390T,Launched,Q2'21,8,16,1.50 GHz,4.90 GHz,4.80 GHz
Intel® Core™ i5-1030NG7 Processor 6M Cache/ up to 3.50 GHz,i5-1030NG7,Launched,Q2'20,4,8,1.10 GHz,3.50 GHz,notFound
Intel® Celeron® Processor J3160 2M Cache/ up to 2.24 GHz,J3160,Launched,Q1'16,4,4,1.60 GHz,notFound,notFound
Intel® Core™ i3-12100E Processor 12M Cache/ up to 4.20 GHz,i3-12100E,Launched,Q1'22,4,8,notFound,4.20 GHz,notFound
Intel® Core™ i3-6006U Processor 3M Cache/ 2.00 GHz,i3-6006U,Discontinued,Q4'16,2,4,2.00 GHz,notFound,notFound
Intel® Xeon® Processor E5-4667 v3 40M Cache/ 2.00 GHz,E5-4667V3,Discontinued,Q2'15,16,32,2.00 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i5-12500T Processor 18M Cache/ up to 4.40 GHz,i5-12500T,Launched,Q1'22,6,12,notFound,4.40 GHz,notFound
Intel® Core™ i5-2415M Processor 3M Cache/ up to 2.90 GHz,i5-2415M,Launched,Q1'11,2,4,2.30 GHz,2.90 GHz,2.90 GHz
Intel Atom® Processor Z510 512K Cache/ 1.10 GHz/ 400 MHz FSB,Z510,Discontinued,Q2'08,1,notFound,1.10 GHz,notFound,notFound
Intel® Xeon® W-1290 Processor 20M Cache/ 3.20 GHz,W-1290,Launched,Q2'20,10,20,3.20 GHz,5.20 GHz,5.00 GHz
Intel® Core™ i5-8600K Processor 9M Cache/ up to 4.30 GHz,i5-8600K,Discontinued,Q4'17,6,6,3.60 GHz,4.30 GHz,4.30 GHz
Intel® Core™ i5-7300HQ Processor 6M Cache/ up to 3.50 GHz,i5-7300HQ,Launched,Q1'17,4,4,2.50 GHz,3.50 GHz,3.50 GHz
Intel Atom® x5-E8000 Processor 2M Cache/ up to 2.00 GHz,E8000,Launched,Q1'16,4,4,1.04 GHz,notFound,notFound
Intel® Xeon® Processor E5-2628L v2 20M Cache/ 1.90 GHz,E5-2628LV2,Launched,Q3'13,8,16,1.90 GHz,2.40 GHz,2.40 GHz
Intel® Xeon® Processor E5-2697 v4 45M Cache/ 2.30 GHz,E5-2697V4,Launched,Q1'16,18,36,2.30 GHz,3.60 GHz,3.60 GHz
Intel Atom® x3-C3235RK Processor 1M Cache/ up to 1.20 GHz,x3-C3235RK,Launched,Q4'15,4,notFound,notFound,notFound,notFound
Intel® Core™ i7-7820X X-series Processor 11M Cache/ up to 4.30 GHz,i7-7820X,Discontinued,Q2'17,8,16,3.60 GHz,4.30 GHz,notFound
Intel® Celeron® M Processor ULV 373 512K Cache/ 1.00 GHz/ 400 MHz FSB,373,Discontinued,Q2'04,1,notFound,1.00 GHz,notFound,notFound
Intel® Xeon® Processor E3-1240 v6 8M Cache/ 3.70 GHz,E3-1240V6,Launched,Q1'17,4,8,3.70 GHz,4.10 GHz,4.10 GHz
Intel® Core™ i3-4010Y Processor 3M Cache/ 1.30 GHz,i3-4010Y,Discontinued,Q3'13,2,4,1.30 GHz,notFound,notFound
Intel® Core™2 Solo Processor ULV SU3500 3M Cache/ 1.40 GHz/ 800 MHz FSB,SU3500,Discontinued,Q2'09,1,notFound,1.40 GHz,notFound,notFound
Intel® Core™ i7-2860QM Processor 8M Cache/ up to 3.60 GHz,i7-2860QM,Discontinued,Q4'11,4,8,2.50 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® Platinum 8352V Processor 54M Cache/ 2.10 GHz,8352V,Launched,Q2'21,36,72,2.10 GHz,3.50 GHz,notFound
Intel® Pentium® Processor G622 3M Cache/ 2.60 GHz,G622,Discontinued,Q2'11,2,2,2.60 GHz,notFound,notFound
Intel® Xeon® Processor E7-8870 v4 50M Cache/ 2.10 GHz,E7-8870V4,Launched,Q2'16,20,40,2.10 GHz,3.00 GHz,3.00 GHz
Intel® Pentium® Processor D1508 3M Cache/ 2.20 GHz,D1508,Launched,Q4'15,2,4,2.20 GHz,2.60 GHz,2.60 GHz
Intel® Xeon® Processor E5-2650L v4 35M Cache/ 1.70 GHz,E5-2650LV4,Launched,Q1'16,14,28,1.70 GHz,2.50 GHz,2.50 GHz
Intel® Xeon® Processor X5260 6M Cache/ 3.33 GHz/ 1333 MHz FSB,X5260,Discontinued,Q4'07,2,notFound,3.33 GHz,notFound,notFound
Intel® Core™ i5-760 Processor 8M Cache/ 2.80 GHz,i5-760,Discontinued,Q3'10,4,4,2.80 GHz,3.33 GHz,notFound
Intel® Pentium® Processor D1509 3M Cache/ 1.50 GHz,D1509,Launched,Q4'15,2,2,1.50 GHz,notFound,notFound
Intel® Celeron® Processor G3950 2M Cache/ 3.00 GHz,G3950,Discontinued,Q1'17,2,2,3.00 GHz,notFound,notFound
Intel® Xeon® Processor E5-2660 v3 25M Cache/ 2.60 GHz,E5-2660V3,Discontinued,Q3'14,10,20,2.60 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® Silver 4210R Processor 13.75M Cache/ 2.40 GHz,4210R,Launched,Q1'20,10,20,2.40 GHz,3.20 GHz,notFound
Intel® Celeron® Processor P4600 2M Cache/ 2.00 GHz,P4600,Discontinued,Q3'10,2,2,2.00 GHz,notFound,notFound
Intel® Xeon® Processor E7-4850 v4 40M Cache/ 2.10 GHz,E7-4850V4,Launched,Q2'16,16,32,2.10 GHz,2.80 GHz,2.80 GHz
Intel® Core™2 Duo Processor E4500 2M Cache/ 2.20 GHz/ 800 MHz FSB,E4500,Discontinued,Q3'07,2,notFound,2.20 GHz,notFound,notFound
Intel® Pentium® Processor G632 3M Cache/ 2.70 GHz,G632,Discontinued,Q3'11,2,2,2.70 GHz,notFound,notFound
Intel® Celeron® M Processor ULV 423 1M Cache/ 1.06 GHz/ 533 MHz FSB,423,Discontinued,Q1'06,1,notFound,1.06 GHz,notFound,notFound
Intel Atom® Processor N450 512K Cache/ 1.66 GHz,N450,Discontinued,Q1'10,1,2,1.66 GHz,notFound,notFound
Intel® Core™2 Duo Processor P7570 3M Cache/ 2.26 GHz/ 1066 MHz FSB,P7570,Discontinued,Q3'09,2,notFound,2.26 GHz,notFound,notFound
Intel® Xeon® Processor 3065 4M Cache/ 2.33 GHz/ 1333 MHz FSB,3065,Discontinued,Q4'07,2,notFound,2.33 GHz,notFound,notFound
Intel® Xeon® Processor E5-2658 v2 25M Cache/ 2.40 GHz,E5-2658V2,Launched,Q3'13,10,20,2.40 GHz,3.00 GHz,3.00 GHz
Intel® Pentium® Processor G3320TE 3M Cache/ 2.30 GHz,G3320TE,Launched,Q3'13,2,2,2.30 GHz,notFound,notFound
Intel® Core™2 Extreme Processor X7800 4M Cache/ 2.60 GHz/ 800 MHz FSB,X7800,Discontinued,Q3'07,2,notFound,2.60 GHz,notFound,notFound
Intel® Xeon® Processor X3320 6M Cache/ 2.50 GHz/ 1333 MHz FSB,X3320,Discontinued,Q1'08,4,notFound,2.50 GHz,notFound,notFound
Intel® Pentium® Processor N4200 2M Cache/ up to 2.50 GHz,N4200,Launched,Q3'16,4,4,1.10 GHz,notFound,notFound
Intel Atom® Processor Z3735D 2M Cache/ up to 1.83 GHz,Z3735D,Discontinued,Q1'14,4,notFound,1.33 GHz,notFound,notFound
Intel® Core™ i9-10920X X-series Processor 19.25M Cache/ 3.50 GHz,i9-10920X,Launched,Q4'19,12,24,3.50 GHz,4.60 GHz,notFound
Intel® Core™ i7-9700KF Processor 12M Cache/ up to 4.90 GHz,i7-9700KF,Launched,Q1'19,8,8,3.60 GHz,4.90 GHz,4.90 GHz
Intel Atom® Processor Z3785 2M Cache/ up to 2.41 GHz,Z3785,Discontinued,Q2'14,4,notFound,1.49 GHz,notFound,notFound
Intel® Core™ i7-2960XM Processor Extreme Edition 8M Cache/ up to 3.70 GHz,i7-2960XM,Discontinued,Q4'11,4,8,2.70 GHz,3.70 GHz,3.70 GHz
Intel® Celeron® Processor G3930T 2M Cache/ 2.70 GHz,G3930T,Discontinued,Q1'17,2,2,2.70 GHz,notFound,notFound
Intel Atom® Processor Z510PT 512K Cache/ 1.10 GHz/ 400 MHz FSB,Z510PT,Discontinued,Q2'08,1,notFound,1.10 GHz,notFound,notFound
Intel® Celeron® Processor 807 1.5M Cache/ 1.50 GHz,807,Discontinued,Q2'12,1,2,1.50 GHz,notFound,notFound
Intel® Xeon® Processor E5-2448L 20M/ 1.8 GHz/ 8.0 GT/s Intel® QPI,E5-2448L,Launched,Q2'12,8,16,1.80 GHz,2.10 GHz,2.10 GHz
Intel® Celeron® Processor G3930TE 2M Cache/ 2.70 GHz,G3930TE,Launched,Q2'17,2,2,2.70 GHz,notFound,notFound
Intel® Core™2 Duo Processor SL9300 6M Cache/ 1.60 GHz/ 1066 MHz FSB,SL9300,Discontinued,Q3'08,2,notFound,1.60 GHz,notFound,notFound
Intel® Celeron® Processor B830 2M Cache/ 1.80 GHz,B830,Discontinued,Q3'12,2,2,1.80 GHz,notFound,notFound
Intel® Core™ i3-7300 Processor 4M Cache/ 4.00 GHz,i3-7300,Discontinued,Q1'17,2,4,4.00 GHz,notFound,notFound
Intel® Xeon® W-1270 Processor 16M Cache/ 3.40 GHz,W-1270,Launched,Q2'20,8,16,3.40 GHz,5.00 GHz,4.90 GHz
Intel® Xeon® Processor E7-4820 18M Cache/ 2.00 GHz/ 5.86 GT/s Intel® QPI,E7-4820,Discontinued,Q2'11,8,16,2.00 GHz,2.27 GHz,notFound
Intel® Pentium® Processor G4620 3M Cache/ 3.70 GHz,G4620,Discontinued,Q1'17,2,4,3.70 GHz,notFound,notFound
Intel® Xeon® W-2123 Processor 8.25M Cache/ 3.60 GHz,W-2123,Launched,Q3'17,4,8,3.60 GHz,3.90 GHz,notFound
Intel Atom® Processor Z3580 2M Cache/ up to 2.33 GHz,Z3580,Discontinued,Q2'14,4,notFound,notFound,notFound,notFound
Intel® Xeon® W-2265 Processor 19.25M Cache/ 3.50 GHz,W-2265,Launched,Q4'19,12,24,3.50 GHz,4.60 GHz,notFound
Intel® Xeon® Processor E5-2403 v2 10M Cache/ 1.80 GHz,E5-2403V2,Discontinued,Q1'14,4,4,1.80 GHz,1.80 GHz,notFound
Intel Atom® Processor Z3735G 2M Cache/ up to 1.83 GHz,Z3735G,Discontinued,Q1'14,4,notFound,1.33 GHz,notFound,notFound
Intel® Xeon® Processor E5-4655 v4 30M Cache/ 2.50 GHz,E5-4655V4,Launched,Q2'16,8,16,2.50 GHz,3.20 GHz,3.20 GHz
Intel® Itanium® Processor 9015 12M Cache/ 1.40 GHz/ 400 MHz FSB,9015,Discontinued,Q1'07,2,notFound,1.40 GHz,notFound,notFound
Intel Atom® Processor Z540 512K Cache/ 1.86 GHz/ 533 MHz FSB,Z540,Discontinued,Q2'08,1,notFound,1.86 GHz,notFound,notFound
Intel® Xeon® Processor E3-1501M v6 6M Cache/ up to 3.60 GHz,E3-1501MV6,Launched,Q2'17,4,4,2.90 GHz,3.60 GHz,3.60 GHz
Intel® Celeron® Processor 585 1M Cache/ 2.16 GHz/ 667 MHz FSB,585,Discontinued,Q3'08,1,notFound,2.16 GHz,notFound,notFound
Intel® Core™2 Duo Processor E8200 6M Cache/ 2.66 GHz/ 1333 MHz FSB,E8200,Discontinued,Q1'08,2,notFound,2.66 GHz,notFound,notFound
Intel® Core™ i7-870S Processor 8M Cache/ 2.66 GHz,i7-870S,Discontinued,Q2'10,4,8,2.66 GHz,3.60 GHz,notFound
Intel® Celeron® M Processor 440 1M Cache/ 1.86 GHz/ 533 MHz FSB,440,Discontinued,Q1'06,1,notFound,1.86 GHz,notFound,notFound
Intel® Celeron® Processor N4000 4M Cache/ up to 2.60 GHz,N4000,Launched,Q4'17,2,2,1.10 GHz,notFound,notFound
Intel® Core™ i7-8086K Processor 12M Cache/ up to 5.00 GHz,i7-8086K,Launched,Q2'18,6,12,4.00 GHz,5.00 GHz,5.00 GHz
Intel® Pentium® Gold 6405U Processor 2M Cache/ 2.40 GHz,6405U,Launched,Q4'19,2,4,2.40 GHz,notFound,notFound
Intel® Core™ i5-2515E Processor 3M Cache/ up to 3.10 GHz,i5-2515E,Discontinued,Q1'11,2,4,2.50 GHz,3.10 GHz,3.10 GHz
Intel Atom® Processor Z3775 2M Cache/ up to 2.39 GHz,Z3775,Discontinued,Q1'14,4,notFound,1.46 GHz,notFound,notFound
Intel® Pentium® D Processor 925 4M Cache/ 3.00 GHz/ 800 MHz FSB,925,Discontinued,Q3'06,2,notFound,3.00 GHz,notFound,notFound
Intel® Xeon® Processor E7310 4M Cache/ 1.60 GHz/ 1066 MHz FSB,E7310,Discontinued,Q3'07,4,notFound,1.60 GHz,notFound,notFound
Intel® Xeon® Gold 6132 Processor 19.25M Cache/ 2.60 GHz,6132,Launched,Q3'17,14,28,2.60 GHz,3.70 GHz,notFound
Intel® Itanium® Processor 9340 20M Cache/ 1.60 GHz/ 4.80 GT/s Intel® QPI,9340,Discontinued,Q1'10,4,8,1.60 GHz,1.73 GHz,notFound
Intel® Xeon® Processor E5-4610 v4 25M Cache/ 1.80 GHz,E5-4610V4,Launched,Q2'16,10,20,1.80 GHz,1.80 GHz,notFound
Intel® Xeon® Processor E7340 8M Cache/ 2.40 GHz/ 1066 MHz FSB,E7340,Discontinued,Q3'07,4,notFound,2.40 GHz,notFound,notFound
Intel® Core™ i5-470UM Processor 3M Cache/ 1.33 GHz,i5-470UM,Discontinued,Q4'10,2,4,1.33 GHz,1.86 GHz,notFound
Intel® Pentium® Processor G850 3M Cache/ 2.90 GHz,G850,Discontinued,Q2'11,2,2,2.90 GHz,notFound,notFound
Intel® Celeron® Processor E1600 512K Cache/ 2.40 GHz/ 800 MHz FSB,E1600,Discontinued,Q2'09,2,notFound,2.40 GHz,notFound,notFound
Intel® Core™ i3-10305T Processor 8M Cache/ up to 4.00 GHz,i3-10305T,Launched,Q1'21,4,8,3.00 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i3-4100M Processor 3M Cache/ 2.50 GHz,i3-4100M,Discontinued,Q4'13,2,4,2.50 GHz,notFound,notFound
Intel® Core™ i9-11950H Processor 24M Cache/ up to 4.90 GHz,i9-11950H,Launched,Q2'21,8,16,notFound,5.00 GHz,notFound
Intel® Xeon® Bronze 3104 Processor 8.25M Cache/ 1.70 GHz,3104,Launched,Q3'17,6,6,1.70 GHz,notFound,notFound
Intel® Celeron® J4005 Processor 4M Cache/ up to 2.70 GHz,J4005,Launched,Q4'17,2,2,2.00 GHz,notFound,notFound
Intel® Celeron® M Processor 520 1M Cache/ 1.60 GHz/ 533 MHz FSB,520,Discontinued,Q1'07,1,notFound,1.60 GHz,notFound,notFound
Intel® Celeron® Processor 1020M 2M Cache/ 2.10 GHz,1020M,Discontinued,Q1'13,2,2,2.10 GHz,notFound,notFound
Intel® Core™ i7-3840QM Processor 8M Cache/ up to 3.80 GHz,i7-3840QM,Discontinued,Q3'12,4,8,2.80 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i7+8700 Processor (12M Cache/ up to 4.60 GHz) includes Intel® Optane™ Memory 16GB,i7-8700,Launched,Q2'18,6,12,3.20 GHz,4.60 GHz,4.60 GHz
Intel® Core™ i9-10900T Processor 20M Cache/ up to 4.60 GHz,i9-10900T,Launched,Q2'20,10,20,1.90 GHz,4.60 GHz,4.50 GHz
Intel® Itanium® Processor 9310 10M Cache/ 1.60 GHz/ 4.80 GT/s Intel® QPI,9310,Discontinued,Q1'10,2,4,1.60 GHz,notFound,notFound
Intel® Pentium® Processor 2127U 2M Cache/ 1.90 GHz,2127U,Discontinued,Q3'13,2,2,1.90 GHz,notFound,notFound
Intel® Pentium® Processor G3460 3M Cache/ 3.50 GHz,G3460,Discontinued,Q3'14,2,2,3.50 GHz,notFound,notFound
Intel Atom® Processor 330 1M Cache/ 1.60 GHz/ 533 MHz FSB,330,Discontinued,Q3'08,2,notFound,1.60 GHz,notFound,notFound
Intel® Xeon® Processor E5649 12M Cache/ 2.53 GHz/ 5.86 GT/s Intel® QPI,E5649,Discontinued,Q1'11,6,12,2.53 GHz,2.93 GHz,notFound
Intel® Pentium® D Processor 940 4M Cache/ 3.20 GHz/ 800 MHz FSB,940,Discontinued,Q1'06,2,notFound,3.20 GHz,notFound,notFound
Intel® Xeon® Processor E5-2690 v4 35M Cache/ 2.60 GHz,E5-2690V4,Launched,Q1'16,14,28,2.60 GHz,3.50 GHz,3.50 GHz
Intel® Pentium® Processor E2200 1M Cache/ 2.20 GHz/ 800 MHz FSB,E2200,Discontinued,Q4'07,2,notFound,2.20 GHz,notFound,notFound
Intel Atom® Processor E3826 1M Cache/ 1.46 GHz,E3826,Launched,Q4'13,2,2,1.46 GHz,notFound,notFound
Intel® Core™ i5-10505 Processor 12M Cache/ up to 4.60 GHz,i5-10505,Launched,Q1'21,6,12,3.20 GHz,4.60 GHz,4.60 GHz
Intel® Core™ i7-4558U Processor 4M Cache/ up to 3.30 GHz,i7-4558U,Discontinued,Q3'13,2,4,2.80 GHz,3.30 GHz,3.30 GHz
Intel® Pentium® Gold G7400T Processor 6M Cache/ 3.10 GHz,G7400T,Launched,Q1'22,2,4,notFound,notFound,notFound
Intel® Core™ i9-9980HK Processor 16M Cache/ up to 5.00 GHz,i9-9980HK,Launched,Q2'19,8,16,2.40 GHz,5.00 GHz,notFound
Intel® Core™ i9-9980HK Processor 16M Cache/ up to 5.00 GHz,i9-9980HK,Launched,Q2'19,8,16,2.40 GHz,5.00 GHz,notFound
Intel® Xeon® Processor E3-1245 v6 8M Cache/ 3.70 GHz,E3-1245V6,Launched,Q1'17,4,8,3.70 GHz,4.10 GHz,4.10 GHz
Intel® Xeon® D-2142IT Processor 11M Cache/ 1.90 GHz,D-2142IT,Launched,Q1'18,8,16,1.90 GHz,3.00 GHz,notFound
Intel® Core™ i5-8269U Processor 6M Cache/ up to 4.20 GHz,i5-8269U,Launched,Q2'18,4,8,2.60 GHz,4.20 GHz,4.20 GHz
Intel® Xeon® Processor W3690 12M Cache/ 3.46 GHz/ 6.40 GT/s Intel® QPI,W3690,Discontinued,Q1'11,6,12,3.46 GHz,3.73 GHz,notFound
Intel® Xeon® Processor X5570 8M Cache/ 2.93 GHz/ 6.40 GT/s Intel® QPI,X5570,Discontinued,Q1'09,4,8,2.93 GHz,3.33 GHz,notFound
Intel® Core™2 Duo Processor SU9300 3M Cache/ 1.20 GHz/ 800 MHz FSB,SU9300,Discontinued,Q3'08,2,notFound,1.20 GHz,notFound,notFound
Intel® Xeon® Processor LV 5128 4M Cache/ 1.86 GHz/ 1066 MHz FSB,5128,Discontinued,Q2'06,2,notFound,1.86 GHz,notFound,notFound
Intel® Pentium® D Processor 950 4M Cache/ 3.40 GHz/ 800 MHz FSB,950,Discontinued,Q1'06,2,notFound,3.40 GHz,notFound,notFound
Intel® Xeon® W-11955M Processor 24M Cache/ 2.60 GHz,W-11955M,Launched,Q2'21,8,16,notFound,5.00 GHz,notFound
Intel® Core™ i7-6700TE Processor 8M Cache/ up to 3.40 GHz,i7-6700TE,Launched,Q4'15,4,8,2.40 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® Gold 6126T Processor 19.25M Cache/ 2.60 GHz,6126T,Launched,Q3'17,12,24,2.60 GHz,3.70 GHz,notFound
Intel® Celeron® Processor 925 1M Cache/ 2.30 GHz/ 800 MHz FSB,925,Discontinued,Q1'11,1,notFound,2.30 GHz,notFound,notFound
Intel® Celeron® M Processor 370 1M Cache/ 1.50 GHz/ 400 MHz FSB,370,Discontinued,Q2'04,1,notFound,1.50 GHz,notFound,notFound
Intel® Xeon® Processor E3-1230 v6 8M Cache/ 3.50 GHz,E3-1230V6,Launched,Q1'17,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® D-2161I Processor 16.5M Cache/ 2.20 GHz,D-2161I,Launched,Q1'18,12,24,2.20 GHz,3.00 GHz,notFound
Intel® Core™ i5-4200M Processor 3M Cache/ up to 3.10 GHz,i5-4200M,Discontinued,Q4'13,2,4,2.50 GHz,3.10 GHz,3.10 GHz
Intel® Core™ i7-10610U Processor 8M Cache/ up to 4.90 GHz,i7-10610U,Launched,Q2'20,4,8,1.80 GHz,4.90 GHz,notFound
Intel® Core™ i5-10600KF Processor 12M Cache/ up to 4.80 GHz,i5-10600KF,Launched,Q2'20,6,12,4.10 GHz,4.80 GHz,4.80 GHz
Intel® Core™ i3-380UM Processor 3M Cache/ 1.33 GHz,i3-380UM,Discontinued,Q4'10,2,4,1.33 GHz,notFound,notFound
Intel® Celeron® Processor ULV 573 512K Cache/ 1.00 GHz/ 533 MHz FSB,573,Discontinued,Q3'06,1,notFound,1.00 GHz,notFound,notFound
Intel® Pentium® Gold Processor 4415Y 2M Cache/ 1.60 GHz,4415Y,Launched,Q2'17,2,4,1.60 GHz,notFound,notFound
Intel® Core™2 Quad Processor Q9300 6M Cache/ 2.50 GHz/ 1333 MHz FSB,Q9300,Discontinued,Q1'08,4,notFound,2.50 GHz,notFound,notFound
Intel® Core™ i5-750 Processor 8M Cache/ 2.66 GHz,i5-750,Discontinued,Q3'09,4,4,2.66 GHz,3.20 GHz,notFound
Intel® Xeon® Platinum 8168 Processor 33M Cache/ 2.70 GHz,8168,Launched,Q3'17,24,48,2.70 GHz,3.70 GHz,notFound
Intel Atom® x6425E Processor 1.5M Cache/ up to 3.00 GHz,6425E,Launched,Q1'21,4,4,2.00 GHz,notFound,notFound
Intel® Core™2 Quad Processor Q9400S 6M Cache/ 2.66 GHz/ 1333 MHz FSB,Q9400S,Discontinued,Q1'09,4,notFound,2.66 GHz,notFound,notFound
Intel® Xeon® W-1290T Processor 20M Cache/ 1.90 GHz,W-1290T,Launched,Q2'20,10,20,1.90 GHz,4.70 GHz,4.60 GHz
Intel® Quark™ SE C1000 Microcontroller,C1000,Discontinued,Q4'15,1,notFound,32 MHz,notFound,notFound
Intel® Core™ i7-12700K Processor 25M Cache/ up to 5.00 GHz,i7-12700K,Launched,Q4'21,12,20,notFound,5.00 GHz,notFound
Intel® Core™ i3-5005U Processor 3M Cache/ 2.00 GHz,i3-5005U,Launched,Q1'15,2,4,2.00 GHz,notFound,notFound
Intel® Core™ i3-5005U Processor 3M Cache/ 2.00 GHz,i3-5005U,Launched,Q1'15,2,4,2.00 GHz,notFound,notFound
Intel® Core™ i9-9920X X-series Processor 19.25M Cache/ up to 4.50 GHz,i9-9920X,Discontinued,Q4'18,12,24,3.50 GHz,4.40 GHz,notFound
Intel® Xeon® Processor E3-1578L v5 8M Cache/ 2.00 GHz,E3-1578LV5,Launched,Q2'16,4,8,2.00 GHz,3.40 GHz,3.40 GHz
Intel® Celeron® Processor 3965U 2M Cache/ 2.20 GHz,3965U,Launched,Q1'17,2,2,2.20 GHz,notFound,notFound
Intel® Core™ i7-5700EQ Processor 6M Cache/ up to 3.40 GHz,i7-5700EQ,Launched,Q2'15,4,8,2.60 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® Processor E5-4607 v2 15M Cache/ 2.60 GHz,E5-4607V2,Discontinued,Q1'14,6,12,2.60 GHz,2.60 GHz,notFound
Intel® Core™ i7-11700F Processor 16M Cache/ up to 4.90 GHz,i7-11700F,Launched,Q1'21,8,16,2.50 GHz,4.90 GHz,4.80 GHz
Intel® Xeon® Processor E3-1220 v2 8M Cache/ 3.10 GHz,E3-1220V2,Discontinued,Q2'12,4,4,3.10 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i5-1038NG7 Processor 6M Cache/ up to 3.80 GHz,i5-1038NG7,Launched,Q2'20,4,8,2.00 GHz,3.80 GHz,notFound
Intel® Core™ i7-10700E Processor 16M Cache/ up to 4.50 GHz,i7-10700E,Launched,Q2'20,8,16,2.90 GHz,4.50 GHz,notFound
Intel® Core™ i5-11600 Processor 12M Cache/ up to 4.80 GHz,i5-11600,Launched,Q1'21,6,12,2.80 GHz,4.80 GHz,4.80 GHz
Intel® Xeon® Processor E5-2440 15M Cache/ 2.40 GHz/ 7.20 GT/s Intel® QPI,E5-2440,Discontinued,Q2'12,6,12,2.40 GHz,2.90 GHz,notFound
Intel® Core™ i3-2367M Processor 3M Cache/ 1.40 GHz,i3-2367M,Discontinued,Q4'11,2,4,1.40 GHz,notFound,notFound
Intel® Celeron® D Processor 326 256K Cache/ 2.53 GHz/ 533 MHz FSB,326,Discontinued,Q2'04,1,notFound,2.53 GHz,notFound,notFound
Intel® Core™ i7-9700TE Processor 12M Cache/ up to 3.80 GHz,i7-9700TE,Launched,Q2'19,8,8,1.80 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i9-9900 Processor 16M Cache/ up to 5.00 GHz,i9-9900,Launched,Q2'19,8,16,3.10 GHz,5.00 GHz,notFound
Intel® Celeron® D Processor 352 512K Cache/ 3.20 GHz/ 533 MHz FSB,352,Discontinued,Q2'06,1,notFound,3.20 GHz,notFound,notFound
Intel® Pentium® Processor U5400 3M Cache/ 1.20 GHz,U5400,Discontinued,Q2'10,2,2,1.20 GHz,notFound,notFound
Intel® Xeon® Gold 6230R Processor 35.75M Cache/ 2.10 GHz,6230R,Launched,Q1'20,26,52,2.10 GHz,4.00 GHz,notFound
Intel® Core™ M-5Y31 Processor 4M Cache/ up to 2.40 GHz,5Y31,Discontinued,Q4'14,2,4,900 MHz,2.40 GHz,2.40 GHz
Intel Atom® x6427FE Processor 1.5M Cache/ 1.90 GHz,6427FE,Launched,Q1'21,4,4,1.90 GHz,notFound,notFound
Intel® Core™ i3-2350M Processor 3M Cache/ 2.30 GHz,i3-2350M,Discontinued,Q4'11,2,4,2.30 GHz,notFound,notFound
Intel® Xeon® Processor X5492 12M Cache/ 3.40 GHz/ 1600 MHz FSB,X5492,Discontinued,Q3'08,4,notFound,3.40 GHz,notFound,notFound
Intel® Xeon® Platinum 8164 Processor 35.75M Cache/ 2.00 GHz,8164,Launched,Q3'17,26,52,2.00 GHz,3.70 GHz,notFound
Intel® Celeron® D Processor 335 256K Cache/ 2.80 GHz/ 533 MHz FSB,335,Discontinued,Q2'04,1,notFound,2.80 GHz,notFound,notFound
Intel® Core™ i7-4900MQ Processor 8M Cache/ up to 3.80 GHz,i7-4900MQ,Discontinued,Q2'13,4,8,2.80 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Processor E5-2403 10M Cache/ 1.80 GHz/ 6.40 GT/s Intel® QPI,E5-2403,Discontinued,Q2'12,4,4,1.80 GHz,notFound,notFound
Intel® Core™ i7-4700EC Processor 8M Cache/ up to 2.70 GHz,i7-4700EC,Launched,Q1'14,4,8,2.70 GHz,notFound,notFound
Intel® Core™2 Quad Processor Q9000 6M Cache/ 2.00 GHz/ 1066 MHz FSB,Q9000,Discontinued,Q1'09,4,notFound,2.00 GHz,notFound,notFound
Intel® Core™ i7-1068NG7 Processor 8M Cache/ up to 4.10 GHz,i7-1068NG7,Launched,Q2'20,4,8,2.30 GHz,4.10 GHz,notFound
Intel® Core™ i5-11400T Processor 12M Cache/ up to 3.70 GHz,i5-11400T,Launched,Q1'21,6,12,1.30 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® Processor E3-1225 v2 8M Cache/ 3.20 GHz,E3-1225V2,Launched,Q2'12,4,4,3.20 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i5-9600 Processor 9M Cache/ up to 4.60 GHz,i5-9600,Launched,Q2'19,6,6,3.10 GHz,4.60 GHz,4.60 GHz
Intel® Xeon® Processor E5-4603 v2 10M Cache/ 2.20 GHz,E5-4603V2,Discontinued,Q1'14,4,8,2.20 GHz,2.20 GHz,notFound
Intel® Xeon® Platinum 8380 Processor 60M Cache/ 2.30 GHz,8380,Launched,Q2'21,40,80,2.30 GHz,3.40 GHz,notFound
Intel® Pentium® Processor E2220 1M Cache/ 2.40 GHz/ 800 MHz FSB,E2220,Discontinued,Q1'08,2,notFound,2.40 GHz,notFound,notFound
Intel® Core™ i7-5850EQ Processor 6M Cache/ up to 3.40 GHz,i7-5850EQ,Launched,Q2'15,4,8,2.70 GHz,3.40 GHz,3.40 GHz
Intel Atom® Processor Z3770D 2M Cache/ up to 2.41 GHz,Z3770D,Discontinued,Q3'13,4,notFound,1.50 GHz,notFound,notFound
Intel® Core™ i7-10700TE Processor 16M Cache/ up to 4.50 GHz,i7-10700TE,Launched,Q2'20,8,16,2.00 GHz,4.40 GHz,notFound
Intel® Core™ i7-11700KF Processor 16M Cache/ up to 5.00 GHz,i7-11700KF,Launched,Q1'21,8,16,3.60 GHz,5.00 GHz,4.90 GHz
Intel® Core™ i5-6402P Processor 6M Cache/ up to 3.40 GHz,i5-6402P,Discontinued,Q4'15,4,4,2.80 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® Processor E5-2470 20M Cache/ 2.30 GHz/ 8.00 GT/s Intel® QPI,E5-2470,Discontinued,Q2'12,8,16,2.30 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Processor L3426 8M Cache/ 1.86 GHz,L3426,Discontinued,Q3'09,4,8,1.86 GHz,3.20 GHz,notFound
Intel® Xeon® Processor E5-1650 v4 15M Cache/ 3.60 GHz,E5-1650V4,Launched,Q2'16,6,12,3.60 GHz,4.00 GHz,notFound
Intel® Pentium® Gold Processor 4415U 2M Cache/ 2.30 GHz,4415U,Launched,Q1'17,2,4,2.30 GHz,notFound,notFound
Intel® Quark™ Microcontroller D2000,D2000,Discontinued,Q3'15,1,notFound,32 MHz,notFound,notFound
Intel Atom® Processor P5931B 13.5M Cache/ 2.20 GHz,P5931B,Launched,Q1'20,12,12,2.20 GHz,notFound,notFound
Intel® Core™ i3-4010U Processor 3M Cache/ 1.70 GHz,i3-4010U,Launched,Q3'13,2,4,1.70 GHz,notFound,notFound
Intel® Core™ i3-4010U Processor 3M Cache/ 1.70 GHz,i3-4010U,Launched,Q3'13,2,4,1.70 GHz,notFound,notFound
Intel® Core™ i9-10980HK Processor 16M Cache/ up to 5.30 GHz,i9-10980HK,Launched,Q2'20,8,16,2.40 GHz,5.30 GHz,notFound
Intel® Celeron® D Processor 340 256K Cache/ 2.93 GHz/ 533 MHz FSB,340,Discontinued,Q4'04,1,notFound,2.93 GHz,notFound,notFound
Intel® Core™ i5-2540M Processor 3M Cache/ up to 3.30 GHz,i5-2540M,Discontinued,Q1'11,2,4,2.60 GHz,3.30 GHz,3.30 GHz
Intel® Celeron® Processor E3300 1M Cache/ 2.50 GHz/ 800 MHz FSB,E3300,Discontinued,Q3'09,2,notFound,2.50 GHz,notFound,notFound
Intel® Celeron® Processor J6413 1.5M Cache/ up to 3.00 GHz,J6413,Launched,Q1'21,4,4,1.80 GHz,notFound,notFound
Intel® Celeron® G4900 Processor 2M Cache/ 3.10 GHz,G4900,Launched,Q2'18,2,2,3.10 GHz,notFound,notFound
Intel® Xeon® Processor E3120 6M Cache/ 3.16 GHz/ 1333 MHz FSB,E3120,Discontinued,Q3'08,2,notFound,3.16 GHz,notFound,notFound
Intel® Xeon® Platinum 8368Q Processor 57M Cache/ 2.60 GHz,8368Q,Launched,Q2'21,38,76,2.60 GHz,3.70 GHz,notFound
Intel® Xeon® W-2133 Processor 8.25M Cache/ 3.60 GHz,W-2133,Launched,Q3'17,6,12,3.60 GHz,3.90 GHz,notFound
Intel® Core™ i9-10900TE Processor 20M Cache/ up to 4.60 GHz,i9-10900TE,Launched,Q2'20,10,20,1.80 GHz,4.50 GHz,notFound
Intel® Xeon® Processor E5-1660 v3 20M Cache/ 3.00 GHz,E5-1660V3,Discontinued,Q3'14,8,16,3.00 GHz,3.50 GHz,3.50 GHz
Intel® Celeron® D Processor 335J 256K Cache/ 2.80 GHz/ 533 MHz FSB,335J,Discontinued,Q4'04,1,notFound,2.80 GHz,notFound,notFound
Intel® Core™ i5-3570 Processor 6M Cache/ up to 3.80 GHz,i5-3570,Discontinued,Q2'12,4,4,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Gold 6208U Processor 22M Cache/ 2.90 GHz,6208U,Launched,Q1'20,16,32,2.90 GHz,3.90 GHz,notFound
Intel® Core™ i3-4350 Processor 4M Cache/ 3.60 GHz,i3-4350,Discontinued,Q2'14,2,4,3.60 GHz,notFound,notFound
Intel® Xeon® D-1602 Processor 3M Cache/ 2.50GHz,D-1602,Launched,Q2'19,2,4,2.50 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i7-660UM Processor 4M Cache/ 1.33 GHz,i7-660UM,Discontinued,Q2'10,2,4,1.33 GHz,2.40 GHz,notFound
Intel® Celeron® D Processor 350/350J 256K Cache/ 3.20 GHz/ 533 MHz FSB,350J,Discontinued,Q3'05,1,notFound,3.20 GHz,notFound,notFound
Intel® Core™ i5-8210Y Processor 4M Cache/ up to 3.60 GHz,i5-8210Y,Discontinued,Q1'19,2,4,1.60 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i5-9500TE Processor 9M Cache/ up to 3.60 GHz,i5-9500TE,Launched,Q2'19,6,6,2.20 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® Processor E5-2603 v4 15M Cache/ 1.70 GHz,E5-2603V4,Launched,Q1'16,6,6,1.70 GHz,notFound,notFound
Intel® Pentium® D Processor 945 4M Cache/ 3.40 GHz/ 800 MHz FSB,945,Discontinued,Q3'06,2,notFound,3.40 GHz,notFound,notFound
Intel® Xeon® Silver 4109T Processor 11M Cache/ 2.00 GHz,4109T,Launched,Q3'17,8,16,2.00 GHz,3.00 GHz,notFound
Intel® Xeon® W-11855M Processor 18M Cache/ 3.20 GHz,W-11855M,Launched,Q2'21,6,12,notFound,4.90 GHz,notFound
Intel® Core™ i7-6700T Processor 8M Cache/ up to 3.60 GHz,i7-6700T,Launched,Q3'15,4,8,2.80 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i9-7980XE Extreme Edition Processor 24.75M Cache/ up to 4.20 GHz,i9-7980XE,Discontinued,Q3'17,18,36,2.60 GHz,4.20 GHz,notFound
Intel® Pentium® Processor U5600 3M Cache/ 1.33 GHz,U5600,Discontinued,Q1'11,2,2,1.33 GHz,notFound,notFound
Intel® Core™2 Quad Processor Q9450 12M Cache/ 2.66 GHz/ 1333 MHz FSB,Q9450,Discontinued,Q1'08,4,notFound,2.66 GHz,notFound,notFound
Intel® Core™ i7-4600M Processor 4M Cache/ up to 3.60 GHz,i7-4600M,Discontinued,Q4'13,2,4,2.90 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i7-8557U Processor 8M Cache/ up to 4.50 GHz,i7-8557U,Launched,Q3'19,4,8,1.70 GHz,4.50 GHz,4.50 GHz
Intel® Xeon® D-2146NT Processor 11M Cache/ 2.30 GHz,D-2146NT,Launched,Q1'18,8,16,2.30 GHz,3.00 GHz,notFound
Intel® Xeon® Processor E3-1280 v6 8M Cache/ 3.90 GHz,E3-1280V6,Launched,Q1'17,4,8,3.90 GHz,4.20 GHz,4.20 GHz
Intel® Core™ i7-10850H Processor 12M Cache/ up to 5.10 GHz,i7-10850H,Launched,Q2'20,6,12,2.70 GHz,5.10 GHz,notFound
Intel® Core™ i7-10700T Processor 16M Cache/ up to 4.50 GHz,i7-10700T,Launched,Q2'20,8,16,2.00 GHz,4.50 GHz,4.40 GHz
Intel® Core™2 Duo Processor SP9400 6M Cache/ 2.40 GHz/ 1066 MHz FSB,SP9400,Discontinued,Q3'08,2,notFound,2.40 GHz,notFound,notFound
Intel® Xeon® Processor LV 5138 4M Cache/ 2.13 GHz/ 1066 MHz FSB,5138,Discontinued,Q2'06,2,notFound,2.13 GHz,notFound,notFound
Intel® Itanium® Processor 9520 20M Cache/ 1.73 GHz,9520,Discontinued,Q4'12,4,8,1.73 GHz,notFound,notFound
Intel® Xeon® Processor X5647 12M Cache/ 2.93 GHz/ 5.86 GT/s Intel® QPI,X5647,Discontinued,Q1'11,4,8,2.93 GHz,3.20 GHz,notFound
Intel® Core™ i5-2450M Processor 3M Cache/ up to 3.10 GHz,i5-2450M,Discontinued,Q1'12,2,4,2.50 GHz,3.10 GHz,3.10 GHz
Intel® Core™2 Duo Processor P7370 3M Cache/ 2.00 GHz/ 1066 MHz FSB,P7370,Discontinued,Q4'08,2,notFound,2.00 GHz,notFound,notFound
Intel® Core™ i5-1135G7 Processor 8M Cache/ up to 4.20 GHz/ with IPU,i5-1135G7,Launched,Q3'20,4,8,notFound,4.20 GHz,notFound
Intel® Core™ i5-1135G7 Processor 8M Cache/ up to 4.20 GHz/ with IPU,i5-1135G7,Launched,Q3'20,4,8,notFound,4.20 GHz,notFound
Intel® Pentium® Processor G3460T 3M Cache/ 3.00 GHz,G3460T,Discontinued,Q1'15,2,2,3.00 GHz,notFound,notFound
Intel Atom® Processor Z500 512K Cache/ 800 MHz/ 400 MHz FSB,Z500,Discontinued,Q2'08,1,notFound,800 MHz,notFound,notFound
Intel® Core™ i3-10105T Processor 6M Cache/ up to 3.90 GHz,i3-10105T,Launched,Q1'21,4,8,3.00 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i5-9500F Processor 9M Cache/ up to 4.40 GHz,i5-9500F,Launched,Q2'19,6,6,3.00 GHz,4.40 GHz,4.40 GHz
Intel® Xeon® D-2145NT Processor 11M Cache/ 1.90 GHz,D-2145NT,Launched,Q1'18,8,16,1.90 GHz,3.00 GHz,notFound
Intel® Pentium® Processor T2130 1M Cache/ 1.86 GHz/ 533 MHz FSB,T2130,Discontinued,Q2'07,2,notFound,1.86 GHz,notFound,notFound
Intel® Core™ i5-7300U Processor 3M Cache/ up to 3.50 GHz,i5-7300U,Launched,Q1'17,2,4,2.60 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i5-7300U Processor 3M Cache/ up to 3.50 GHz,i5-7300U,Launched,Q1'17,2,4,2.60 GHz,3.50 GHz,3.50 GHz
Intel® Core™2 Quad Processor Q9550 12M Cache/ 2.83 GHz/ 1333 MHz FSB,Q9550,Discontinued,Q1'08,4,notFound,2.83 GHz,notFound,notFound
Intel® Xeon® Processor E5-2658 v4 35M Cache/ 2.30 GHz,E5-2658V4,Launched,Q1'16,14,28,2.30 GHz,2.80 GHz,2.80 GHz
Intel® Pentium® Processor G4600T 3M Cache/ 3.00 GHz,G4600T,Discontinued,Q1'17,2,4,3.00 GHz,notFound,notFound
Intel® Pentium® D Processor 930 4M Cache/ 3.00 GHz/ 800 MHz FSB,930,Discontinued,Q1'06,2,notFound,3.00 GHz,notFound,notFound
Intel Atom® Processor Z3795 2M Cache/ up to 2.39 GHz,Z3795,Discontinued,Q1'14,4,notFound,1.59 GHz,notFound,notFound
Intel Atom® Processor E3815 512K Cache/ 1.46 GHz,E3815,Launched,Q4'13,1,1,1.46 GHz,notFound,notFound
Intel® Core™ i7-2640M Processor 4M Cache/ up to 3.50 GHz,i7-2640M,Discontinued,Q4'11,2,4,2.80 GHz,3.50 GHz,3.50 GHz
Intel® Celeron® Processor G5905 4M Cache/ 3.50 GHz,G5905,Launched,Q3'20,2,2,3.50 GHz,notFound,notFound
Intel® Core™ i5-4300M Processor 3M Cache/ up to 3.30 GHz,i5-4300M,Discontinued,Q4'13,2,4,2.60 GHz,3.30 GHz,3.30 GHz
Intel® Pentium® D Processor 805 2M Cache/ 2.66 GHz/ 533 MHz FSB,805,Discontinued,Q1'05,2,notFound,2.66 GHz,notFound,notFound
Intel® Core™2 Duo Processor E7300 3M Cache/ 2.66 GHz/ 1066 MHz FSB,E7300,Discontinued,Q3'08,2,notFound,2.66 GHz,notFound,notFound
Intel® Xeon® Processor E7330 6M Cache/ 2.40 GHz/ 1066 MHz FSB,E7330,Discontinued,Q3'07,4,notFound,2.40 GHz,notFound,notFound
Intel® Pentium® Processor G840 3M Cache/ 2.80 GHz,G840,Discontinued,Q2'11,2,2,2.80 GHz,notFound,notFound
Intel® Celeron® Processor 3965Y 2M Cache/ 1.50 GHz,3965Y,Launched,Q2'17,2,2,1.50 GHz,notFound,notFound
Intel® Core™ i9-7960X X-series Processor 22M Cache/ up to 4.20 GHz,i9-7960X,Discontinued,Q3'17,16,32,2.80 GHz,4.20 GHz,notFound
Intel® Xeon® Processor E5-2690 v3 30M Cache/ 2.60 GHz,E5-2690V3,Discontinued,Q3'14,12,24,2.60 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i7-10700KF Processor 16M Cache/ up to 5.10 GHz,i7-10700KF,Launched,Q2'20,8,16,3.80 GHz,5.10 GHz,5.00 GHz
Intel® Core™ M-5Y70 Processor 4M Cache/ up to 2.60 GHz,5Y70,Discontinued,Q3'14,2,4,1.10 GHz,2.60 GHz,2.60 GHz
Intel® Xeon® Silver 4110 Processor 11M Cache/ 2.10 GHz,4110,Launched,Q3'17,8,16,2.10 GHz,3.00 GHz,notFound
Intel® Core™ i7-11850H Processor 24M Cache/ up to 4.80 GHz,i7-11850H,Launched,Q2'21,8,16,notFound,4.80 GHz,notFound
Intel® Pentium® Processor G645T 3M Cache/ 2.50 GHz,G645T,Discontinued,Q3'12,2,2,2.50 GHz,notFound,notFound
Intel® Celeron® Processor 1037U 2M Cache/ 1.80 GHz,1037U,Discontinued,Q1'13,2,2,1.80 GHz,notFound,notFound
Intel® Core™ i7-3740QM Processor 6M Cache/ up to 3.70 GHz,i7-3740QM,Discontinued,Q3'12,4,8,2.70 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i5+8500 Processor (9M Cache/ up to 4.10 GHz) includes Intel® Optane™ Memory 16GB,i5-8500,Launched,Q2'18,6,6,3.00 GHz,4.10 GHz,4.10 GHz
Intel Atom® Processor Z3775D 2M Cache/ up to 2.41 GHz,Z3775D,Discontinued,Q1'14,4,notFound,1.49 GHz,notFound,notFound
Intel Atom® Processor E3827 1M Cache/ 1.75 GHz,E3827,Launched,Q4'13,2,2,1.75 GHz,notFound,notFound
Intel® Xeon® Processor E7320 4M Cache/ 2.13 GHz/ 1066 MHz FSB,E7320,Discontinued,Q3'07,4,notFound,2.13 GHz,notFound,notFound
Intel® Xeon® Processor E7-4820 v4 25M Cache/ 2.00 GHz,E7-4820V4,Launched,Q2'16,10,20,2.00 GHz,notFound,notFound
Intel® Pentium® D Processor 920 4M Cache/ 2.80 GHz/ 800 MHz FSB,920,Discontinued,Q1'06,2,notFound,2.80 GHz,notFound,notFound
Intel® Celeron® Processor 5305U 2M Cache/ 2.3 GHz,5305U,Launched,Q2'20,2,2,2.30 GHz,notFound,notFound
Intel® Core™ i7-2635QM Processor 6M Cache/ up to 2.90 GHz,i7-2635QM,Discontinued,Q1'11,4,8,2.00 GHz,2.90 GHz,2.90 GHz
Intel® Core™ i3-2340UE Processor 3M Cache/ 1.30 GHz,i3-2340UE,Discontinued,Q2'11,2,4,1.30 GHz,notFound,notFound
Intel® Xeon Phi™ Coprocessor 5110P 8GB/ 1.053 GHz/ 60 core,5110P,Discontinued,Q4'12,60,notFound,1.05 GHz,notFound,notFound
Intel® Core™ i5+8400 Processor (9M Cache/ up to 4.00 GHz) includes Intel® Optane™ Memory 16GB,i5-8400,Launched,Q2'18,6,6,2.80 GHz,4.00 GHz,4.00 GHz
Intel® Core™2 Duo Processor T5750 2M Cache/ 2.00 GHz/ 667 MHz FSB,T5750,Discontinued,Q1'08,2,notFound,2.00 GHz,notFound,notFound
Intel® Celeron® Processor G465 1.5M Cache/ 1.90 GHz,G465,Discontinued,Q3'12,1,2,1.90 GHz,notFound,notFound
Intel® Xeon® Bronze 3106 Processor 11M Cache/ 1.70 GHz,3106,Launched,Q3'17,8,8,1.70 GHz,notFound,notFound
Intel® Itanium® Processor 9320 16M Cache/ 1.33 GHz/ 4.80 GT/s Intel® QPI,9320,Discontinued,Q1'10,4,8,1.33 GHz,1.47 GHz,notFound
Intel® Pentium® Processor J2850 2M Cache/ 2.41 GHz,J2850,Discontinued,Q3'13,4,4,2.41 GHz,notFound,notFound
Intel® Celeron® Processor T1700 1M Cache/ 1.83 GHz/ 667 MHz FSB,T1700,Discontinued,Q4'08,2,notFound,1.83 GHz,notFound,notFound
Intel Atom® Processor D510 1M Cache/ 1.66 GHz,D510,Discontinued,Q1'10,2,4,1.66 GHz,notFound,notFound
Intel Atom® Processor Z2420 512K Cache/ up to 1.20 GHZ,Z2420,Discontinued,Q1'13,1,2,notFound,notFound,notFound
Intel® Xeon® Processor E5-1680 v3 20M Cache/ 3.20 GHz,E5-1680V3,Discontinued,Q3'14,8,16,3.20 GHz,3.80 GHz,3.80 GHz
Intel® Core™2 Quad Processor Q9650 12M Cache/ 3.00 GHz/ 1333 MHz FSB,Q9650,Discontinued,Q3'08,4,notFound,3.00 GHz,notFound,notFound
Intel® Xeon® Platinum 8351N Processor 54M Cache/ 2.40 GHz,8351N,Launched,Q2'21,36,72,2.40 GHz,3.50 GHz,notFound
Intel® Xeon® D-1622 Processor 6M Cache/ 2.60GHz,D-1622,Launched,Q2'19,4,8,2.60 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i5-540UM Processor 3M Cache/ 1.20 GHz,i5-540UM,Discontinued,Q2'10,2,4,1.20 GHz,2.00 GHz,notFound
Intel® Core™ i7-4771 Processor 8M Cache/ up to 3.90 GHz,i7-4771,Discontinued,Q3'13,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Celeron® D Processor 350 256K Cache/ 3.20 GHz/ 533 MHz FSB,350,Discontinued,Q3'05,1,notFound,3.20 GHz,notFound,notFound
Intel® Core™ i7-5820K Processor 15M Cache/ up to 3.60 GHz,i7-5820K,Discontinued,Q3'14,6,12,3.30 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® Processor E5-1680 v4 20M Cache/ 3.40 GHz,E5-1680V4,Launched,Q2'16,8,16,3.40 GHz,4.00 GHz,notFound
Intel® Core™ i5-3470T Processor 3M Cache/ up to 3.60 GHz,i5-3470T,Discontinued,Q2'12,2,4,2.90 GHz,3.60 GHz,3.60 GHz
Intel® Celeron® Processor B710 1.5M Cache/ 1.60 GHz,B710,Discontinued,Q3'11,1,1,1.60 GHz,notFound,notFound
Intel® Core™ i3-4170 Processor 3M Cache/ 3.70 GHz,i3-4170,Discontinued,Q1'15,2,4,3.70 GHz,notFound,notFound
Intel® Xeon® Silver 4215R Processor 11M Cache/ 3.20 GHz,4215R,Launched,Q1'20,8,16,3.20 GHz,4.00 GHz,notFound
Intel® Core™ M-5Y51 Processor 4M Cache/ up to 2.60 GHz,5Y51,Discontinued,Q4'14,2,4,1.10 GHz,2.60 GHz,2.60 GHz
Intel® Pentium® Processor T4500 1M Cache/ 2.30 GHz/ 800 MHz FSB,T4500,Discontinued,Q1'10,2,notFound,2.30 GHz,notFound,notFound
Intel® Core™ i5-3330 Processor 6M Cache/ up to 3.20 GHz,i5-3330,Discontinued,Q3'12,4,4,3.00 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® W-1290TE Processor 20M Cache/ up to 4.50 GHz,W-1290TE,Launched,Q2'20,10,20,1.80 GHz,4.50 GHz,notFound
Intel® Celeron® Processor E3200 1M Cache/ 2.40 GHz/ 800 MHz FSB,E3200,Discontinued,Q3'09,2,notFound,2.40 GHz,notFound,notFound
Intel® Core™ i7-2657M Processor 4M Cache/ up to 2.70 GHz,i7-2657M,Discontinued,Q1'11,2,4,1.60 GHz,2.70 GHz,2.70 GHz
Intel Atom® x6413E Processor 1.5M Cache/ up to 3.00 GHz,6413E,Launched,Q1'21,4,4,1.50 GHz,notFound,notFound
Intel® Core™ i5-3610ME Processor 3M Cache/ up to 3.30 GHz,i5-3610ME,Launched,Q2'12,2,4,2.70 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® Processor E3-1558L v5 8M Cache/ 1.90 GHz,E3-1558LV5,Launched,Q2'16,4,8,1.90 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® Processor E5-4650 20M Cache/ 2.70 GHz/ 8.00 GT/s Intel® QPI,E5-4650,Discontinued,Q2'12,8,16,2.70 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® D-1653N Processor 12M Cache/ 2.80GHz,D-1653N,Launched,Q2'19,8,16,2.80 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i5-10300H Processor 8M Cache/ up to 4.50 GHz,i5-10300H,Launched,Q2'20,4,8,2.50 GHz,4.50 GHz,4.50 GHz
Intel® Celeron® D Processor 340J 256K Cache/ 2.93 GHz/ 533 MHz FSB,340J,Discontinued,Q4'04,1,notFound,2.93 GHz,notFound,notFound
Intel® Core™ i5-8310Y Processor 4M Cache/ up to 3.90 GHz,i5-8310Y,Launched,Q1'19,2,4,1.60 GHz,3.90 GHz,3.90 GHz
Intel® Celeron® Processor SU2300 1M Cache/ 1.20 GHz/ 800 MHz FSB,SU2300,Discontinued,Q3'09,2,notFound,1.20 GHz,notFound,notFound
Intel® Xeon® Processor L3014 3M Cache/ 2.40 GHz/ 1066 MHz FSB,L3014,Discontinued,Q1'08,1,notFound,2.40 GHz,notFound,notFound
Intel Atom® x6414RE Processor 1.5M Cache/ 1.50 GHz,6414RE,Launched,Q1'21,4,4,1.50 GHz,notFound,notFound
Intel® Xeon® Gold 6226R Processor 22M Cache/ 2.90 GHz,6226R,Launched,Q1'20,16,32,2.90 GHz,3.90 GHz,notFound
Intel® Core™ i7-9850HE Processor 9M Cache/ up to 4.40 GHz,i7-9850HE,Launched,Q2'19,6,12,2.70 GHz,4.40 GHz,4.40 GHz
Intel® Celeron® Processor G6900T 4M Cache/ 2.80 GHz,G6900T,Launched,Q1'22,2,2,notFound,notFound,notFound
Intel® Core™ i7-12700F Processor 25M Cache/ up to 4.90 GHz,i7-12700F,Launched,Q1'22,12,20,notFound,4.90 GHz,notFound
Intel® Celeron® D Processor 351 256K Cache/ 3.20 GHz/ 533 MHz FSB,351,Discontinued,Q3'05,1,notFound,3.20 GHz,notFound,notFound
Intel® Celeron® Processor U3400 2M Cache/ 1.06 GHz,U3400,Discontinued,Q2'10,2,2,1.06 GHz,notFound,notFound
Intel® Core™ i9-9820X X-series Processor 16.5M Cache/ up to 4.20 GHz,i9-9820X,Discontinued,Q4'18,10,20,3.30 GHz,4.10 GHz,notFound
Intel® Xeon® Processor E5-2637 v2 15M Cache/ 3.50 GHz,E5-2637V2,Discontinued,Q3'13,4,8,3.50 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Processor X5365 8M Cache/ 3.00 GHz/ 1333 MHz FSB,X5365,Discontinued,Q3'07,4,notFound,3.00 GHz,notFound,notFound
Intel® Xeon® Gold 6330N Processor 42M Cache/ 2.20 GHz,6330N,Launched,Q2'21,28,56,2.20 GHz,3.40 GHz,notFound
Intel® Xeon® Processor E3-1230 v2 8M Cache/ 3.30 GHz,E3-1230V2,Discontinued,Q2'12,4,8,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i5-5675C Processor 4M Cache/ up to 3.60 GHz,i5-5675C,Discontinued,Q2'15,4,notFound,3.10 GHz,3.60 GHz,3.60 GHz
Intel® Pentium® Processor T2310 1M Cache/ 1.46 GHz/ 533 MHz FSB,T2310,Discontinued,Q4'07,2,notFound,1.46 GHz,notFound,notFound
Intel® Celeron® D Processor 335/335J 256K Cache/ 2.80 GHz/ 533 MHz FSB,335,Discontinued,Q2'04,1,notFound,2.80 GHz,notFound,notFound
Intel® Xeon® Processor L3360 12M Cache/ 2.83 GHz/ 1333 MHz FSB,L3360,Discontinued,Q1'09,4,notFound,2.83 GHz,notFound,notFound
Intel® Core™ i5-1035G7 Processor 6M Cache/ up to 3.70 GHz,i5-1035G7,Launched,Q3'19,4,8,1.20 GHz,3.70 GHz,notFound
Intel® Core™ i5-11500T Processor 12M Cache/ up to 3.90 GHz,i5-11500T,Launched,Q1'21,6,12,1.50 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor E5-2407 10M Cache/ 2.20 GHz/ 6.40 GT/s Intel® QPI,E5-2407,Discontinued,Q2'12,4,4,2.20 GHz,notFound,notFound
Intel® Core™ i5-4402EC Processor 4M Cache/ up to 2.50 GHz,i5-4402EC,Launched,Q1'14,2,4,2.50 GHz,notFound,notFound
Intel® Core™ i7-12700KF Processor 25M Cache/ up to 5.00 GHz,i7-12700KF,Launched,Q4'21,12,20,notFound,5.00 GHz,notFound
Intel® Core™ i7-10750H Processor 12M Cache/ up to 5.00 GHz,i7-10750H,Launched,Q2'20,6,12,2.60 GHz,5.00 GHz,notFound
Intel® Core™ i9-9980XE Extreme Edition Processor 24.75M Cache/ up to 4.50 GHz,i9-9980XE,Discontinued,Q4'18,18,36,3.00 GHz,4.40 GHz,notFound
Intel® Celeron® Processor G6900 4M Cache/ 3.40 GHz,G6900,Launched,Q1'22,2,2,notFound,notFound,notFound
Intel® Celeron® Processor 3865U 2M Cache/ 1.80 GHz,3865U,Launched,Q1'17,2,2,1.80 GHz,notFound,notFound
Intel® Xeon® W-1250P Processor 12M Cache/ 4.10 GHz,W-1250P,Launched,Q2'20,6,12,4.10 GHz,4.80 GHz,4.80 GHz
Intel® Pentium® Processor N6415 1.5M Cache/ up to 3.00 GHz,N6415,Launched,Q1'21,4,4,1.20 GHz,notFound,notFound
Intel® Core™2 Quad Processor Q9550S 12M Cache/ 2.83 GHz/ 1333 MHz FSB,Q9550S,Discontinued,Q1'09,4,notFound,2.83 GHz,notFound,notFound
Intel® Xeon® Processor E5-2430L 15M Cache/ 2.00 GHz/ 7.20 GT/s Intel® QPI,E5-2430L,Discontinued,Q2'12,6,12,2.00 GHz,2.50 GHz,2.50 GHz
Intel® Core™ i7-11700K Processor 16M Cache/ up to 5.00 GHz,i7-11700K,Launched,Q1'21,8,16,3.60 GHz,5.00 GHz,4.90 GHz
Intel® Core™ i5-11600K Processor 12M Cache/ up to 4.90 GHz,i5-11600K,Launched,Q1'21,6,12,3.90 GHz,4.90 GHz,4.90 GHz
Intel® Celeron® D Processor 325J 256K Cache/ 2.53 GHz/ 533 MHz FSB,325J,Discontinued,Q4'04,1,notFound,2.53 GHz,notFound,notFound
Intel® Xeon® Processor E3-1220L 3M Cache/ 2.20 GHz,E3-1220L,Discontinued,Q2'11,2,4,2.20 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i3-2357M Processor 3M Cache/ 1.30 GHz,i3-2357M,Discontinued,Q2'11,2,4,1.30 GHz,notFound,notFound
Intel® Xeon® Processor E3-1220L v2 3M Cache/ 2.30 GHz,E3-1220LV2,Discontinued,Q2'12,2,4,2.30 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i7-8750H Processor 9M Cache/ up to 4.10 GHz,i7-8750H,Launched,Q2'18,6,12,2.20 GHz,4.10 GHz,4.10 GHz
Intel® Core™ i5-2550K Processor 6M Cache/ up to 3.80 GHz,i5-2550K,Discontinued,Q1'12,4,4,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Processor E7-2850 24M Cache/ 2.00 GHz/ 6.40 GT/s Intel® QPI,E7-2850,Discontinued,Q2'11,10,20,2.00 GHz,2.40 GHz,notFound
Intel® Xeon® Processor E5-2697 v2 30M Cache/ 2.70 GHz,E5-2697V2,Discontinued,Q3'13,12,24,2.70 GHz,3.50 GHz,3.50 GHz
Intel Atom® Processor C3708 16M Cache/ up to 1.70 GHz,C3708,Launched,Q3'17,8,8,1.70 GHz,1.70 GHz,notFound
Intel® Core™ i5-520M Processor 3M Cache/ 2.40 GHz,i5-520M,Discontinued,Q1'10,2,4,2.40 GHz,2.93 GHz,notFound
Intel® Core™ i5-4278U Processor 3M Cache/ up to 3.10 GHz,i5-4278U,Discontinued,Q3'14,2,4,2.60 GHz,3.10 GHz,3.10 GHz
Intel® Pentium® Processor 1405 5M Cache/ 1.2 GHz,1405,Discontinued,Q2'12,2,2,1.20 GHz,1.80 GHz,notFound
Intel® Xeon® Processor E5-2680 v2 25M Cache/ 2.80 GHz,E5-2680V2,Discontinued,Q3'13,10,20,2.80 GHz,3.60 GHz,3.60 GHz
Intel® Core™2 Duo Processor E6600 4M Cache/ 2.40 GHz/ 1066 MHz FSB,E6600,Discontinued,Q3'06,2,notFound,2.40 GHz,notFound,notFound
Intel® Xeon® Platinum 9221 Processor 71.5M Cache/ 2.30 GHz,9221,Launched,Q3'19,32,64,2.30 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i5-4570T Processor 4M Cache/ up to 3.60 GHz,i5-4570T,Discontinued,Q2'13,2,4,2.90 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® Platinum 8352S Processor 48M Cache/ 2.20 GHz,8352S,Launched,Q2'21,32,64,2.20 GHz,3.40 GHz,notFound
Intel® Core™ i7-4710HQ Processor 6M Cache/ up to 3.50 GHz,i7-4710HQ,Discontinued,Q2'14,4,8,2.50 GHz,3.50 GHz,3.50 GHz
Intel Atom® Processor C2358 1M Cache/ 1.70 GHz,C2358,Launched,Q3'13,2,2,1.70 GHz,2.00 GHz,2.00 GHz
Intel® Core™ i5-7Y54 Processor 4M Cache/ up to 3.20 GHz,i5-7Y54,Launched,Q3'16,2,4,1.20 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® Gold 5120T Processor 19.25M Cache/ 2.20 GHz,5120T,Launched,Q3'17,14,28,2.20 GHz,3.20 GHz,notFound
Intel® Core™2 Quad Processor Q6600 8M Cache/ 2.40 GHz/ 1066 MHz FSB,Q6600,Discontinued,Q1'07,4,notFound,2.40 GHz,notFound,notFound
Intel® Xeon® Processor E5-2637 5M Cache/ 3.00 GHz/ 8.00 GT/s Intel® QPI,E5-2637,Discontinued,Q1'12,2,4,3.00 GHz,3.50 GHz,3.50 GHz
Intel® Xeon® Processor E5-2667 v3 20M Cache/ 3.20 GHz,E5-2667V3,Discontinued,Q3'14,8,16,3.20 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® Gold 6222V Processor 27.5M Cache/ 1.80 GHz,6222V,Launched,Q2'19,20,40,1.80 GHz,3.60 GHz,notFound
Intel® Core™ i3-1125G4 Processor 8M Cache/ up to 3.70 GHz,i3-1125G4,Launched,Q1'21,4,8,notFound,3.70 GHz,notFound
Intel® Celeron® Processor 3955U 2M Cache/ 2.00 GHz,3955U,Launched,Q4'15,2,2,2.00 GHz,notFound,notFound
Intel® Xeon® Gold 6126 Processor 19.25M Cache/ 2.60 GHz,6126,Launched,Q3'17,12,24,2.60 GHz,3.70 GHz,notFound
Intel® Core™ i5-6350HQ Processor 6M Cache/ up to 3.20 GHz,i5-6350HQ,Discontinued,Q1'16,4,4,2.30 GHz,3.20 GHz,3.20 GHz
Intel® Core™ i5-450M Processor 3M cache/ 2.40 GHz,i5-450M,Discontinued,Q2'10,2,4,2.40 GHz,2.66 GHz,notFound
Intel® Xeon® Processor E7-4850 v2 24M Cache/ 2.30 GHz,E7-4850V2,Discontinued,Q1'14,12,24,2.30 GHz,2.80 GHz,2.80 GHz
Intel® Core™ i7-4810MQ Processor 6M Cache/ up to 3.80 GHz,i7-4810MQ,Discontinued,Q1'14,4,8,2.80 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Processor E7-8870 30M Cache/ 2.40 GHz/ 6.40 GT/s Intel® QPI,E7-8870,Discontinued,Q2'11,10,20,2.40 GHz,2.80 GHz,notFound
Intel® Xeon® Processor E5-2650L v2 25M Cache/ 1.70 GHz,E5-2650LV2,Discontinued,Q3'13,10,20,1.70 GHz,2.10 GHz,2.10 GHz
Intel® Core™2 Duo Processor T7600 4M Cache/ 2.33 GHz/ 667 MHz FSB,T7600,Discontinued,Q3'07,2,notFound,2.33 GHz,notFound,notFound
Intel® Xeon® Platinum 8362 Processor 48M Cache/ 2.80 GHz,8362,Launched,Q2'21,32,64,2.80 GHz,3.60 GHz,notFound
Intel® Core™ i5-3337U Processor 3M Cache/ up to 2.70 GHz,i5-3337U,Discontinued,Q1'13,2,4,1.80 GHz,2.70 GHz,2.70 GHz
Intel® Core™ i5-8257U Processor 6M Cache/ up to 3.90 GHz,i5-8257U,Launched,Q3'19,4,8,1.40 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor E7-4850 24M Cache/ 2.00 GHz/ 6.40 GT/s Intel® QPI,E7-4850,Discontinued,Q2'11,10,20,2.00 GHz,2.40 GHz,notFound
Intel Atom® Processor C3955 16M Cache/ up to 2.40 GHz,C3955,Launched,Q3'17,16,16,2.10 GHz,2.40 GHz,2.40 GHz
Intel® Xeon® Processor E5-2640 v3 20M Cache/ 2.60 GHz,E5-2640V3,Launched,Q3'14,8,16,2.60 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® Processor L5240 6M Cache/ 3.00 GHz/ 1333 MHz FSB,L5240,Discontinued,Q2'08,2,notFound,3.00 GHz,notFound,notFound
Intel® Celeron® Processor G1610 2M Cache/ 2.60 GHz,G1610,Discontinued,Q1'13,2,2,2.60 GHz,notFound,notFound
Intel® Pentium® Processor G3260 3M Cache/ 3.30 GHz,G3260,Discontinued,Q1'15,2,2,3.30 GHz,notFound,notFound
Intel® Core™ i5-8265U Processor 6M Cache/ up to 3.90 GHz,i5-8265U,Launched,Q3'18,4,8,1.60 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i5-8265U Processor 6M Cache/ up to 3.90 GHz,i5-8265U,Launched,Q3'18,4,8,1.60 GHz,3.90 GHz,3.90 GHz
Intel® Pentium® Gold G5400 Processor 4M Cache/ 3.70 GHz,G5400,Launched,Q2'18,2,4,3.70 GHz,notFound,notFound
Intel® Xeon® Gold 5115 Processor 13.75M Cache/ 2.40 GHz,5115,Launched,Q3'17,10,20,2.40 GHz,3.20 GHz,notFound
Intel® Core™ i3-1110G4 Processor 6M Cache/ up to 3.90 GHz/ with IPU,i3-1110G4,Launched,Q3'20,2,4,notFound,3.90 GHz,notFound
Intel® Core™2 Duo Processor T7700 4M Cache/ 2.40 GHz/ 800 MHz FSB,T7700,Discontinued,Q2'07,2,notFound,2.40 GHz,notFound,notFound
Intel Atom® x5-E3930 Processor 2M Cache/ up to 1.80 GHz,E3930,Launched,Q4'16,2,2,1.30 GHz,notFound,notFound
Intel® Xeon® Processor E5-2683 v3 35M Cache/ 2.00 GHz,E5-2683V3,Discontinued,Q3'14,14,28,2.00 GHz,3.00 GHz,3.00 GHz
Intel® Core™ i3-7101E Processor 3M Cache/ 3.90 GHz,i3-7101E,Launched,Q1'17,2,4,3.90 GHz,notFound,notFound
Intel® Core™2 Extreme Processor QX9770 12M Cache/ 3.20 GHz/ 1600 MHz FSB,QX9770,Discontinued,Q1'08,4,notFound,3.20 GHz,notFound,notFound
Intel® Xeon® Processor E7-4820 v2 16M Cache/ 2.00 GHz,E7-4820V2,Discontinued,Q1'14,8,16,2.00 GHz,2.50 GHz,2.50 GHz
Intel® Pentium® Processor N4200E 2M Cache/ up to 2.50 GHz,N4200E,Launched,Q3'19,4,4,1.10 GHz,2.50 GHz,notFound
Intel® Core™ i3-5157U Processor 3M Cache/ 2.50 GHz,i3-5157U,Discontinued,Q1'15,2,4,2.50 GHz,notFound,notFound
Intel® Xeon® Gold 5217 Processor 11M Cache/ 3.00 GHz,5217,Launched,Q2'19,8,16,3.00 GHz,3.70 GHz,notFound
Intel® Celeron® Processor 2000E 2M Cache/ 2.20 GHz,2000E,Launched,Q1'14,2,2,2.20 GHz,notFound,notFound
Intel® Core™ i3-9100HL Processor 6M Cache/ up to 2.90 GHz,i3-9100HL,Launched,Q2'19,4,4,1.60 GHz,2.90 GHz,2.90 GHz
Intel® Xeon® Gold 6136 Processor 24.75M Cache/ 3.00 GHz,6136,Launched,Q3'17,12,24,3.00 GHz,3.70 GHz,notFound
Intel® Itanium® Processor 9140M 18M Cache/ 1.66 GHz/ 667 MHz FSB,9140M,Discontinued,Q4'07,2,notFound,1.66 GHz,notFound,notFound
Intel® Xeon® Processor E5-2690 20M Cache/ 2.90 GHz/ 8.00 GT/s Intel® QPI,E5-2690,Discontinued,Q1'12,8,16,2.90 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i5-1135G7 Processor 8M Cache/ up to 4.20 GHz,i5-1135G7,Launched,Q3'20,4,8,notFound,4.20 GHz,notFound
Intel® Core™ i5-1135G7 Processor 8M Cache/ up to 4.20 GHz,i5-1135G7,Launched,Q3'20,4,8,notFound,4.20 GHz,notFound
Intel® Xeon® Gold 6348H Processor 33M Cache/ 2.30 GHz,6348H,Launched,Q2'20,24,48,2.30 GHz,4.20 GHz,notFound
Intel® Pentium® Processor G3250T 3M Cache/ 2.80 GHz,G3250T,Discontinued,Q3'14,2,2,2.80 GHz,notFound,notFound
Intel® Core™ i5-9600T Processor 9M Cache/ up to 3.90 GHz,i5-9600T,Launched,Q2'19,6,6,2.30 GHz,3.90 GHz,3.90 GHz
Intel® Core™2 Duo Processor T9400 6M Cache/ 2.53 GHz/ 1066 MHz FSB,T9400,Discontinued,Q3'08,2,notFound,2.53 GHz,notFound,notFound
Intel Atom® Processor C2338 1M Cache/ 1.70 GHz,C2338,Launched,Q3'13,2,2,1.70 GHz,2.00 GHz,2.00 GHz
Intel® Xeon® Processor E5-2690 v2 25M Cache/ 3.00 GHz,E5-2690V2,Discontinued,Q3'13,10,20,3.00 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i3-350M Processor 3M Cache/ 2.26 GHz,i3-350M,Discontinued,Q1'10,2,4,2.26 GHz,notFound,notFound
Intel® Core™2 Duo Processor E4300 2M Cache/ 1.80 GHz/ 800 MHz FSB,E4300,Discontinued,Q3'06,2,notFound,1.80 GHz,notFound,notFound
Intel® Xeon® Processor E7-4809 v4 20M Cache/ 2.10 GHz,E7-4809V4,Launched,Q2'16,8,16,2.10 GHz,notFound,notFound
Intel® Xeon® W-3223 Processor 16.5M Cache/ 3.50 GHz,W-3223,Launched,Q2'19,8,16,3.50 GHz,4.00 GHz,notFound
Intel® Core™ i7-4578U Processor 4M Cache/ up to 3.50 GHz,i7-4578U,Discontinued,Q3'14,2,4,3.00 GHz,3.50 GHz,3.50 GHz
Intel® Pentium® Gold 7505 Processor 4M Cache/ up to 3.50 GHz/ with IPU,7505,Launched,Q4'20,2,4,notFound,3.50 GHz,notFound
Intel® Xeon® Processor E5-2608L v3 15M Cache/ 2.00 GHz,E5-2608LV3,Launched,Q3'14,6,12,2.00 GHz,notFound,notFound
Intel® Xeon® Gold 5218T Processor 22M Cache/ 2.10 GHz,5218T,Launched,Q2'19,16,32,2.10 GHz,3.80 GHz,notFound
Intel Atom® Processor C2550 2M Cache/ 2.40 GHz,C2550,Launched,Q3'13,4,4,2.40 GHz,2.60 GHz,2.60 GHz
Intel® Core™2 Duo Processor E6320 4M Cache/ 1.86 GHz/ 1066 MHz FSB,E6320,Discontinued,Q2'07,2,notFound,1.86 GHz,notFound,notFound
Intel Atom® Processor E680 512K Cache/ 1.60 GHz,E680,Discontinued,Q3'10,1,2,1.60 GHz,notFound,notFound
Intel® Xeon® Platinum 8353H Processor 24.75M Cache/ 2.50 GHz,8353H,Launched,Q2'20,18,36,2.50 GHz,3.80 GHz,notFound
Intel® Celeron® Processor E1400 512K Cache/ 2.00 GHz/ 800 MHz FSB,E1400,Discontinued,Q2'08,2,notFound,2.00 GHz,notFound,notFound
Intel® Itanium® Processor 9130M 8M Cache/ 1.66 GHz/ 667 MHz FSB,9130M,Discontinued,Q4'07,2,notFound,1.66 GHz,notFound,notFound
Intel® Xeon® Processor E5-2640 15M Cache/ 2.50 GHz/ 7.20 GT/s Intel® QPI,E5-2640,Discontinued,Q1'12,6,12,2.50 GHz,3.00 GHz,notFound
Intel Atom® x7-E3950 Processor 2M Cache/ up to 2.00 GHz,E3950,Launched,Q4'16,4,4,1.60 GHz,notFound,notFound
Intel® Xeon® Gold 5215 Processor 13.75M Cache/ 2.50 GHz,5215,Launched,Q2'19,10,20,2.50 GHz,3.40 GHz,notFound
Intel® Celeron® Processor 807UE 1M Cache/ 1.00 GHz,807UE,Discontinued,Q4'11,1,1,1.00 GHz,notFound,notFound
Intel® Core™ i5-4400E Processor 3M Cache/ up to 3.30 GHz,i5-4400E,Launched,Q3'13,2,4,2.70 GHz,3.30 GHz,3.30 GHz
Intel® Celeron® Processor N3350E 2M Cache/ up to 2.40 GHz,N3350E,Discontinued,Q3'19,2,2,1.10 GHz,2.40 GHz,notFound
Intel® Core™ i5-5257U Processor 3M Cache/ up to 3.10 GHz,i5-5257U,Launched,Q1'15,2,4,2.70 GHz,3.10 GHz,3.10 GHz
Intel® Core™ i5-5257U Processor 3M Cache/ up to 3.10 GHz,i5-5257U,Launched,Q1'15,2,4,2.70 GHz,3.10 GHz,3.10 GHz
Intel® Core™ i9-11900KB Processor 24M Cache/ up to 4.90 GHz,i9-11900KB,Launched,Q2'21,8,16,3.30 GHz,4.90 GHz,notFound
Intel® Pentium® Processor G3470 3M Cache/ 3.60 GHz,G3470,Discontinued,Q1'15,2,2,3.60 GHz,notFound,notFound
Intel® Xeon® Processor E7-2880 v2 37.5M Cache/ 2.50 GHz,E7-2880V2,Launched,Q1'14,15,30,2.50 GHz,3.10 GHz,3.10 GHz
Intel® Core™2 Extreme Processor X9000 6M Cache/ 2.80 GHz/ 800 MHz FSB,X9000,Discontinued,Q1'08,2,notFound,2.80 GHz,notFound,notFound
Intel® Xeon® Processor E5-2630L v3 20M Cache/ 1.80 GHz,E5-2630LV3,Discontinued,Q3'14,8,16,1.80 GHz,2.90 GHz,2.90 GHz
Intel® Xeon® Gold 6234 Processor 24.75M Cache/ 3.30 GHz,6234,Launched,Q2'19,8,16,3.30 GHz,4.00 GHz,notFound
Intel Atom® Processor C2730 4M Cache/ 1.70 GHz,C2730,Launched,Q3'13,8,8,1.70 GHz,2.40 GHz,2.40 GHz
Intel® Core™2 Duo Processor E4400 2M Cache/ 2.00 GHz/ 800 MHz FSB,E4400,Discontinued,Q2'07,2,notFound,2.00 GHz,notFound,notFound
Intel® Core™ i5-1145G7 Processor 8M Cache/ up to 4.40 GHz/ with IPU,i5-1145G7,Launched,Q1'21,4,8,notFound,4.40 GHz,notFound
Intel® Core™ i5-1145G7 Processor 8M Cache/ up to 4.40 GHz/ with IPU,i5-1145G7,Launched,Q1'21,4,8,notFound,4.40 GHz,notFound
Intel® Xeon® Processor E7-8860 v4 45M Cache/ 2.20 GHz,E7-8860V4,Launched,Q2'16,18,36,2.20 GHz,3.20 GHz,3.20 GHz
Intel® Pentium® Processor B970 2M Cache/ 2.30 GHz,B970,Discontinued,Q1'12,2,2,2.30 GHz,notFound,notFound
Intel® Xeon® Processor D-1521 6M Cache/ 2.40 GHz,D-1521,Launched,Q4'15,4,8,2.40 GHz,2.70 GHz,2.70 GHz
Intel® Core™ i7-4910MQ Processor 8M Cache/ up to 3.90 GHz,i7-4910MQ,Discontinued,Q1'14,4,8,2.90 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor D-1553N 12M Cache/ 2.30 GHz,D-1553N,Launched,Q3'17,8,16,2.30 GHz,2.70 GHz,2.70 GHz
Intel Atom® x3-C3200RK Processor 1M Cache/ up to 1.10 GHz,x3-C3200RK,Discontinued,Q1'15,4,notFound,notFound,notFound,notFound
Intel® Xeon® Processor X7550 18M Cache/ 2.00 GHz/ 6.40 GT/s Intel® QPI,X7550,Discontinued,Q1'10,8,16,2.00 GHz,2.40 GHz,notFound
Intel® Xeon® Processor E5-2408L v3 10M Cache/ 1.80 GHz,E5-2408LV3,Launched,Q1'15,4,8,1.80 GHz,notFound,notFound
Intel® Core™ i5-7287U Processor 4M Cache/ up to 3.70 GHz,i5-7287U,Discontinued,Q1'17,2,4,3.30 GHz,3.70 GHz,3.70 GHz
Intel® Xeon® W-3175X Processor 38.5M Cache/ 3.10 GHz,W-3175X,Launched,Q4'18,28,56,3.10 GHz,3.80 GHz,notFound
Intel® Core™2 Duo Processor P9600 6M Cache/ 2.66 GHz/ 1066 MHz FSB,P9600,Discontinued,Q4'08,2,notFound,2.66 GHz,notFound,notFound
Intel® Xeon® Processor E3-1230 v5 8M Cache/ 3.40 GHz,E3-1230V5,Launched,Q4'15,4,8,3.40 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Processor L5410 12M Cache/ 2.33 GHz/ 1333 MHz FSB,L5410,Discontinued,Q1'08,4,notFound,2.33 GHz,notFound,notFound
Intel® Pentium® Processor E2140 1M Cache/ 1.60 GHz/ 800 MHz FSB,E2140,Discontinued,Q2'07,2,notFound,1.60 GHz,notFound,notFound
Intel® Pentium® Processor E2180 1M Cache/ 2.00 GHz/ 800 MHz FSB,E2180,Discontinued,Q3'07,2,notFound,2.00 GHz,notFound,notFound
Intel® Pentium® 4 Processor 530J supporting HT Technology 1M Cache/ 3.00 GHz/ 800 MHz FSB,530J,Discontinued,Q4'04,1,notFound,3.00 GHz,notFound,notFound
Intel® Core™ i3-4330T Processor 4M Cache/ 3.00 GHz,i3-4330T,Discontinued,Q3'13,2,4,3.00 GHz,notFound,notFound
Intel® Core™ i5-4200H Processor 3M Cache/ up to 3.40 GHz,i5-4200H,Discontinued,Q4'13,2,4,2.80 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® Processor E3-1240 v5 8M Cache/ 3.50 GHz,E3-1240V5,Discontinued,Q4'15,4,8,3.50 GHz,3.90 GHz,3.90 GHz
Intel® Xeon® Processor E3-1276 v3 8M Cache/ 3.60 GHz,E3-1276V3,Discontinued,Q2'14,4,8,3.60 GHz,4.00 GHz,4.00 GHz
Intel® Quark™ SoC X1000 16K Cache/ 400 MHz,X1000,Discontinued,Q4'13,1,1,400 MHz,notFound,notFound
Intel® Core™ i7-6920HQ Processor 8M Cache/ up to 3.80 GHz,i7-6920HQ,Discontinued,Q3'15,4,8,2.90 GHz,3.80 GHz,3.80 GHz
Intel® Core™ i7-10510U Processor 8M Cache/ up to 4.90 GHz,i7-10510U,Launched,Q3'19,4,8,1.80 GHz,4.90 GHz,notFound
Intel® Celeron® Processor G3900E 2M Cache/ 2.40 GHz,G3900E,Launched,Q1'16,2,2,2.40 GHz,notFound,notFound
Intel® Xeon® Processor E3-1125C 8M Cache/ 2.00 GHz,E3-1125C,Discontinued,Q2'12,4,8,2.00 GHz,notFound,notFound
Intel® Core™ i3-550 Processor 4M Cache/ 3.20 GHz,i3-550,Discontinued,Q2'10,2,4,3.20 GHz,notFound,notFound
Intel® Xeon® Processor E5-1428L v3 20M Cache/ 2.00 GHz,E5-1428LV3,Launched,Q1'15,8,16,2.00 GHz,notFound,notFound
Intel® Xeon® Gold 6248 Processor 27.5M Cache/ 2.50 GHz,6248,Launched,Q2'19,20,40,2.50 GHz,3.90 GHz,notFound
Intel® Xeon® Processor E3-1240L v3 8M Cache/ 2.00 GHz,E3-1240LV3,Discontinued,Q2'14,4,8,2.00 GHz,3.00 GHz,3.00 GHz
Intel® Core™ Duo Processor T2400 2M Cache/ 1.83 GHz/ 667 MHz FSB,T2400,Discontinued,notFound,2,notFound,1.83 GHz,notFound,notFound
Intel® Celeron® Processor U3405 2M Cache/ 1.07 GHz,U3405,Discontinued,Q1'10,2,2,1.06 GHz,notFound,notFound
Intel® Pentium® Processor G3430 3M Cache/ 3.30 GHz,G3430,Discontinued,Q3'13,2,2,3.30 GHz,notFound,notFound
Intel® Xeon® Processor E3-1280 v5 8M Cache/ 3.70 GHz,E3-1280V5,Discontinued,Q4'15,4,8,3.70 GHz,4.00 GHz,4.00 GHz
Intel® Pentium® 4 Processor 530/530J supporting HT Technology 1M Cache/ 3.00 GHz/ 800 MHz FSB,530,Discontinued,Q2'04,1,notFound,3.00 GHz,notFound,notFound
Intel® Core™ i7-920XM Processor Extreme Edition 8M Cache/ 2.00 GHz,i7-920XM,Discontinued,Q3'09,4,8,2.00 GHz,3.20 GHz,notFound
Intel® Pentium® Processor B925C 4M Cache/ 2.00 GHz,B925C,Launched,Q4'13,2,4,2.00 GHz,notFound,notFound
Intel® Celeron® Processor G1820 2M Cache/ 2.70 GHz,G1820,Launched,Q1'14,2,2,2.70 GHz,notFound,notFound
Intel® Core™ i3-8145UE Processor 4M Cache/ up to 3.90 GHz,i3-8145UE,Launched,Q2'19,2,4,2.20 GHz,3.90 GHz,3.90 GHz
Intel® Core™ i5-2467M Processor 3M Cache/ up to 2.30 GHz,i5-2467M,Discontinued,Q2'11,2,4,1.60 GHz,2.30 GHz,2.30 GHz
Intel® Xeon® W-3275 Processor 38.5M Cache/ 2.50 GHz,W-3275,Launched,Q2'19,28,56,2.50 GHz,4.40 GHz,notFound
Intel® Celeron® Processor G5900 2M Cache/ 3.40 GHz,G5900,Launched,Q2'20,2,2,3.40 GHz,notFound,notFound
Intel® Core™ i5-6400 Processor 6M Cache/ up to 3.30 GHz,i5-6400,Discontinued,Q3'15,4,4,2.70 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® Processor E3-1268L v5 8M Cache/ 2.40 GHz,E3-1268LV5,Launched,Q4'15,4,8,2.40 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i3-6098P Processor 3M Cache/ 3.60 GHz,i3-6098P,Discontinued,Q4'15,2,4,3.60 GHz,notFound,notFound
Intel® Pentium® Processor G4500T 3M Cache/ 3.00 GHz,G4500T,Discontinued,Q3'15,2,2,3.00 GHz,notFound,notFound
Intel® Xeon® Processor E3-1505M v5 8M Cache/ 2.80 GHz,E3-1505MV5,Launched,Q3'15,4,8,2.80 GHz,3.70 GHz,3.70 GHz
Intel® Celeron® Processor 440 512K Cache/ 2.00 GHz/ 800 MHz FSB,440,Discontinued,Q3'06,1,notFound,2.00 GHz,notFound,notFound
Intel® Xeon® Processor E5640 12M Cache/ 2.66 GHz/ 5.86 GT/s Intel® QPI,E5640,Discontinued,Q1'10,4,8,2.66 GHz,2.93 GHz,notFound
Intel Atom® Processor Z2580 1M Cache/ 2.00 GHz,Z2580,Discontinued,Q2'13,2,4,notFound,notFound,notFound
Intel® Xeon® Processor E3-1545M v5 8M Cache/ 2.90 GHz,E3-1545MV5,Launched,Q1'16,4,8,2.90 GHz,3.80 GHz,3.80 GHz
Intel® Pentium® 4 Processor 516 1M Cache/ 2.93 GHz/ 533 MHz FSB,516,Discontinued,Q4'05,1,notFound,2.93 GHz,notFound,notFound
Intel® Xeon® Platinum 8276 Processor 38.5M Cache/ 2.20 GHz,8276,Launched,Q2'19,28,56,2.20 GHz,4.00 GHz,notFound
Intel® Core™ i7-3632QM Processor 6M Cache/ up to 3.20 GHz BGA,i7-3632QM,Discontinued,Q3'12,4,8,2.20 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® E-2286G Processor 12M Cache/ 4.00 GHz,E-2286G,Launched,Q2'19,6,12,4.00 GHz,4.90 GHz,4.90 GHz
Intel® Core™ i7-6850K Processor 15M Cache/ up to 3.80 GHz,i7-6850K,Discontinued,Q2'16,6,12,3.60 GHz,3.80 GHz,notFound
Intel® Xeon® Processor E5630 12M Cache/ 2.53 GHz/ 5.86 GT/s Intel® QPI,E5630,Discontinued,Q1'10,4,8,2.53 GHz,2.80 GHz,notFound
Intel® Core™2 Duo Processor T8300 3M Cache/ 2.40 GHz/ 800 MHz FSB,T8300,Discontinued,Q1'08,2,notFound,2.40 GHz,notFound,notFound
Intel Atom® x5-Z8350 Processor 2M Cache/ up to 1.92 GHz,x5-Z8350,Launched,Q1'16,4,notFound,1.44 GHz,notFound,notFound
Intel® Xeon® Processor E3-1105C v2 8M Cache/ 1.80 GHz,E3-1105CV2,Launched,Q3'13,4,8,1.80 GHz,notFound,notFound
Intel® Xeon® Processor X7460 16M Cache/ 2.66 GHz/ 1066 MHz FSB,X7460,Discontinued,Q3'08,6,notFound,2.66 GHz,notFound,notFound
Intel® Xeon® Gold 6240Y Processor 24.75M Cache/ 2.60 GHz,6240Y,Launched,Q2'19,18,36,2.60 GHz,3.90 GHz,notFound
Intel® Core™ i7-4960X Processor Extreme Edition 15M Cache/ up to 4.00 GHz,i7-4960X,Discontinued,Q3'13,6,12,3.60 GHz,4.00 GHz,4.00 GHz
Intel® Pentium® Silver N5030 Processor 4M Cache/ up to 3.10 GHz,N5030,Launched,Q4'19,4,4,1.10 GHz,notFound,notFound
Intel® Core™ m3-7Y32 Processor 4M Cache/ up to 3.00 GHz,M3-7Y32,Launched,Q2'17,2,4,1.10 GHz,3.00 GHz,3.00 GHz
Intel® Core™2 Duo Processor T5670 2M Cache/ 1.80 GHz/ 800 MHz FSB,T5670,Discontinued,Q2'08,2,notFound,1.80 GHz,notFound,notFound
Intel® Xeon® Processor E7530 12M Cache/ 1.86 GHz/ 5.86 GT/s Intel® QPI,E7530,Discontinued,Q1'10,6,12,1.87 GHz,2.13 GHz,notFound
Intel® Xeon® W-3345 Processor 36M Cache/ up to 4.00 GHz,W-3345,Launched,Q3'21,24,48,3.00 GHz,4.00 GHz,notFound
Intel® Xeon® Processor E5506 4M Cache/ 2.13 GHz/ 4.80 GT/s Intel® QPI,E5506,Discontinued,Q1'09,4,4,2.13 GHz,notFound,notFound
Intel® Pentium® 4 Processor 511 1M Cache/ 2.80 GHz/ 533 MHz FSB,511,Discontinued,Q4'05,1,notFound,2.80 GHz,notFound,notFound
Intel® Core™ i5-5250U Processor 3M Cache/ up to 2.70 GHz,i5-5250U,Discontinued,Q1'15,2,4,1.60 GHz,2.70 GHz,2.70 GHz
Intel® Core™ i5-5250U Processor 3M Cache/ up to 2.70 GHz,i5-5250U,Discontinued,Q1'15,2,4,1.60 GHz,2.70 GHz,2.70 GHz
Intel® Pentium® M Processor LV 738 2M Cache/ 1.40 GHz/ 400 MHz FSB,738,Discontinued,Q2'04,1,notFound,1.40 GHz,notFound,notFound
Intel® Pentium® Silver N6000 Processor 4M Cache/ up to 3.30 GHz,N6000,Launched,Q1'21,4,4,1.10 GHz,notFound,notFound
Intel® Celeron® Processor J3455E 2M Cache/ up to 2.30 GHz,J3455E,Discontinued,Q3'19,4,4,1.50 GHz,2.30 GHz,notFound
Intel Atom® Processor N280 512K Cache/ 1.66 GHz/ 667 MHz FSB,N280,Discontinued,Q1'09,1,notFound,1.66 GHz,notFound,notFound
Intel® Xeon® Silver 4208 Processor 11M Cache/ 2.10 GHz,4208,Launched,Q2'19,8,16,2.10 GHz,3.20 GHz,notFound
Intel® Core™ i3-4100E Processor 3M Cache/ 2.40 GHz,i3-4100E,Launched,Q3'13,2,4,2.40 GHz,notFound,notFound
Intel® Celeron® Processor N3060 2M Cache/ up to 2.48 GHz,N3060,Launched,Q1'16,2,2,1.60 GHz,notFound,notFound
Intel® Core™2 Duo Processor E8190 6M Cache/ 2.66 GHz/ 1333 MHz FSB,E8190,Discontinued,Q1'08,2,notFound,2.66 GHz,notFound,notFound
Intel® Xeon® Processor E7-2870 v2 30M Cache/ 2.30 GHz,E7-2870V2,Launched,Q1'14,15,30,2.30 GHz,2.90 GHz,2.90 GHz
Intel Atom® Processor E660T 512K Cache/ 1.30 GHz,E660T,Discontinued,Q3'10,1,2,1.30 GHz,notFound,notFound
Intel® Xeon® Processor E5-2650 20M Cache/ 2.00 GHz/ 8.00 GT/s Intel® QPI,E5-2650,Discontinued,Q1'12,8,16,2.00 GHz,2.80 GHz,2.80 GHz
Intel® Itanium® Processor 9120N 12M Cache/ 1.42 GHz/ 533 MHz FSB,9120N,Discontinued,Q4'07,2,notFound,1.42 GHz,notFound,notFound
Intel® Celeron® Processor E1500 512K Cache/ 2.20 GHz/ 800 MHz FSB,E1500,Discontinued,Q3'06,2,notFound,2.20 GHz,notFound,notFound
Intel® Xeon® Processor D-1531 9M Cache/ 2.20 GHz,D-1531,Launched,Q4'15,6,12,2.20 GHz,2.70 GHz,2.70 GHz
Intel® Core™2 Extreme Processor X6800 4M Cache/ 2.93 GHz/ 1066 MHz FSB,X6800,Discontinued,Q3'06,2,notFound,2.93 GHz,notFound,notFound
Intel® Core™ i5-3427U Processor 3M Cache/ up to 2.80 GHz,i5-3427U,Discontinued,Q2'12,2,4,1.80 GHz,2.80 GHz,2.80 GHz
Intel® Core™ i5-3427U Processor 3M Cache/ up to 2.80 GHz,i5-3427U,Discontinued,Q2'12,2,4,1.80 GHz,2.80 GHz,2.80 GHz
Intel Atom® x3-C3405 Processor 1M Cache/ up to 1.40 GHz,x3-C3405,Announced,Q1'15,4,notFound,1.20 GHz,notFound,notFound
Intel Atom® Processor C2316 1M Cache/ 1.50 GHz,C2316,Launched,Q3'17,2,2,1.50 GHz,notFound,notFound
Intel® Core™ i5-8400B Processor 9M Cache/ up to 4.00 GHz,i5-8400B,Discontinued,Q2'18,6,6,2.80 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i7-1160G7 Processor 12M Cache/ up to 4.40 GHz/ with IPU,i7-1160G7,Launched,Q3'20,4,8,notFound,4.40 GHz,notFound
Intel® Celeron® Processor G3900 2M Cache/ 2.80 GHz,G3900,Launched,Q4'15,2,2,2.80 GHz,notFound,notFound
Intel® Xeon® Processor E5-2630 v3 20M Cache/ 2.40 GHz,E5-2630V3,Discontinued,Q3'14,8,16,2.40 GHz,3.20 GHz,3.20 GHz
Intel Atom® Processor C2718 4M Cache/ 2.00 GHz,C2718,Launched,Q3'13,8,8,2.00 GHz,notFound,notFound
Intel® Xeon® Processor E7-8880 v4 55M Cache/ 2.20 GHz,E7-8880V4,Launched,Q2'16,22,44,2.20 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i5-1140G7 Processor 8M Cache/ up to 4.20 GHz/ with IPU,i5-1140G7,Launched,Q1'21,4,8,notFound,4.20 GHz,notFound
Intel® Xeon® Platinum 9282 Processor 77M Cache/ 2.60 GHz,9282,Launched,Q2'19,56,112,2.60 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Platinum 8354H Processor 24.75M Cache/ 3.10 GHz,8354H,Launched,Q2'20,18,36,3.10 GHz,4.30 GHz,notFound
Intel® Xeon® Processor E5-2665 20M Cache/ 2.40 GHz/ 8.00 GT/s Intel® QPI,E5-2665,Discontinued,Q1'12,8,16,2.40 GHz,3.10 GHz,3.10 GHz
Intel® Core™ i3-9100E Processor 6M Cache/ up to 3.70 GHz,i3-9100E,Launched,Q2'19,4,4,3.10 GHz,3.70 GHz,3.70 GHz
Intel® Itanium® Processor 9140N 18M Cache/ 1.60 GHz/ 533 MHz FSB,9140N,Discontinued,Q4'07,2,notFound,1.60 GHz,notFound,notFound
Intel® Core™2 Duo Processor P8700 3M Cache/ 2.53 GHz/ 1066 MHz FSB,P8700,Discontinued,Q4'08,2,notFound,2.53 GHz,notFound,notFound
Intel Atom® Processor E620 512K Cache/ 600 MHz,E620,Discontinued,Q3'10,1,2,600 MHz,notFound,notFound
Intel® Pentium® Processor G3250 3M Cache/ 3.20 GHz,G3250,Discontinued,Q3'14,2,2,3.20 GHz,notFound,notFound
Intel® Core™2 Duo Processor T9600 6M Cache/ 2.80 GHz/ 1066 MHz FSB,T9600,Discontinued,Q3'08,2,notFound,2.80 GHz,notFound,notFound
Intel® Core™ i7-8569U Processor 8M Cache/ up to 4.70 GHz,i7-8569U,Launched,Q2'19,4,8,2.80 GHz,4.70 GHz,4.70 GHz
Intel® Pentium® Gold Processor 4417U 2M Cache/ 2.30 GHz,4417U,Launched,Q1'19,2,4,2.30 GHz,notFound,notFound
Intel® Xeon® Processor E7-4830 v2 20M Cache/ 2.20 GHz,E7-4830V2,Discontinued,Q1'14,10,20,2.20 GHz,2.70 GHz,2.70 GHz
Intel® Pentium® Processor T2370 1M Cache/ 1.73 GHz/ 533 MHz FSB,T2370,Discontinued,Q1'08,2,notFound,1.73 GHz,notFound,notFound
Intel Atom® Processor D410 512K Cache/ 1.66 GHz,D410,Discontinued,Q1'10,1,2,1.66 GHz,notFound,notFound
Intel® Xeon® Gold 5218N Processor 22M Cache/ 2.30 GHz,5218N,Launched,Q2'19,16,32,2.30 GHz,3.70 GHz,notFound
Intel® Core™ i3-4102E Processor 3M Cache/ 1.60 GHz,i3-4102E,Launched,Q3'13,2,4,1.60 GHz,notFound,notFound
Intel® Xeon® Processor E7-8891 v4 60M Cache/ 2.80 GHz,E7-8891V4,Launched,Q2'16,10,20,2.80 GHz,3.50 GHz,3.50 GHz
Intel® Core™ i7-9700F Processor 12M Cache/ up to 4.70 GHz,i7-9700F,Launched,Q2'19,8,8,3.00 GHz,4.70 GHz,4.70 GHz
Intel® Core™ i5-4308U Processor 3M Cache/ up to 3.30 GHz,i5-4308U,Discontinued,Q3'14,2,4,2.80 GHz,3.30 GHz,3.30 GHz
Intel® Xeon® Gold 6230T Processor 27.5M Cache/ 2.10 GHz,6230T,Launched,Q2'19,20,40,2.10 GHz,3.90 GHz,notFound
Intel® Xeon® Processor E5-2618L v3 20M Cache/ 2.30 GHz,E5-2618LV3,Launched,Q3'14,8,16,2.30 GHz,3.40 GHz,3.40 GHz
Intel Atom® Processor C2558 2M Cache/ 2.40 GHz,C2558,Launched,Q3'13,4,4,2.40 GHz,notFound,notFound
Intel® Core™2 Duo Processor E6420 4M Cache/ 2.13 GHz/ 1066 MHz FSB,E6420,Discontinued,Q2'07,2,notFound,2.13 GHz,notFound,notFound
Intel Atom® Processor C2350 1M Cache/ 1.70 GHz,C2350,Launched,Q3'13,2,2,1.70 GHz,2.00 GHz,2.00 GHz
Intel® Xeon® Platinum 8358P Processor 48M Cache/ 2.60 GHz,8358P,Launched,Q2'21,32,64,2.60 GHz,3.40 GHz,notFound
Intel Atom® Processor C2516 2M Cache/ 1.40 GHz,C2516,Launched,Q3'17,4,4,1.40 GHz,notFound,notFound
Intel® Celeron® M Processor ULV 722 1M Cache/ 1.20 GHz/ 800 MHz FSB,722,Discontinued,Q3'08,1,notFound,1.20 GHz,notFound,notFound
Intel® Core™2 Duo Processor L7200 4M Cache/ 1.33 GHz/ 667 MHz FSB,L7200,Discontinued,Q1'07,2,notFound,1.33 GHz,notFound,notFound
Intel® Celeron® Processor G460 1.5M Cache/ 1.80 GHz,G460,Discontinued,Q4'11,1,2,1.80 GHz,notFound,notFound
Intel® Xeon® Processor D-1548 12M Cache/ 2.00 GHz,D-1548,Launched,Q4'15,8,16,2.00 GHz,2.60 GHz,2.60 GHz
Intel® Xeon® Processor E5-4610 v2 16M Cache/ 2.30 GHz,E5-4610V2,Discontinued,Q1'14,8,16,2.30 GHz,2.70 GHz,2.70 GHz
Intel® Xeon® Processor E7-8850 24M Cache/ 2.00 GHz/ 6.40 GT/s Intel® QPI,E7-8850,Discontinued,Q2'11,10,20,2.00 GHz,2.40 GHz,notFound
Intel Atom® Processor C3850 12M Cache/ up to 2.40 GHz,C3850,Launched,Q3'17,12,12,2.10 GHz,2.40 GHz,2.40 GHz
Intel® Celeron® Processor T3300 1M Cache/ 2.00 GHz/ 800 MHz FSB,T3300,Discontinued,Q1'10,2,notFound,2.00 GHz,notFound,notFound
Intel® Celeron® Processor G1620 2M Cache/ 2.70 GHz,G1620,Launched,Q1'13,2,2,2.70 GHz,notFound,notFound
Intel® Xeon® Processor E5-2637 v3 15M Cache/ 3.50 GHz,E5-2637V3,Discontinued,Q3'14,4,8,3.50 GHz,3.70 GHz,3.70 GHz
Intel® Core™ i3-9300 Processor 8M Cache/ up to 4.30 GHz,i3-9300,Launched,Q2'19,4,4,3.70 GHz,4.30 GHz,4.30 GHz
Intel® Core™ i7-4760HQ Processor 6M Cache/ up to 3.30 GHz,i7-4760HQ,Discontinued,Q2'14,4,8,2.10 GHz,3.30 GHz,3.30 GHz
Intel® Core™ i7-3537U Processor 4M Cache/ up to 3.10 GHz,i7-3537U,Discontinued,Q1'13,2,4,2.00 GHz,3.10 GHz,3.10 GHz
Intel® Core™2 Duo Processor T7400 4M Cache/ 2.16 GHz/ 667 MHz FSB,T7400,Discontinued,Q3'06,2,notFound,2.16 GHz,notFound,notFound
Intel® Core™ i5-4570 Processor 6M Cache/ up to 3.60 GHz,i5-4570,Discontinued,Q2'13,4,4,3.20 GHz,3.60 GHz,3.60 GHz
Intel® Core™2 Duo Processor U7500 2M Cache/ 1.06 GHz/ 533 MHz FSB Socket P,U7500,Discontinued,Q3'06,2,notFound,1.06 GHz,notFound,notFound
Intel® Core™ i3-7100E Processor 3M Cache/ 2.90 GHz,i3-7100E,Launched,Q1'17,2,4,2.90 GHz,notFound,notFound
Intel® Xeon® Gold 6148F Processor 27.5M Cache/ 2.40 GHz,6148F,Launched,Q3'17,20,40,2.40 GHz,3.70 GHz,notFound
Intel Atom® Processor E680T 512K Cache/ 1.60 GHz,E680T,Discontinued,Q3'10,1,2,1.60 GHz,notFound,notFound
Intel® Celeron® G4920 Processor 2M Cache/ 3.20 GHz,G4920,Discontinued,Q2'18,2,2,3.20 GHz,notFound,notFound
Intel® Core™ i7-740QM Processor 6M cache/ 1.73 GHz,i7-740QM,Discontinued,Q3'10,4,8,1.73 GHz,2.93 GHz,notFound
Intel® Pentium® Processor G3260T 3M Cache/ 2.90 GHz,G3260T,Discontinued,Q1'15,2,2,2.90 GHz,notFound,notFound
Intel® Xeon® Gold 6140 Processor 24.75M Cache/ 2.30 GHz,6140,Discontinued,Q3'17,18,36,2.30 GHz,3.70 GHz,notFound
Intel® Core™ i5-4570S Processor 6M Cache/ up to 3.60 GHz,i5-4570S,Launched,Q2'13,4,4,2.90 GHz,3.60 GHz,3.60 GHz
Intel® Core™2 Duo Processor E6700 4M Cache/ 2.66 GHz/ 1066 MHz FSB,E6700,Discontinued,Q3'06,2,notFound,2.66 GHz,notFound,notFound
Intel Atom® Processor C2518 2M Cache/ 1.70 GHz,C2518,Launched,Q3'13,4,4,1.70 GHz,notFound,notFound
Intel® Core™ i7-4710MQ Processor 6M Cache/ up to 3.50 GHz,i7-4710MQ,Discontinued,Q2'14,4,8,2.50 GHz,3.50 GHz,3.50 GHz
Intel® Celeron® Processor G1610T 2M Cache/ 2.30 GHz,G1610T,Discontinued,Q1'13,2,2,2.30 GHz,notFound,notFound
Intel® Core™ i3-9300T Processor 8M Cache/ up to 3.80 GHz,i3-9300T,Launched,Q2'19,4,4,3.20 GHz,3.80 GHz,3.80 GHz
Intel® Xeon® Processor E7-8860 24M Cache/ 2.26 GHz/ 6.40 GT/s Intel® QPI,E7-8860,Discontinued,Q2'11,10,20,2.26 GHz,2.67 GHz,notFound
Intel Atom® Processor C3308 4M Cache/ up to 2.10 GHz,C3308,Launched,Q3'17,2,2,1.60 GHz,2.10 GHz,2.10 GHz
Intel® Xeon® Gold 6128 Processor 19.25M Cache/ 3.40 GHz,6128,Launched,Q3'17,6,12,3.40 GHz,3.70 GHz,notFound
Intel® Xeon® Processor E7-4860 v2 30M Cache/ 2.60 GHz,E7-4860V2,Launched,Q1'14,12,24,2.60 GHz,3.20 GHz,3.20 GHz
Intel® Xeon® W-2175 Processor 19.25M Cache/ 2.50 GHz,W-2175,Launched,Q3'17,14,28,2.50 GHz,4.30 GHz,notFound
Intel® Core™ i5-430UM Processor 3M cache/ 1.20 GHz,i5-430UM,Discontinued,Q2'10,2,4,1.20 GHz,1.73 GHz,notFound
Intel® Core™ i7-6650U Processor 4M Cache/ up to 3.40 GHz,i7-6650U,Discontinued,Q3'15,2,4,2.20 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i5-1130G7 Processor 8M Cache/ up to 4.00 GHz/ with IPU,i5-1130G7,Launched,Q3'20,4,8,notFound,4.00 GHz,notFound
Intel® Core™2 Duo Processor U7600 2M Cache/ 1.20 GHz/ 533 MHz FSB Socket P,U7600,Discontinued,Q2'07,2,notFound,1.20 GHz,notFound,notFound
Intel® Xeon® Gold 6138 Processor 27.5M Cache/ 2.00 GHz,6138,Launched,Q3'17,20,40,2.00 GHz,3.70 GHz,notFound
Intel® Xeon® E-2386G Processor 12M Cache/ 3.50 GHz,E-2386G,Launched,Q3'21,6,12,3.50 GHz,5.10 GHz,5.10 GHz
Intel Atom® x5-Z8550 Processor 2M Cache/ up to 2.40 GHz,x5-Z8550,Launched,Q1'16,4,notFound,1.44 GHz,notFound,notFound
Intel® Xeon® Processor E3-1220 8M Cache/ 3.10 GHz,E3-1220,Discontinued,Q2'11,4,4,3.10 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i3-4330TE Processor 4M Cache/ 2.40 GHz,i3-4330TE,Launched,Q3'13,2,4,2.40 GHz,notFound,notFound
Intel® Celeron® Processor N4120 4M Cache/ up to 2.60 GHz,N4120,Launched,Q4'19,4,4,1.10 GHz,notFound,notFound
Intel® Xeon® Processor E5620 12M Cache/ 2.40 GHz/ 5.86 GT/s Intel® QPI,E5620,Discontinued,Q1'10,4,8,2.40 GHz,2.66 GHz,notFound
Intel® Xeon® W-3335 Processor 24M Cache/ up to 4.00 GHz,W-3335,Launched,Q3'21,16,32,3.40 GHz,4.00 GHz,notFound
Intel® Xeon® Platinum 8260L Processor 35.75M Cache/ 2.40 GHz,8260L,Launched,Q2'19,24,48,2.40 GHz,3.90 GHz,notFound
Intel Atom® Processor C3338R 4M Cache/ up to 2.20 GHz,C3338R,Launched,Q2'20,2,2,1.80 GHz,2.20 GHz,2.20 GHz
Intel® Xeon® Processor E7520 18M Cache/ 1.86 GHz/ 4.80 GT/s Intel® QPI,E7520,Discontinued,Q1'10,4,8,1.87 GHz,1.87 GHz,notFound
Intel® Core™ i5-7260U Processor 4M Cache/ up to 3.40 GHz,i5-7260U,Launched,Q1'17,2,4,2.20 GHz,3.40 GHz,3.40 GHz
Intel® Core™ i5-7260U Processor 4M Cache/ up to 3.40 GHz,i5-7260U,Launched,Q1'17,2,4,2.20 GHz,3.40 GHz,3.40 GHz
Intel® Xeon® Platinum 8270 Processor 35.75M Cache/ 2.70 GHz,8270,Launched,Q2'19,26,52,2.70 GHz,4.00 GHz,notFound
Intel® Pentium® Processor T4200 1M Cache/ 2.00 GHz/ 800 MHz FSB,T4200,Discontinued,Q1'09,2,notFound,2.00 GHz,notFound,notFound
Intel® Xeon® E-2276G Processor 12M Cache/ 3.80 GHz,E-2276G,Launched,Q2'19,6,12,3.80 GHz,4.90 GHz,4.90 GHz
Intel Atom® Processor Z3570 2M Cache/ up to 2.00 GHz,Z3570,Discontinued,Q3'14,4,notFound,notFound,notFound,notFound
Intel® Xeon® Processor X5650 12M Cache/ 2.66 GHz/ 6.40 GT/s Intel® QPI,X5650,Discontinued,Q1'10,6,12,2.66 GHz,3.06 GHz,notFound
Intel® Xeon® Processor E7450 12M Cache/ 2.40 GHz/ 1066 MHz FSB,E7450,Discontinued,Q3'08,6,notFound,2.40 GHz,notFound,notFound
Intel® Xeon® Processor E5-2658 20M/ 2.10 GHz/ 8.0 GT/s Intel® QPI,E5-2658,Discontinued,Q1'12,8,16,2.10 GHz,2.40 GHz,2.40 GHz
Intel® Pentium® Processor G4400 3M Cache/ 3.30 GHz,G4400,Launched,Q3'15,2,2,3.30 GHz,notFound,notFound
Intel® Core™ i5-4250U Processor 3M Cache/ up to 2.60 GHz,i5-4250U,Discontinued,Q3'13,2,4,1.30 GHz,2.60 GHz,2.60 GHz
Intel® Core™ i5-4250U Processor 3M Cache/ up to 2.60 GHz,i5-4250U,Discontinued,Q3'13,2,4,1.30 GHz,2.60 GHz,2.60 GHz
Intel® Core™ i7-6800K Processor 15M Cache/ up to 3.60 GHz,i7-6800K,Discontinued,Q2'16,6,12,3.40 GHz,3.60 GHz,notFound
Intel® Xeon® Processor X7542 18M Cache/ 2.66 GHz/ 5.86 GT/s Intel® QPI,X7542,Discontinued,Q1'10,6,notFound,2.67 GHz,2.80 GHz,notFound
Intel Atom® Processor Z2560 1M Cache/ 1.60 GHz,Z2560,Discontinued,Q2'13,2,4,notFound,notFound,notFound
Intel® Xeon® Processor E3-1515M v5 8M Cache/ 2.80 GHz,E3-1515MV5,Launched,Q1'16,4,8,2.80 GHz,3.70 GHz,3.70 GHz
Intel® Pentium® 4 Processor 515/515J 1M Cache/ 2.93 GHz/ 533 MHz FSB,515,Discontinued,Q3'05,1,notFound,2.93 GHz,notFound,notFound
Intel® Xeon® W-3365 Processor 48M Cache/ up to 4.00 GHz,W-3365,Launched,Q3'21,32,64,2.70 GHz,4.00 GHz,notFound
Intel® Core™ i5-680 Processor 4M Cache/ 3.60 GHz,i5-680,Discontinued,Q2'10,2,4,3.60 GHz,3.86 GHz,notFound
Intel® Pentium® Processor E5800 2M Cache/ 3.20 GHz/ 800 MHz FSB,E5800,Discontinued,Q4'10,2,notFound,3.20 GHz,notFound,notFound
Intel® Core™ i7-7660U Processor 4M Cache/ up to 4.00 GHz,i7-7660U,Launched,Q1'17,2,4,2.50 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i7-10710U Processor 12M Cache/ up to 4.70 GHz,i7-10710U,Launched,Q3'19,6,12,1.10 GHz,4.70 GHz,notFound
Intel® Core™ i7-10710U Processor 12M Cache/ up to 4.70 GHz,i7-10710U,Launched,Q3'19,6,12,1.10 GHz,4.70 GHz,notFound
Intel® Xeon® Processor E3-1105C 6M Cache/ 1.00 GHz,E3-1105C,Discontinued,Q2'12,4,8,1.00 GHz,notFound,notFound
Intel® Core™ M-5Y10c Processor 4M Cache/ up to 2.00 GHz,5Y10c,Discontinued,Q4'14,2,4,800 MHz,2.00 GHz,2.00 GHz
Intel® Xeon® Platinum 8280 Processor 38.5M Cache/ 2.70 GHz,8280,Launched,Q2'19,28,56,2.70 GHz,4.00 GHz,notFound
Intel® Core™2 Duo Processor SP9600 6M Cache/ 2.53 GHz/ 1066 MHz FSB,SP9600,Discontinued,Q1'09,2,notFound,2.53 GHz,notFound,notFound
Intel® Xeon® W-3245 Processor 22M Cache/ 3.20 GHz,W-3245,Launched,Q2'19,16,32,3.20 GHz,4.40 GHz,notFound
Intel® Core™ i5-6500 Processor 6M Cache/ up to 3.60 GHz,i5-6500,Launched,Q3'15,4,4,3.20 GHz,3.60 GHz,3.60 GHz
Intel® Celeron® Processor 4305U 2M Cache/ 2.20 GHz,4305U,Launched,Q2'19,2,2,2.20 GHz,notFound,notFound
Intel® Pentium® Processor G3420T 3M Cache/ 2.70 GHz,G3420T,Discontinued,Q3'13,2,2,2.70 GHz,notFound,notFound
Intel Atom® Processor N550 1M Cache/ 1.50 GHz,N550,Discontinued,Q3'10,2,4,1.50 GHz,notFound,notFound
Intel® Xeon® Processor E3-1235L v5 8M Cache/ 2.00 GHz,E3-1235LV5,Launched,Q4'15,4,4,2.00 GHz,3.00 GHz,3.00 GHz
Intel® Celeron® Processor J4025 4M Cache/ up to 2.90 GHz,J4025,Launched,Q4'19,2,2,2.00 GHz,notFound,notFound
Intel® Xeon® Gold 6252 Processor 35.75M Cache/ 2.10 GHz,6252,Launched,Q2'19,24,48,2.10 GHz,3.70 GHz,notFound
Intel® Xeon® Processor E3-1286 v3 8M Cache/ 3.70 GHz,E3-1286V3,Discontinued,Q2'14,4,8,3.70 GHz,4.10 GHz,4.10 GHz
Intel® Celeron® Processor G1830 2M Cache/ 2.80 GHz,G1830,Discontinued,Q1'14,2,2,2.80 GHz,notFound,notFound
Intel® Xeon® Processor E3-1125C v2 8M Cache/ 2.50 GHz,E3-1125CV2,Launched,Q3'13,4,8,2.50 GHz,notFound,notFound
Intel® Core™ i7-940XM Processor Extreme Edition 8M Cache/ 2.13 GHz,i7-940XM,Discontinued,Q3'10,4,8,2.13 GHz,3.33 GHz,notFound
Intel® Pentium® 4 Processor 524 supporting HT Technology 1M Cache/ 3.06 GHz/ 533 MHz FSB,524,Discontinued,Q2'06,1,notFound,3.06 GHz,notFound,notFound
Intel® Core™ i3-8109U Processor 4M Cache/ up to 3.60 GHz,i3-8109U,Launched,Q2'18,2,4,3.00 GHz,3.60 GHz,3.60 GHz
Intel® Core™ i3-8109U Processor 4M Cache/ up to 3.60 GHz,i3-8109U,Launched,Q2'18,2,4,3.00 GHz,3.60 GHz,3.60 GHz
Intel® Xeon® Processor D-1567 18M Cache/ 2.10 GHz,D-1567,Launched,Q1'16,12,24,2.10 GHz,2.70 GHz,2.70 GHz
Intel® Xeon® Processor E5-2418L v3 15M Cache/ 2.00 GHz,E5-2418LV3,Launched,Q1'15,6,12,2.00 GHz,notFound,notFound
Intel® Pentium® Processor E6500 2M Cache/ 2.93 GHz/ 1066 FSB,E6500,Discontinued,Q1'08,2,notFound,2.93 GHz,notFound,notFound
Intel® Xeon® Processor X7560 24M Cache/ 2.26 GHz/ 6.40 GT/s Intel® QPI,X7560,Discontinued,Q1'10,8,16,2.27 GHz,2.67 GHz,notFound
Intel® Celeron® Processor T3100 1M Cache/ 1.90 GHz/ 800 MHz FSB,T3100,Discontinued,Q3'08,2,notFound,1.90 GHz,notFound,notFound
Intel® Core™ i5-8365UE Processor 6M Cache/ up to 4.10 GHz,i5-8365UE,Launched,Q2'19,4,8,1.60 GHz,4.10 GHz,notFound
Intel® Pentium® 4 Processor 531 supporting HT Technology 1M Cache/ 3.00 GHz/ 800 MHz FSB,531,Discontinued,Q2'04,1,notFound,3.00 GHz,notFound,notFound
Intel® Xeon® Gold 6242 Processor 22M Cache/ 2.80 GHz,6242,Launched,Q2'19,16,32,2.80 GHz,3.90 GHz,notFound
Intel® Xeon® Processor E5-2648L 20M/ 1.80 GHz/ 8.0 GT/s Intel® QPI,E5-2648L,Discontinued,Q1'12,8,16,1.80 GHz,2.10 GHz,2.10 GHz
Intel® Xeon® Processor E3-1286L v3 8M Cache/ 3.20 GHz,E3-1286LV3,Discontinued,Q2'14,4,8,3.20 GHz,4.00 GHz,4.00 GHz
Intel® Core™ i5-540M Processor 3M Cache/ 2.53 GHz,i5-540M,Discontinued,Q1'10,2,4,2.53 GHz,3.07 GHz,notFound
Intel® Core™ i3-4340 Processor 4M Cache/ 3.60 GHz,i3-4340,Discontinued,Q3'13,2,4,3.60 GHz,notFound,notFound
Intel® Xeon® Processor E3-1275 v5 8M Cache/ 3.60 GHz,E3-1275V5,Launched,Q4'15,4,8,3.60 GHz,4.00 GHz,4.00 GHz
Intel® Xeon® W-3275M Processor 38.5M Cache/ 2.50 GHz,W-3275M,Launched,Q2'19,28,56,2.50 GHz,4.40 GHz,notFound
Intel® Core™ i5-6500T Processor 6M Cache/ up to 3.10 GHz,i5-6500T,Discontinued,Q3'15,4,4,2.50 GHz,3.10 GHz,3.10 GHz
Intel® Xeon® Processor L5430 12M Cache/ 2.66 GHz/ 1333 MHz FSB,L5430,Discontinued,Q3'08,4,notFound,2.66 GHz,notFound,notFound
Intel® Pentium® Processor N3520 2M Cache/ up to 2.42 GHz,N3520,Discontinued,Q4'13,4,4,2.17 GHz,notFound,notFound
Intel® Pentium® Processor E2160 1M Cache/ 1.80 GHz/ 800 MHz FSB,E2160,Discontinued,Q3'06,2,notFound,1.80 GHz,notFound,notFound
END_TABLE


	@cpuLookupTable = split /\n/,$table;

	return;
}