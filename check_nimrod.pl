#!/usr/bin/perl -w
use strict;
use LWP::UserAgent;
use JSON::XS;
use Switch;
use DateTime;
use Getopt::Long;

use lib '/usr/lib/nagios/plugins';
use utils qw(%ERRORS);

#
# Check Nimrod Metrics
#

my ($opt_timeout,$opt_license,$opt_version,$opt_help,$opt_verbose);
my ($opt_hostname,$opt_username,$opt_password,$opt_port,$opt_logName,$opt_endpointName,$opt_window,$opt_jobName,$opt_type,$opt_warn,$opt_crit);
my ($PROGNAME,$REVISION);
my ($state,$msg);
use constant DEFAULT_TIMEOUT            =>660;
use constant DEFAULT_PORT               =>80;

$ENV{'PATH'}='';
$ENV{'BASH_ENV'}='';
$ENV{'ENV'}='';
$PROGNAME = "check_nimrod";
$REVISION = "1.0";

my $arg_status = check_args();
if ($arg_status){
  print "ERROR: some arguments wrong\n";
  exit $ERRORS{"UNKNOWN"};
}

$SIG{'ALRM'} = sub {
  print ("ERROR: plugin timed out after $opt_timeout seconds \n");
  exit $ERRORS{"UNKNOWN"};
};

alarm($opt_timeout);



my @Names = split(/:/,$opt_jobName);
my $TYPE  = $ARGV[6];
my $WARN  = $ARGV[7];
my $CRIT = $ARGV[8];
my $ua = LWP::UserAgent->new;
my $QUERY = "";
if ($opt_type eq "alert") {
        $QUERY = "http://$opt_hostname:$opt_port/logs/$opt_logName/alerts/$opt_endpointName";

} else {
	$QUERY = "http://$opt_hostname:$opt_port/logs/$opt_logName/gauges/$opt_endpointName";
}
my $req = HTTP::Request->new( GET => $QUERY );
$req->authorization_basic( $opt_username, $opt_password );

$ua->timeout($opt_timeout);
my $res = $ua->request($req);

if ( $res->is_success ) {
  my $json = new JSON::XS;
  my $value = "";
  my $jobStatus = "";
  my $count = "";
  my $elapsed = "";
  my $obj = $json->decode( $res->content );
  if ($opt_type eq "alert") {
	if (defined($obj->{"alert"})){
		$jobStatus = $obj->{"alert"};
		$state = $ERRORS{'OK'};
	} else {
		$msg = sprintf("Unable to find job status");
		$state = $ERRORS{'UNKNOWN'};
                last;
	}
  } else {
    if (defined($obj->{"count"})){
	$count = $obj->{"count"};
    }
    foreach my $name (@Names) {
	if (defined($obj->{$name})) {
		$obj = $obj->{$name};
		$state = $ERRORS{'OK'};
	} else {
		$msg = sprintf("Unable to find object");
                $state = $ERRORS{'UNKNOWN'};
		last;
	}
    }
  }
  if ($state != $ERRORS{'UNKNOWN'}){
	if ($opt_type eq "alert") {
		$value = $jobStatus;
	} else {
		$value = int($obj / 1000);
	}
	switch ($opt_type){
   		case "threshold"        { threshold_check($value,$count) }
   	 	case "reverse"          { reverse_threshold_check($value) }
	        case "string"           { string_check($value) }
		case "alert"		{ alert_check($value) }
        	else  {  
			$msg = sprintf("invalid type");
			$state = $ERRORS{'UNKNOWN'};
			print_exit();
		}
  	}
  } else {
	print_exit()
  }


}
else {
  $msg = sprintf("FAILED TO OPEN URL: $QUERY");
  $state = $ERRORS{'WARNING'};
  print_exit()
}

