package Object;
require './bin/email2-spam-filter.pl'; ##no critic
package main;
Object->import;

use Mojo::Base -strict;
use Mojo::File 'path';
use Test::More;
use Carp::Always;
use FindBin;
$ENV{MOJO_MODE}='dry-run';
$ENV{NMS_CONFIG_DIR} = 't/etc';


#Test script as a object

my $to = Object->new(configfile=>'t/config/configfile.yml');

$to->main({testing=>1}); #,iterations=>1,mode=>'mocked'
done_testing;