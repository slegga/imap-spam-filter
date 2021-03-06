package Test::Mail::IMAPClient;
use Mojo::Base -base, -signatures;
use DateTime::Format::RFC3501;
use DateTime;
use Mojo::File 'path';

=head1 NAME

Test::Mail::IMAPClient

=head1 SYNOPSIS

    use Test::Mail::IMAPClient;
    my $imap = Test::Mail::IMAPClient->new(Server=>'files');

=head1 DESCRIPTION

Simulate Mail::IMAPClient for testing.

=head1 ATTRIBUTES

=cut

has 'Server';
has 'Folder_INBOX';
has 'Folder_Sent';
has 'selected_folder';
has 'error' =>'';
has 'move_to' =>sub{{}};

=head1 METHODS

=head2 Rfc3501_datetime

Epoch to rfc3501

=cut

sub Rfc3501_datetime($self, $epoch) {
    my $f = DateTime::Format::RFC3501->new();
    return $f->format_datetime(DateTime->from_epoch(epoch=>$epoch));
}

=head2 folders

=cut

sub folders($self) {
    return ['INBOX','Sent'];
}

=head2 select

=cut

sub select($self,$folder) {
    my $new;
    if ($folder eq 'INBOX') {
        $new = $self->Folder_INBOX;
    }
    elsif ($folder =~ /^t\//) {
        $new = $folder;
    } else {
        die "Unknown folder $folder";
    }
    $self->selected_folder($new);
    return $self;
}

=head2 since

=cut

sub since($self,$date) {
    return path($self->selected_folder)->list->each;
}

=head2 search

=cut

sub search($self,@string){
    if ($string[0] eq 'ALL') {
        my $tdir = $self->selected_folder||$self->Folder_INBOX;
        die "Missing \$tdir" if !$tdir;
        return path($tdir)->list->each;
    }
    warn join(" # ", @string);
    ...;
}

=head2 LastError

=cut

sub LastError($self) {
    return $self->error;
}

=head2 message_string

=cut

sub message_string($self,$uid) {
    return path($uid)->slurp;
}

=head2 size

=cut

sub size($self,$uid) {
    return length(path($uid)->slurp);
}

=head2 expunge

=cut

sub expunge($self) {
    # Delete marked deleted emails
    return $self->move_to;

}

=head2 logout

=cut

sub logout($self) {
    # do nothing
    return 1
}

=head2 move

=cut

sub move($self,$folder,$uid) {
    my $m = $self->move_to;
    push @{ $m->{$folder} }, $uid;
    $self->move_to($m);
    return $self;
}
1;