sub alert_check {
	my $duration = "";
	my $end_epoch = "";
	my $val = "";
	my $jobStatus = $_[0];
	my $start_epoch = "";
	my @endpoints = split(/[.]/,$opt_endpointName);
	my $endpoint = $endpoints[0]. "." .$endpoints[1]. ".time.elapsed";
	my $URL = "http://$opt_hostname:$opt_port/logs/$opt_logName/gauges/$endpoint";
	my $ua = LWP::UserAgent->new;
	my $req = HTTP::Request->new( GET => $URL );
	$req->authorization_basic( $opt_username, $opt_password );
	$ua->timeout($opt_timeout);
	my $res = $ua->request($req);
	if ( $res->is_success ) {
  		my $json = new JSON::XS;
  		my $obj = $json->decode( $res->content );
		my $current_time = time;	
		$duration  = int($obj->{"gauge"} / (1000 * 60));
		$end_epoch = int($obj->{"timestamp"} / 1000);
		$val = int(($current_time - $end_epoch) / 60 );
		if ($jobStatus eq "FAILED") {
			$msg = sprintf("Job has FAILED. $val mins since last run. Duration was $duration mins");
			$state = $ERRORS{'CRITICAL'};
                	print_exit();
		}
	} else {
		if ($jobStatus eq "RUNNING") {
			$msg = sprintf("Job is RUNNING. It has not yet completed a successful run.");
			$state = $ERRORS{'WARNING'};
                        print_exit();
		} else {
			$msg = "$res->status_line";
			$state = $ERRORS{'UNKNOWN'};
			print_exit();
		}
		
	}
	if ($val < $opt_warn) {
		$msg = "Job is $jobStatus. $val mins since last run. Duration was $duration mins";
		$state = $ERRORS{'OK'};
                print_exit();
        } elsif (($val >= $opt_warn) && ($val < $opt_warn)) {
		$msg = "Job is $jobStatus. $val mins since last run. Duration was $duration mins";
                $state = $ERRORS{'WARNING'};
                print_exit();
        } else {
		$msg = "Job is $jobStatus. $val mins since last run. Duration was $duration mins";
                $state = $ERRORS{'WARNING'};
                print_exit();
        }
}

sub reverse_threshold_check {
	my ($val) = @_;
	my @vals = split(" ",$val);	
	$val = $vals[0];
	
	if ($val > $opt_warn) {
		print "OK Threshold of $val ms OK. Warning at $opt_warn ms";
		exit 0;
	} elsif (($val <= $opt_warn) && ($val > $opt_crit)) {
		print "WARNING Threshold of $val ms WARNING. Critical at $opt_crit ms";
		exit 1;	
	} else {
		print "CRITICAL Threshold of $val ms CRITICAL.";
		exit 2;
	}
}

sub threshold_check {
        my $val = $_[0];
	my $queries = $_[1];
	my $extra_info = "";
	if ($opt_window && $queries) {
		my $rate = ($queries / $opt_window);
		$rate = sprintf "%.2f", $rate;
		$extra_info = " Query rate is $rate";
	}
        if ($val < $opt_warn) {
                print "OK Threshold of $val ms OK. Warning at $opt_warn ms.$extra_info\n";
                exit 0;
        } elsif (($val >= $opt_warn) && ($val < $opt_crit)) {
                print "WARNING Threshold of $val ms WARNING. Critical at $opt_crit ms.$extra_info";
                exit 1;
        } else {
                print "CRITICAL Threshold of $val ms CRITICAL.$extra_info";
                exit 2;
        }
}

sub print_exit {
	print "$msg\n";
	exit $state;
}




