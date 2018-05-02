#!/usr/bin/env perl

use Mojo::Base -strict;
use Mail::IMAPClient;
use Carp;
use YAML;
use Data::Printer;
use Mojo::Home;
use Carp::Always;

# Find and manage the project root directory
my $home = Mojo::Home->new;
$home->detect;

my $CONFIGFILE = $ENV{HOME} . '/etc/email.yml';
my $config_data;

eval {
    open my $FH, '< :encoding(UTF-8)', $CONFIGFILE or die "Failed to read $CONFIGFILE: $!";
    $config_data = YAML::Load(
        do { local $/; <$FH> }
    );    # slurp content
} or do {
    confess $@;
};

my $ban_heads = $home->rel_file('data/banned_email_headers.yml');
if (-f "$ban_heads") {
    eval {
        open my $fh, '< :encoding(UTF-8)', "$ban_heads" or die "Failed to read $CONFIGFILE: $!";
        $config_data->{banned_email_headers} = YAML::Load( do { local $/; <$fh> } );
    } or do {
        confess $@;
    };
}

say $imap->Rfc3501_date(time());
my $imap = Mail::IMAPClient->new(
Server   => $config_data->{mail_server},
User     => $config_data->{username},
Password => $config_data->{password},
Ssl      => 1,
Uid      => 1,
);

my $folders = $imap->folders
or die "List folders error: ", $imap->LastError, "\n";
#print "Folders: @$folders\n";

$imap->select( $folders->[0] )
or die "Select '$folders->[0]' error: ", $imap->LastError, "\n";

$imap->fetch_hash("FLAGS", "INTERNALDATE", "RFC822.SIZE")
or die "Fetch hash '$folders->[0]' error: ", $imap->LastError, "\n";


# remove blocked senders
for my $blocked(@{$config_data->{blocked_email}}) {
    my $uid_ar = $imap->search( 'FROM "'.$blocked.'"' ) or warn "search failed: $@\n";
    if (@$uid_ar) {
        p($uid_ar);
        $imap->move('INBOX.Spam',$uid_ar);
    }
}

# remove blocked email headers
for my $key (keys %{$config_data->{banned_email_headers}}) {
    for my $item (@{$config_data->{banned_email_headers}->{$key}}) {
        say "head: $key -> $item";

        my $uid_ar = $imap->search( HEADER => $key => \$imap->Quote($item) ) or warn "search failed: $@\n";
        if (defined $uid_ar && @$uid_ar) {
	        say "MOVE TO SPAM BANNED: $key -> $item";
            p($uid_ar);
            $imap->move('INBOX.Spam',$uid_ar);
        }
    }
}


# delay remove of ads
my $dt = time - 3 * 24 *60 *60;

for my $blocked(@{$config_data->{advertising_three_days}}) {
    my $search = 'FROM "'.$blocked.'" BEFORE '.$imap->Rfc3501_date($dt);#45646545644"';#.$imap->Quote($imap->Rfc3501_datetime($dt));#Rfc822_date($dt));
    say "###$search";
    my $uid_ar = $imap->search( $search ) or warn "search failed: $@\n";
    if (defined $uid_ar && @$uid_ar) {
        say "WARNING MOVE ADS TO SPAM";
        p($uid_ar);
        $imap->move('INBOX.Spam',$uid_ar);
    }

}

# delay remove of info emails
 $dt = time - 10 * 24 *60 *60;

for my $blocked(@{$config_data->{advertising_ten_days}}) {
    my $search = 'FROM "'.$blocked.'" BEFORE '.$imap->Rfc3501_date($dt);#45646545644"';#.$imap->Quote($imap->Rfc3501_datetime($dt));#Rfc822_date($dt));
    say "###$search";
    my $uid_ar = $imap->search( $search ) or warn "search failed: $@\n";
    if (defined $uid_ar && @$uid_ar) {
        say "WARNING MOVE INFO TO SPAM";
        p($uid_ar);
        $imap->move('INBOX.Spam',$uid_ar);
    }

}


$imap->expunge;
$imap->logout
    or die "Logout error: ", $imap->LastError, "\n";
