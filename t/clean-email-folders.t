use Mojo::Base -strict;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../utilities-perl/lib";
use SH::UseLib;
use Mojo::File 'path';

# clean-email-folders.pl - Delete old emails after rules from configuration.

use Test::ScriptX;


unlike(path('bin/clean-email-folders.pl')->slurp, qr{\<[A-Z]+\>},'All placeholders are changed');
my $t = Test::ScriptX->new('bin/clean-email-folders.pl', debug=>1);
$t->run(help=>1);
$t->stderr_ok->stdout_like(qr{clean-email-folders});
done_testing;
