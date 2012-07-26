# nagios-nimrod

Nagios check for Nimrod metrics

## Overview

This script is designed to retrieve metrics from a Nimrod server and process it as a Nagios check

## Installation

In your Nagios plugins directory run

<pre><code>git clone git://github.com/mbst/nagios-nimrod.git</code></pre>
It requires the JSON::XS Perl module in order to run as this will be processing JSON retrieved from Nimrod

### commands.cfg

In your commands.cfg file (or in a separate file if your nagios.cfg is set to read at the directory level for its configs:
<pre><code>define command{
        command_name    check_nimrod
        command_line    /usr/bin/perl /usr/lib/nagios/plugins/check_nimrod.pl   -H '$ARG1$' -u '$ARG2$' -p '$ARG3$' -P '$ARG4$' -l '$ARG5$' -e '$ARG6$' -j '$ARG7$' -t '$ARG8$' -W '$ARG11$' -w '$ARG9$' -c '$ARG10$'
}
</code></pre>
You may wish to change the number of parameters you expose based on the below parameter list.

### Example services.cfg
Below is an example of how you may implement a check:
<pre><code>define service{
        use                     generic-service
        host_name               [your_host_name]
        service_description     Content_Rate
        normal_check_interval   5
        max_check_attempts      3
        check_command           check_nimrod![nimrod_server]!none!none!80!requests!single_content_single_id/history/aggregate?percentiles=99&age=300000!percentiles:99th:gauge!threshold!6000!8000!5
}</code></pre>


### check_nimrod.pl

<pre><code>./check_nimrod.pl --help
Usage: check_nimrod [-h] [-L] [-T timeout] [-v] [-V] [-P port] -H hostname [-u username] [-p password] -l logName -e endpointName -j jobName -t type [-W window] -w <warning> -c <critical>

   Check Nimrod Metric via JSON Parser
-T (--timeout)      Timeout in seconds (default=660)
-H (--hostname)     Nimrod Host
-u (--username)     Nimrod Auth Username
-p (--password)     Nimrod Authentication password
-P (--port)         Nimrod Port (default=80)
-l (--logName)      Nimrod Log Name
-e (--endpointName) Nimrod Metric Name
-j (--jobName)      Nimrod JSON Value Name
-t (--type)         Nimrod Check Type
-W (--window)       Aggregate Time Window
-w (--warn)         Warning Value
-c (--crit)         Critical Value
-h (--help)         Help
-V (--version)      Program version
-v (--verbose)      Print some useful information
-L (--license)      Print license information</code></pre>
Optional parameters are in square brackets.