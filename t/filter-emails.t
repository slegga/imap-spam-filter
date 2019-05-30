use Mojo::Base -strict;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../utilities-perl/lib";
use SH::UseLib;
use Mojo::File 'path';

# filter-emails.pl - Search for emails

use Test::ScriptX;


unlike(path('bin/filter-emails.pl')->slurp, qr{\<[A-Z]+\>},'All placeholders are changed');
my $t = Test::ScriptX->new('bin/filter-emails.pl', debug=>1);
$t->run(help=>1);
$t->stderr_ok->stdout_like(qr{filter-emails});
done_testing;
