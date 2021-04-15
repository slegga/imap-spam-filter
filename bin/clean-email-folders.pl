#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/../../utilities-perl/lib";
use SH::UseLib;
use SH::ScriptX;
use Mojo::Base 'SH::ScriptX';
use utf8;
use open ':encoding(UTF-8)';
use Mail::IMAPClient;
use Carp;
use YAML::Tiny;
use autodie;
use Data::Printer;
use Mojo::File 'path';
use Carp::Always;
use SH::PrettyPrint;
use SH::ScriptX; # call SH::ScriptX->import
use Mojo::Base 'SH::ScriptX';
#use Time::Piece;
use NetAddr::IP;
use SH::Email::ToHash;
use Data::Dumper;
use DateTime::Format::Mail;
#use Carp::Always;

=head1 NAME

clean-email-folders.pl - Delete old emails after rules from configuration.

=head1 DESCRIPTION

Remove old emails.

=cut

has 'config';
has home => sub { path($0)->sibling('..') };
option 'dryrun!', 'Print to screen instead of doing changes';
option 'verbose!', 'Turn on verbose output';
option 'debug!', 'Turn on debug output';
option 'info!',  'Print out config data. And exit';
option 'server=s', 'regexp på server name, for running only one or few not all';

 sub main {
    my $self = shift;
    my $CONFIGFILE = $ENV{HOME} . '/etc/email2.yml';
    my $config_data;

    eval {
        open my $FH, '< :encoding(UTF-8)', $CONFIGFILE or die "Failed to read $CONFIGFILE: $!";
        $config_data = YAML::Tiny::Load(
            do { local $/; <$FH> }
        );    # slurp content
    } or do {
        confess $@;
    };
    if ($self->info) {
        p $config_data ;
        return $self->gracefull_exit;
    }
    my $convert = SH::Email::ToHash->new;

    my $pf = DateTime::Format::Mail->new();
    for my $emc(  keys %{ $config_data->{connection} }) {
    	next if $emc eq 'banned_email_headers';
    	next if $emc eq 'advertising_three_days';
    	next if $emc eq 'blocked_email';
    	next if $emc eq 'advertising_ten_days';
        if  ($self->server) {
            my $s = $self->server;
            next if $emc!~/$s/;
        }
    	my $imap = Mail::IMAPClient->new(
    	Server   => $config_data->{connection}->{$emc}->{Server},
    	User     => $config_data->{connection}->{$emc}->{Username},
    	Password => $config_data->{connection}->{$emc}->{Password},
    	Ssl      => $config_data->{connection}->{$emc}->{Ssl},
    	Uid      => $config_data->{connection}->{$emc}->{Uid},
    	Debug    => $config_data->{connection}->{$emc}->{Debug},
    	Peek     => 1,
    	) or die "Cant open $emc email account: ". ($config_data->{connection}->{$emc}->{Server}//'__UNDEF__'). ' User: ' . ($config_data->{connection}->{$emc}->{Username}//'__UNDEF');

    	say $imap->Rfc3501_datetime(time()) if defined $imap;

    	my @folders = $imap->folders
    	or die "$emc: List folders error: ", $imap->LastError, "\n";

		print join( ", ", @folders ), ".\n" if $self->verbose;

        #keep 200
        for my $trash_f(qw/INBOX.S&APg-ppelb&APg-tte INBOX.Trash /) {
            if (grep {$_ eq $trash_f} @folders) {
            	$imap->select($trash_f);
                my @all = sort {$a <=> $b} $imap->search('ALL');
                pop (@all) for(0 .. 200);
                next if !@all;
                printf "%s %s\n", $trash_f, scalar @all;
                $imap->delete_message(\@all)or warn "Could not delete_messages: $@\n" # for @all;
            	    or die "Logout error: ", $imap->LastError, "\n";
                $imap->expunge;

            }
        }
        for my $trash_f(qw/INBOX.Spam/) {
            if (grep {$_ eq $trash_f} @folders) {
            	$imap->select($trash_f);
                my @all = sort {$a <=> $b} $imap->search('ALL');
                pop (@all) for(0 .. 300);
                next if !@all;
                printf "%s %s\n", $trash_f, scalar @all;
                $imap->delete_message(\@all)or warn "Could not delete_messages: $@\n" # for @all;
            	    or die "Logout error: ", $imap->LastError, "\n";
                $imap->expunge;

            }
        }
        for my $trash_f(qw/INBOX.Behandlet INBOX.Sendt/) {
            if (grep {$_ eq $trash_f} @folders) {
            	$imap->select($trash_f);
                my @all = sort {$a <=> $b} $imap->search('ALL');
                pop (@all) for(0 .. 2000);
                next if !@all;
                printf "%s %s\n", $trash_f, scalar @all;
                $imap->delete_message(\@all)or warn "Could not delete_messages: $@\n" # for @all;
            	    or die "Logout error: ", $imap->LastError, "\n";
                $imap->expunge;

            }
        }


        $imap->logout
        # delete trash
	}

    #delete files in /tmp
    # Mail::IMAPClient produces alot of files in /tmp
    # Gets disk error if no housekeeping of /tmp
	if (-d '/tmp/emails') {
		`rm -rf /tmp/emails`;
	}
#    my @tmpfiles=path('/tmp')->list_tree->each;
#    for my $f(@tmpfiles) {
#        next if "$f" =~ /^systemd/;
#        next if "$f" =~ /\.sock$/;
#        if ($f->lstat->mtime > time - 14 * 24 * 60 * 60) {
#            unlink "$f";
#        }
#    }

}

__PACKAGE__->new->main();
