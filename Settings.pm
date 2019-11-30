package Plugins::Cloudplay::Settings;

# Plugin to stream audio from Cloudplay streams
#
# Released under GNU General Public License version 2 (GPLv2)
# Written by Daniel Vijge
# See file LICENSE for full license details

use strict;
use base qw(Slim::Web::Settings);

use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Log;

use constant EXEC => 'youtube-dl';
use constant EXEC_OPTIONS_VERSION => '--version';
use constant EXEC_OPTIONS_UPDATE => '--update';

my $log   = logger('plugin.cloudplay');
my $prefs = preferences('plugin.cloudplay');
my $bin_path;

sub handler {
    my ($class, $client, $params, $callback, @args) = @_;

    findExec();

    my $exec = $bin_path . '/' . EXEC;
    my $exec_options = EXEC_OPTIONS_VERSION;
    $log->debug("Calling External command: $exec $exec_options");
    my $output = `$exec $exec_options`;

    if ($output) {
        $params->{'youtube-dl-version'} = $output;
    }

    return $callback->($client, $params, $class->SUPER::handler($client, $params), @args);

}

sub findExec {
    my %paths = Slim::Utils::Misc::getBinPaths();

    for my $path (%paths) {
        if (index($path, 'Cloudplay') != -1) {
            $log->debug("Use bin path " . $path);
            $bin_path = $path;
            return;
        }
    }
    $log->error("Error: Cannot find bin path for youtube-dl");
}

# Returns the name of the plugin. The real 
# string is specified in the strings.txt file.
sub name {
	return 'PLUGIN_CLOUDPLAY';
}

sub page {
    return 'plugins/cloudplay/settings/basic.html';
}

sub prefs {
    return (preferences('plugin.cloudplay'));
}

# Always end with a 1 to make Perl happy
1;
