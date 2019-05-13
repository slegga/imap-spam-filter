# script_compile.t
use Test::Compile 'no_plan';
for my $script (glob('script/*'),glob('bin/*')) { #$FindBin::Bin . '/../
    next if -d $script;
    if ( $script =~ /\.pl$/ || $script =~ /^[^\.]+$/) {
        pl_file_ok( $script );
    }
}
