
## ~/.perlcriticrc
# severity = 5
# verbose = %f: [%p] %m at line %l, column %c (Severity %s).\n%d\n
my $cfg = "$ENV{HOME}/.perlcriticrc";
die 'perlcritic link does not exists. Run env-setup.pl to fix.' if !-f $cfg;
use Test::Perl::Critic (-profile => $cfg);
all_critic_ok(qw/bin lib/);
