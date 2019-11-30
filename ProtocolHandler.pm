package Plugins::Cloudplay::ProtocolHandler;

# Plugin to stream audio from 22track streams
#
# Released under GNU General Public License version 2 (GPLv2)
# Written by Daniel Vijge
# See file LICENSE for full license details

#use strict;

use base qw(Slim::Player::Protocols::HTTP);

use List::Util qw(min max);
use LWP::Simple;
use LWP::UserAgent;
use HTML::Parser;
use URI::Escape;
use JSON::XS::VersionOneAndTwo;
use XML::Simple;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Errno;
use Slim::Utils::Cache;
use Scalar::Util qw(blessed);

use constant EXEC => 'youtube-dl';
use constant EXEC_OPTIONS => '-j --no-warnings';

my $log   = logger('plugin.cloudplay');
my $prefs = preferences('plugin.cloudplay');
$prefs->init({});

Slim::Player::ProtocolHandlers->registerHandler('cloudplay', __PACKAGE__);

sub canSeek { 0 }

sub getFormatForURL () { 'mp3' }

sub isRemote { 1 }

# Source for AudioScrobbler
sub audioScrobblerSource {
        return 'R';
}

sub scanUrl {
    my ($class, $url, $args) = @_;
    
    $args->{cb}->( $args->{song}->currentTrack() );
}

sub getNextTrack {
    my ($class, $song, $successCb, $errorCb) = @_;
    
    my $client = $song->master();
    my $url    = $song->currentTrack()->url;
        
    my $cache = Slim::Utils::Cache->new;
    $log->debug('Getting cached data for '.$url);
    my $meta = $cache->get( 'cloudplay_meta_' . $url );

    use Data::Dumper;
    $log->debug(Dumper($meta));

    return $meta if $meta;

    $log->debug('No cached data available for '.$url);
}

sub getNextTrackError {
    my $http = shift;
    
    $http->params->{errorCallback}->( 'PLUGIN_CLOUDPLAY_ERROR', $http->error );
}

sub canDirectStreamSong {
    my ( $class, $client, $song ) = @_;
    
    # We need to check with the base class (HTTP) to see if we
    # are synced or if the user has set mp3StreamingMethod

    return $class->SUPER::canDirectStream( $client, $song->streamUrl(), $class->getFormatForURL() );
}

# If an audio stream fails, keep playing
sub handleDirectError {
    my ( $class, $client, $url, $response, $status_line ) = @_;
    
    main::INFOLOG && $log->info("Direct stream failed: $url [$response] $status_line");
}

1;
