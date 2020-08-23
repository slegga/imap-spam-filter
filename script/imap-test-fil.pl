#!/usr/bin/env perl

use Mojo::Base -strict;
use Mail::IMAPClient;
use Carp;
use YAML::Tiny;
use autodie;
use Data::Printer;
use Mojo::JSON 'to_json';
use Mojo::File 'path';
use Carp::Always;
use FindBin;
use lib "$FindBin::Bin/../../utilities-perl/lib";
use SH::UseLib;
use SH::PrettyPrint;
use SH::ScriptX; # call SH::ScriptX->import
use Mojo::Base 'SH::ScriptX';
use Time::Piece;
use DateTime::Format::RFC3501;

=head1 NAME

imap-spam-filter.pl - Spamfilter

=head1 DESCRIPTION

Script for put clean your email account. Script login to account and do steady after rules you  have given.

=cut

# Find and manage the project root directory

has home => sub { path($0)->sibling('..') };
option 'verbose!', 'Turn on verbose output';
option 'debug!', 'Turn on debug output';
option 'info!',  'Print out config data. And exit';
option 'server=s', 'regexp på server name, for running only one or few not all';

sub main {

    #
    #   Gather info
    #

   my $self = shift;

    my $CONFIGFILE = $ENV{HOME} . '/etc/email.yml';
    my $config_data;

    eval {
        open my $FH, '< :encoding(UTF-8)', $CONFIGFILE or die "Failed to read $CONFIGFILE: $!";
        $config_data = YAML::Tiny::Load(
            do { local $/; <$FH> }
        );    # slurp content
    } or do {
        confess $@;
    };

    my $ban_heads = $self->home->child('data/banned_email_headers.yml');
    if (-f "$ban_heads") {
        eval {
            open my $fh, '< :encoding(UTF-8)', "$ban_heads" or die "Failed to read $ban_heads: $!";
            $config_data->{banned_email_headers} = YAML::Tiny::Load( do { local $/; <$fh> } );
        } or do {
            confess $@;
        };
    }
    if ($self->info) {
        p $config_data ;
        return $self->gracefull_exit;
    }
        # TODO: Only keep 1 or x of emails from this sender.
say "XXXX";
    for my $emc( grep {ref $config_data->{$_} eq 'HASH'} keys %$config_data) {
        next if $emc eq 'banned_email_headers';
        next if $emc eq 'advertising_three_days';
        next if $emc eq 'blocked_email';
        next if $emc eq 'advertising_ten_days';
 say "XXXR";
        if  ($self->server) {
            my $s = $self->server;
            next if $emc!~/$s/;
        }
        say  $config_data->{$emc}->{Server};
        my $imap = Mail::IMAPClient->new(
        Server   => $config_data->{$emc}->{Server},
        User     => $config_data->{$emc}->{Username},
        Password => $config_data->{$emc}->{Password},
        Ssl      => $config_data->{$emc}->{Ssl},
        Uid      => $config_data->{$emc}->{Uid},
        Debug    => $config_data->{$emc}->{Debug},
        ) or die "Cant open $emc email account: ". ($config_data->{$emc}->{Server}//'__UNDEF__'). ' User: ' . ($config_data->{$emc}->{Username}//'__UNDEF');

        say $imap->Rfc3501_datetime(time()) if defined $imap;

        my $folders = $imap->folders
        or die "$emc: List folders error: ", $imap->LastError, "\n";
        printf "Folders: %s\n",join("\n",@$folders);

		if (grep{$_ eq 'INBOX.Behandlet'}@$folders) {
	        $imap->select( 'INBOX.Behandlet' )
	    	or die "$emc: Select '$folders->[0]' error: ", $imap->LastError, "\n";
	    	my $Rfc3501_date = $imap->Rfc3501_date(time - 2.5*365*24*60*60); #
	    	my @msgs = $imap->before($Rfc3501_date)
	  or warn "Could not find any messages sent since $Rfc3501_date: $@\n";
	        say join(' ',grep{ defined }@msgs);
            my %points;
            my $f = DateTime::Format::RFC3501->new();
            for my $i (@msgs) {

                my $tmp = $imap->fetch_hash($i, "RFC822.SIZE",'ENVELOPE')->{$i};
                p $tmp;
                warn  $tmp->{ENVELOPE};
                my $point = $f->parse_datetime( $tmp->{ENVELOPE} );
                $points{$point} = $i;
            }
	    }
        $imap->expunge;
        $imap->logout
            or die "Logout error: ", $imap->LastError, "\n";
    }


}

__PACKAGE__->new->main;
