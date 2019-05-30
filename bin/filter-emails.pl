#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/../../utilities-perl/lib";
use SH::UseLib;
use SH::ScriptX;
use Mojo::Base 'SH::ScriptX';
use utf8;
use YAML::Tiny;
use Carp 'confess';
use open ':encoding(UTF-8)';
use Mail::IMAPClient;
use SH::Email::ToHash;
use Data::Dumper;
#use Carp::Always;

=head1 NAME

filter-emails.pl - Search and show emails

=head1 DESCRIPTION

Search or show emails

=head1 COMMANDS

=over 4

=item list - List emails uid and Subject

=item folders - List email folders

=item servers - List email servers

=item show - complete email

=back

=cut

has 'config';
option 'uid=i', 'See only this uid email';
option 'folder=s', 'Show only email from this folder. Default INBOX',{default=>'INBOX'};
option 'server=s', 'Filter servername';
option 'info!',    'Show info';

 sub main {
    my $self = shift;
    my ($command,@e) = $self->extra_options;
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
    for my $emc( grep {ref $config_data->{$_} eq 'HASH'} keys %$config_data) {
        if  ($self->server) {
            my $s = $self->server;
            next if $emc!~/$s/;
        }
        my $imap = Mail::IMAPClient->new(
        Server   => $config_data->{$emc}->{Server},
        User     => $config_data->{$emc}->{Username},
        Password => $config_data->{$emc}->{Password},
        Ssl      => $config_data->{$emc}->{Ssl},
        Uid      => $config_data->{$emc}->{Uid},
        Debug    => $config_data->{$emc}->{Debug},
        Peek     => 1,
        ) or die "Cant open $emc email account: ". ($config_data->{$emc}->{Server}//'__UNDEF__'). ' User: ' . ($config_data->{$emc}->{Username}//'__UNDEF');

        $imap->select( $self->folder );

#        warn join(' ',@all);
        my $convert = SH::Email::ToHash->new;
        if ($command eq 'folders') {
            my $folders = $imap->folders
            or die "$emc: List folders error: ", $imap->LastError, "\n";
            say join("\n", @$folders);
        }
        elsif ($command eq 'list') {
            say Dumper  $imap->list();
        } else {
            say $self->folder;
            my @all = $imap->search('ALL')
            or die "$emc: Fetch error: ", $imap->LastError, "\n";

            for my $uid(@all) {
                my $next = 0;
                my $text = $imap->message_string($uid);
                my $email_h = $convert->msgtext2hash($text);
                say $email_h->{header}->{Subject};
            }
        }
    }

}

__PACKAGE__->new(options_cfg=>{extra=>1})->main();
