use Mojo::Base -strict;
use Test::More;
use Mojo::File 'path';

my $lib;
BEGIN {
    my $gitdir = Mojo::File->curfile;
    my @cats = @$gitdir;
    while (my $cd = pop @cats) {
        if ($cd eq 'git') {
            $gitdir = path(@cats,'git');
            last;
        }
    }
    $lib =  $gitdir->child('utilities-perl','lib')->to_string;
};
use lib $lib;

use SH::UseLib;
use Test::ScriptX;


# yml-conv-yml.pl - Convert old email.yml to email2.yml format

unlike(path('script/email-yml-2-email2.pl')->slurp, qr{\<[A-Z]+\>},'All placeholders are changed');
my $t = Test::ScriptX->new('bin/yml-conv-yml.pl', debug=>1);
$t->run(help=>1);
$t->stderr_ok->stdout_like(qr{yml-conv-yml});
done_testing;
