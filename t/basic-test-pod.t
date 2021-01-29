use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../utilities-perl/lib";
use SH::Test::Pod;

check_modules_pod({
headers_required=>[ 'NAME', 'SYNOPSIS', 'DESCRIPTION', '(?:METHODS|FUNCTIONS)',],
headers_order_force=>1,     # force the order of headers if set
synopsis_compile=>1,        # compile synopsis and look for errors if set
environment_variables=>1,
skip=>['SH::Code::Template::ScriptX','SH::Code::Template::Model'],
name => 'petra',
});

check_scripts_pod({
    headers_required=>[ 'NAME'],
    headers_order_force=>0,     # force the order of headers if set
});



done_testing;
