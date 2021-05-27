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
use Data::Dumper;

#Test script as a object
ok(1,'dummy');
my $to = Object->new(configfile=>'t/config/email2.yml', debug=>1);

my $result = $to->main({configfile=>'t/config/email2.yml', testing=>1}); #,iterations=>1,mode=>'mocked'
my @spam_emails = sort @{$result->{'INBOX.Spam'}};
say ".";
is_deeply \@spam_emails, [ 't/email-folder/lisa-sex.txt','t/email-folder/phishing.txt'  ],'Correct moving';
# 't/email-folder/base64-problem2.txt',
say ".";

done_testing;