#--------------------------------------------------------------------------
sub check_args {
#--------------------------------------------------------------------------
  Getopt::Long::Configure('bundling');
  GetOptions
        ("V"                    => \$opt_version,
         "version"              => \$opt_version,
         "L"                    => \$opt_license,
         "license"              => \$opt_license,
         "v"                    => \$opt_verbose,
         "verbose"              => \$opt_verbose,
         "h|?"                  => \$opt_help,
         "help"                 => \$opt_help,
         "T=i"                  => \$opt_timeout,
         "timeout=i"            => \$opt_timeout,
         "H=s"                  => \$opt_hostname,
         "hostname=s"           => \$opt_hostname,
	 "u=s"			=> \$opt_username,
	 "username=s"		=> \$opt_username,
	 "p=s"			=> \$opt_password,
	 "password=s"		=> \$opt_password,
         "P=i"                  => \$opt_port,
         "port=i"               => \$opt_port,
         "W=s"                  => \$opt_window,
         "window=s"             => \$opt_window,
	 "l=s"			=> \$opt_logName,
	 "logName=s"		=> \$opt_logName,
	 "e=s"			=> \$opt_endpointName,
	 "endpointName=s"	=> \$opt_endpointName,
	 "j=s"			=> \$opt_jobName,
	 "jobName=s"		=> \$opt_jobName,
	 "t=s"			=> \$opt_type,
	 "type=s"		=> \$opt_type,
         "w=s"                  => \$opt_warn,
         "warn=s"               => \$opt_warn,
         "c=s"                  => \$opt_crit,
         "crit=s"               => \$opt_crit,
         );

  if ($opt_license) {
    print_gpl($PROGNAME,$REVISION);
    exit $ERRORS{'OK'};
  }

  if ($opt_version) {
    print_revision($PROGNAME,$REVISION);
    exit $ERRORS{'OK'};
  }

  if ($opt_help) {
    print_help();
    exit $ERRORS{'OK'};
  }

  if ( ! defined($opt_hostname)){
    print "\nERROR: Hostname not defined\n\n";
    print_usage();
    exit $ERRORS{'UNKNOWN'};
  }

  if ( ! defined($opt_logName)){
    print "\nERROR: Log Name not defined\n\n";
    print_usage();
    exit $ERRORS{'UNKNOWN'};
  }

  if ( ! defined($opt_endpointName)){
    print "\nERROR: Endpoint Name not defined\n\n";
    print_usage();
    exit $ERRORS{'UNKNOWN'};
  }

  if ( ! defined($opt_jobName)){
    print "\nERROR: Job Name not defined\n\n";
    print_usage();
    exit $ERRORS{'UNKNOWN'};
  }

  if ( ! defined($opt_type)){
    print "\nERROR: Check Type not defined\n\n";
    print_usage();
    exit $ERRORS{'UNKNOWN'};
  }


  unless ((defined $opt_username) && (defined $opt_password)) {
    $opt_username = "none";
    $opt_password = "none";
  }

  unless (defined $opt_warn) {
    print "\nERROR: parameter -w <warn> not defined\n\n";
    print_usage();
    exit ($ERRORS{'UNKNOWN'});
  }

  unless (defined $opt_crit) {
    print "\nERROR: parameter -c <crit> not defined\n\n";
    print_usage();
    exit ($ERRORS{'UNKNOWN'});
  }

  if ( $opt_warn > $opt_crit) {
    print "\nERROR: parameter -w <warn> greater than parameter -c\n\n";
    print_usage();
    exit ($ERRORS{'UNKNOWN'});
  }

  unless (defined $opt_timeout) {
    $opt_timeout = DEFAULT_TIMEOUT;
  }

  unless (defined $opt_port) {
    $opt_port = DEFAULT_PORT;
  }


  return $ERRORS{'OK'};
}


#--------------------------------------------------------------------------
sub print_usage {
#--------------------------------------------------------------------------
  print "Usage: $PROGNAME [-h] [-L] [-T timeout] [-v] [-V] [-P port] -H hostname -u username -p password -l logName -e endpointName -j jobName -t type [-W timewindow] -w <warning> -c <critical>\n\n";
}

#--------------------------------------------------------------------------
sub print_help {
#--------------------------------------------------------------------------
  print_revision($PROGNAME,$REVISION);
  printf("\n");
  print_usage();
  printf("\n");
  printf("   Check Nimrod Metric via JSON Parser\n");
  printf("-T (--timeout)      Timeout in seconds (default=%d)\n",DEFAULT_TIMEOUT);
  printf("-H (--hostname)     Nimrod Host\n");
  printf("-u (--username)     Nimrod Auth Username\n");
  printf("-p (--password)     Nimrod Authentication password\n");
  printf("-P (--port)         Nimrod Port (default=%d)\n",DEFAULT_PORT);
  printf("-l (--logName)      Nimrod Log Name\n");
  printf("-e (--endpointName) Nimrod Metric Name\n");
  printf("-j (--jobName)      Nimrod JSON Value Name\n");
  printf("-t (--type)         Nimrod Check Type\n");
  printf("-W (--window)       Aggregate Time Window\n");
  printf("-w (--warn)         Warning Value\n");
  printf("-c (--crit)         Critical Value\n");
  printf("-h (--help)         Help\n");
  printf("-V (--version)      Program version\n");
  printf("-v (--verbose)      Print some useful information\n");
  printf("-L (--license)      Print license information\n");
  printf("\n");
}

#--------------------------------------------------------------------------
sub print_gpl {
#--------------------------------------------------------------------------
  print <<EOD;

  Copyright (C) 2012 MetaBroadcast

  Permission is hereby granted, free of charge, to any person obtaining a copy of this software 
  and associated documentation files (the "Software"), to deal in the Software without restriction, 
  including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, 
  and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, 
  subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all copies
  or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT 
  NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

EOD

}

#--------------------------------------------------------------------------
sub print_revision {
#--------------------------------------------------------------------------
  my ($l_prog,$l_revision)=@_;

  print <<EOD

$l_prog $l_revision, Copyright (C) 2012 MetaBroadcast

This program comes with ABSOLUTELY NO WARRANTY; 
for details type "$l_prog -L".
EOD
}

