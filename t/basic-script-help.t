# script_compile.t
use Mojo::File 'path';
use Test::More;
use FindBin;
use Carp::Always;
use lib "$FindBin::Bin/../../utilities-perl/lib";
use SH::UseLib;
use Test::ScriptX;
no warnings 'redefine';
my $testscriptname = path($0)->basename;
for my $script (glob('script/*'),glob('bin/*')) { #$FindBin::Bin . '/../
    next if -d $script;
    next if ( $script !~ /\.pl$/ && $script !~ /^[^\.]+$/);
    my $scr_obj = path($script);
    next if index($scr_obj->slurp,'::ScriptX') == -1;
    my $t = Test::ScriptX->new($script);
    $t->run(help => 1);
    $t->stderr_ok;
    my $b = path($0)->basename;
    $t->stdout_like(qr/$b/);
}
ok(1,'Dummy'); # dummy testing in case no scripts
done_testing;
