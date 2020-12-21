$ENV{MOCK}=1;
package Object;
require './bin/email2-spam-filter.pl'; ##no critic
package main;
$ENV{MOCK} = 0;
Object->import;

use Mojo::Base -strict;
use Mojo::File 'path';
use Test::More;
use Carp::Always;
use FindBin;
use Carp::Always;

$ENV{MOJO_MODE}='dry-run';
$ENV{NMS_CONFIG_DIR} = 't/etc';


#Test script as a object

my $to = Object->new(configfile=>'t/config/email2.yml', debug=>1);

$to->main({configfile=>'t/config/email2.yml', testing=>1}); #,iterations=>1,mode=>'mocked'
done_testing;