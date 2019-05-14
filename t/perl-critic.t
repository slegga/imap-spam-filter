#use Carp::Always;

## ~/.perlcriticrc
# severity = 5
# verbose = %f: [%p] %m at line %l, column %c (Severity %s).\n%d\n
my $cfg = "$ENV{HOME}/.perlcriticrc";
warn $cfg;
die 'perlcritic link does not exists. Run env-setup.pl to fix.' if ! -e $cfg;
use Test::Perl::Critic (-profile => $cfg);
use Test::More;
if (-d 'lib') {
	all_critic_ok();
} else {
	ok(1,'dummy');
	done_testing;
}