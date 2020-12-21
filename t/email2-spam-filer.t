use Mojo::Base -strict;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../utilities-perl/lib";
use SH::UseLib;
use Mojo::File 'path';

# filter-emails.pl - Search for emails

use Test::ScriptX;


unlike(path('bin/email2-spam-filter.pl')->slurp, qr{\<[A-Z]+\>},'All placeholders are changed');
my $t = Test::ScriptX->new('bin/email2-spam-filter.pl', debug => 1, configfile => 't/config/email2.yml');
$t->run(help=>1);
$t->stderr_ok->stdout_like(qr{email2-spam-filter.pl});
$t->run();
$t->stderr_ok->stdout_like(qr{filtcer-emails});
done_testing;
