#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx mail smtp module.

###############################################################################

use warnings;
use strict;

use Test::More tests => 28;

use MIME::Base64;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use _common;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

start_nginx('smtp.conf');

###############################################################################

my $s = smtp_connect();
smtp_check(qr/^220 /, "greeting");

smtp_send('EHLO example.com');
smtp_check(qr/^250 /, "ehlo");

smtp_send('AUTH PLAIN ' . encode_base64("test\@example.com\0\0bad", ''));
smtp_check(qr/^5.. /, 'auth plain with bad password');

smtp_send('AUTH PLAIN ' . encode_base64("test\@example.com\0\0secret", ''));
smtp_ok('auth plain');

# We are talking to backend from this point

smtp_send('MAIL FROM:<test@example.com> SIZE=100');
smtp_ok('mail from after auth');

smtp_send('RSET');
smtp_ok('rset');

smtp_send('MAIL FROM:<test@xn--e1afmkfd.xn--80akhbyknj4f> SIZE=100');
smtp_ok("idn mail from (example.test in russian)");

smtp_send('QUIT');
smtp_ok("quit");

# Try auth plain with pipelining

$s = smtp_connect();
smtp_check(qr/^220 /, "greeting");

smtp_send('EHLO example.com');
smtp_check(qr/^250 /, "ehlo");

smtp_send('INVALID COMMAND WITH ARGUMENTS' . CRLF
	. 'RSET');
smtp_read();
smtp_ok('pipelined rset after invalid command');

smtp_send('AUTH PLAIN '
	. encode_base64("test\@example.com\0\0bad", '') . CRLF
	. 'MAIL FROM:<test@example.com> SIZE=100');
smtp_read();
smtp_ok('mail from after failed pipelined auth');

smtp_send('AUTH PLAIN '
	. encode_base64("test\@example.com\0\0secret", '') . CRLF
	. 'MAIL FROM:<test@example.com> SIZE=100');
smtp_read();
smtp_ok('mail from after pipelined auth');

# Try auth none

$s = smtp_connect();
smtp_check(qr/^220 /, "greeting");

smtp_send('EHLO example.com');
smtp_check(qr/^250 /, "ehlo");

smtp_send('MAIL FROM:<test@example.com> SIZE=100');
smtp_ok('auth none - mail from');

smtp_send('RCPT TO:<test@example.com>');
smtp_ok('auth none - rcpt to');

smtp_send('RSET');
smtp_ok('auth none - rset, should go to backend');

# Auth none with pipelining

$s = smtp_connect();
smtp_check(qr/^220 /, "greeting");

smtp_send('EHLO example.com');
smtp_check(qr/^250 /, "ehlo");

smtp_send('MAIL FROM:<test@example.com> SIZE=100' . CRLF
	. 'RCPT TO:<test@example.com>' . CRLF
	. 'RSET');

smtp_ok('pipelined mail from');

smtp_ok('pipelined rcpt to');
smtp_ok('pipelined rset');

# Connection must stay even if error returned to rcpt to command

$s = smtp_connect();
smtp_read(); # skip greeting

smtp_send('EHLO example.com');
smtp_read(); # skip ehlo reply

smtp_send('MAIL FROM:<test@example.com> SIZE=100');
smtp_read(); # skip mail from reply

smtp_send('RCPT TO:<example.com>');
smtp_check(qr/^5.. /, "bad rcpt to");

smtp_send('RCPT TO:<test@example.com>');
smtp_ok('good rcpt to');

# Make sure command splitted into many packets processed correctly

$s = smtp_connect();
smtp_read();

log_out('HEL');
$s->print('HEL');
smtp_send('O example.com');
smtp_ok('splitted command');

# With smtp_greeting_delay session expected to be closed after first error
# message if client sent something before greeting.  Use 10026 port
# configured with smtp_greeting_delay 0.1s to check this.

$s = smtp_connect(PeerPort => 10026);
smtp_send('HELO example.com');
smtp_check(qr/^5.. /, "command before greeting - session must be rejected");
ok($s->eof(), "session have to be closed");

###############################################################################
