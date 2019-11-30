package Plugins::Cloudplay::Plugin;

# Plugin to stream audio from various different websites
#
# Released under GNU General Public License version 2 (GPLv2)
# Written by Daniel Vijge
# See file LICENSE for full license details

use strict;
use utf8;

use vars qw(@ISA);

use URI::Escape;
use JSON::XS::VersionOneAndTwo;
use LWP::Simple;
use LWP::UserAgent;
use File::Spec::Functions qw(:ALL);
use List::Util qw(min max);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;

use Plugins::Cloudplay::ProtocolHandler;

use constant EXEC => 'youtube-dl';
use constant EXEC_OPTIONS => '-j --no-warnings';

my $log;
my $compat;
my $bin_path;

# Get the data related to this plugin and preset certain variables with 
# default values in case they are not set
my $prefs = preferences('plugin.cloudplay');
$prefs->init({});

# This is the entry point in the script
BEGIN {
    # Initialize the logging
    $log = Slim::Utils::Log->addLogCategory({
        'category'     => 'plugin.cloudplay',
        'defaultLevel' => 'WARN',
        'description'  => string('PLUGIN_CLOUDPLAY'),
    });

    # Always use OneBrowser version of XMLBrowser by using server or packaged 
    # version included with plugin
    if (exists &Slim::Control::XMLBrowser::findAction) {
        $log->info("using server XMLBrowser");
        require Slim::Plugin::OPMLBased;
        push @ISA, 'Slim::Plugin::OPMLBased';
    } else {
        $log->info("using packaged XMLBrowser: Slim76Compat");
        require Slim76Compat::Plugin::OPMLBased;
        push @ISA, 'Slim76Compat::Plugin::OPMLBased';
        $compat = 1;
    }
}

# This is called when squeezebox server loads the plugin.
# It is used to initialize variables and the like.
sub initPlugin {
    my $class = shift;

    $class->SUPER::initPlugin(
        feed   => \&toplevel,
        tag    => 'Cloudplay',
        menu   => 'radios',
        is_app => $class->can('nonSNApps') ? 1 : undef,
        weight => 10,
    );

    if (!$::noweb) {
        require Plugins::Cloudplay::Settings;
        Plugins::Cloudplay::Settings->new;
    }

    Slim::Formats::RemoteMetadata->registerProvider(
        match => qr/https?:\/\//,
        func => \&remoteMetadataProvider,
    );

    Slim::Player::ProtocolHandlers->registerHandler(
        'cloudplay' => 'Plugins::Cloudplay::ProtocolHandler'
    );

    findExec();
}

# Called when the plugin is stopped
sub shutdownPlugin {
    my $class = shift;
}

# Returns the name to display on the squeezebox
sub getDisplayName { 'PLUGIN_CLOUDPLAY' }

sub playerMenu { shift->can('nonSNApps') ? undef : 'RADIO' }

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

sub toplevel {
    my ($client, $callback, $args) = @_;

    my $menu = [];
    push @$menu, {
        name => string('PLUGIN_CLOUDPLAY_SEARCH'),
        type => 'search',
        url => \&_search
    };

     $callback->({
        items  => $menu
     });
    
}

sub _search {
    my ($client, $callback, $args, $passDict) = @_;

    my $searchurl = $args->{'search'};
    # awful hacks, why are periods being replaced?
    $searchurl =~ s/ /./g;

    my $menu = [];
    
    my $exec = $bin_path . '/' . EXEC;
    my $exec_options = EXEC_OPTIONS;
    $log->debug("Calling External command: $exec $exec_options $searchurl");
    my $output = `$exec $exec_options $searchurl`;

    if ($output) {
        my $json = eval { from_json($output) };

        my $menu = [];
        if ($json->{'url'}) {
            push @$menu, _makeMetadata($json, $searchurl, 'default');
        }

        if (length($json->{'formats'})>0) {
            push @$menu, {
                name => string('PLUGIN_CLOUDPLAY_FORMATS'),
                type => 'link',
                url => \&_formats,
                passthrough => [ { json => $json, searchurl => $searchurl } ]
            };
        }

        $callback->({
            items  => $menu
        });
    }
    else {
        $callback->({
            items => [{name => 'Not found', type => 'text'}]
        });
    }
}

sub _formats {
    my ($client, $callback, $args, $passDict) = @_;

    my $json = $passDict->{'json'};
    my $searchurl = $passDict->{'searchurl'};

    my $menu = [];
    
    my $formats = $json->{'formats'};
    for my $format (@$formats) {
        my $formatItem = _makeMetadata($json, $searchurl, $format->{'format_id'});
        
        # Overwrite the URL, and save again in the cache
        $formatItem->{'type'} = $format->{'format'} . ' (' . $json->{'extractor_key'} . ' via Cloudlpay)';
        $formatItem->{'play'} = $format->{'url'};
        my $cache = Slim::Utils::Cache->new;
        $log->debug("setting ". 'cloudplay_meta_' . $formatItem->{'play'});
        $cache->set( 'cloudplay_meta_' . $formatItem->{'play'}, $formatItem, 3600);

        # The name is only for display in the list, we don't want this in the cache
        $formatItem->{'name'} = $format->{'format'};

        push @$menu, $formatItem;
    }

    $callback->({
        items  => $menu
     });
}

sub _makeMetadata {
    my ($json, $searchurl, $format) = @_;

    my $DATA = {
        name => $json->{'title'},
        title => $json->{'title'},
        artist => $json->{'uploader'},
        album => $json->{'extractor_key'},
        #play => 'cloudplay://' . $searchurl . '#format=' . $format,
        play => $json->{'url'},
        type => $json->{'format'} . ' (' . $json->{'extractor_key'} . ' via Cloudlpay)',
        passthrough => [ { key => $json->{'key'}} ],
        duration => int($json->{'duration'}),
        bitrate => $json->{'duration'} . 'kbps',
        icon => $json->{'thumbnails'}->[0]->{'url'},
        image => $json->{'thumbnails'}->[0]->{'url'},
        cover => $json->{'thumbnails'}->[0]->{'url'},
        on_select => 'play',
    };

    my $cache = Slim::Utils::Cache->new;
    #for debug only, clear cache
    $cache->remove('cloudplay_meta_' . $DATA->{'play'});

    $log->debug("setting ". 'cloudplay_meta_' . $DATA->{'play'});
    $cache->set( 'cloudplay_meta_' . $DATA->{'play'}, $DATA, 3600);

    return $DATA;
}

sub remoteMetadataProvider {
    my ( $client, $url ) = @_;

    my $cache = Slim::Utils::Cache->new;
    $log->debug('Getting cached data for '.$url);
    my $meta = $cache->get( 'cloudplay_meta_' . $url );

    return $meta if $meta;

    $log->debug('No cached data available for '.$url);

}

# Returns the default metadata for the track which is specified by the URL.
# In this case only the track title that will be returned.
sub defaultMeta {
    my ( $client, $url ) = @_;

    return {
        title => Slim::Music::Info::getCurrentTitle($url)
    };
}

# Always end with a 1 to make Perl happy
1;
