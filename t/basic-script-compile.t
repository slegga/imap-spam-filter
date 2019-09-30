# script_compile.t
use Test::Compile;
for my $script (glob('script/*'),glob('bin/*')) { #$FindBin::Bin . '/../
    next if -d $script;
    if ( $script =~ /\.pl$/ || $script =~ /^[^\.]+$/) {
        pl_file_ok( $script );
    }
}
my $test = Test::Compile->new();
$test->done_testing();
