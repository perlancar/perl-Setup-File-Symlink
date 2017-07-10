#!perl

use 5.010;
use strict;
use warnings;
use Test::More 0.96;

use File::chdir;
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use Setup::File::Symlink;
use Test::Perinci::Tx::Manager qw(test_tx_action);

plan skip_all => "symlink() not available"
    unless eval { symlink "", ""; 1 };

my $tmpdir = tempdir(CLEANUP=>1);
$CWD = $tmpdir;

test_tx_action(
    name          => "fixable",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s";
    },
    f             => 'Setup::File::Symlink::ln_s',
    args          => {symlink=>"$tmpdir/s", target=>"/t"},
);

test_tx_action(
    name          => "fixed",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s"; symlink "/t", "$tmpdir/s";
    },
    f             => 'Setup::File::Symlink::ln_s',
    args          => {symlink=>"$tmpdir/s", target=>"/t"},
    status        => 304,
);

test_tx_action(
    name          => "unfixable: s already exists (file)",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s";
        write_text("$tmpdir/s", "");
    },
    f             => 'Setup::File::Symlink::ln_s',
    args          => {symlink=>"$tmpdir/s", target=>"/t"},
    status        => 412,
);

DONE_TESTING:
done_testing();
if (Test::More->builder->is_passing) {
    #diag "all tests successful, deleting test data dir";
    $CWD = "/";
} else {
    diag "there are failing tests, not deleting test data dir $tmpdir";
}
