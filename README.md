# imap-spam-filter
Work on a Spam filter for IMAP

##How to debug why not a certain email is not removed

1. First take a copy of raw data to a file. Place that file in t/email-folder
2. Then make rule in t/config/email2.yml
3. Add result in t/email-spam_filter2.t if expected.
4. Run test and debug if not expected result.


## How to debug
1. $ PERL5LIB=lib:. perldebug t/email2-spam-filer2.t