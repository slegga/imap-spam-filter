use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../utilities-perl/lib";
use SH::Test::Pod;

check_modules_pod({
headers_required=>[ 'NAME', 'SYNOPSIS', 'DESCRIPTION', '(?:METHODS|FUNCTIONS)'],
#headers_required=>['NAME','SYNOPSIS'],
headers_order_force=>0,     # force the order of headers if set
synopsis_compile=>0,        # compile synopsis and look for errors if set
#skip=>['SH::Utils'],
name => 'petra',
environment_variables=>1,
});

check_scripts_pod({
    headers_required=>[ 'NAME','DESCRIPTION'],
    headers_order_force=>0,     # force the order of headers if set
});

done_testing;
