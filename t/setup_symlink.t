#!perl

use 5.010;
use strict;
use warnings;
use Test::More 0.96;

use File::chdir;
use File::Slurp;
use File::Temp qw(tempdir);
use Setup::File::Symlink qw(setup_symlink);
use Test::Perinci::Tx::Manager qw(test_tx_action);

plan skip_all => "symlink() not available"
    unless eval { symlink "", ""; 1 };

my $tmpdir = tempdir(CLEANUP=>1);
$CWD = $tmpdir;

test_tx_action(
    name          => "create",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s",
    },
    f             => "Setup::File::Symlink::setup_symlink",
    args          => {symlink => "$tmpdir/s", target=>"/t"},
);
test_tx_action(
    name          => "do not create",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s",
    },
    f             => "Setup::File::Symlink::setup_symlink",
    args          => {symlink => "$tmpdir/s", target=>"/t", create=>0},
    status        => 412,
);
test_tx_action(
    name          => "replace symlink",
    tmpdir        => $tmpdir,
    reset_state   => sub {
        unlink "$tmpdir/s"; symlink "/t", "$tmpdir/s";
    },
    f             => "Setup::File::Symlink::setup_symlink",
    args          => {symlink => "$tmpdir/s", target=>"/t2"},
);
goto DONE_TESTING;

test_tx_action(
    name          => "do not replace_symlink",
    prepare       => sub { symlink "t", "s" },
    symlink       => "/s",
    target        => "/t2",
    other_args    => {replace_symlink=>0},
    check_unsetup => {target=>"t"},
    dry_do_error  => 412,
    cleanup       => sub { unlink "s" },
);
test_tx_action(
    name          => "replace file",
    prepare       => sub { write_file "s", "test" },
    symlink       => "/s",
    target        => "/t",
    other_args    => {replace_file=>1},
    check_unsetup => {is_symlink=>0},
    check_setup   => {target=>"$tmpdir/t"},
    cleanup       => sub { unlink "s" },
);
test_tx_action(
    name          => "do not replace file",
    prepare       => sub { write_file "s", "test" },
    symlink       => "/s",
    target        => "/t",
    other_args    => {},
    check_unsetup => {is_symlink=>0},
    dry_do_error  => 412,
    cleanup       => sub { unlink "s" },
);
test_tx_action(
    name          => "replace dir",
    prepare       => sub { mkdir "s"; write_file "s/f", "test" },
    symlink       => "/s",
    target        => "/t",
    other_args    => {replace_dir=>1},
    check_unsetup => {is_symlink=>0,
                      extra=>sub {
                          ok((-f "s/f"), "file inside dir still exists");
                          is(read_file("s/f"), "test", "file content intact");
                      }},
    check_setup   => {target=>"$tmpdir/t"},
    cleanup       => sub { unlink "s" },
);
test_tx_action(
    name          => "do not replace dir",
    prepare       => sub { mkdir "s" },
    symlink       => "/s",
    target        => "/t",
    other_args    => {},
    check_unsetup => {is_symlink=>0},
    dry_do_error  => 412,
    cleanup       => sub { rmdir "s" },
);
goto DONE_TESTING;

DONE_TESTING:
done_testing();
if (Test::More->builder->is_passing) {
    #diag "all tests successful, deleting test data dir";
    $CWD = "/";
} else {
    diag "there are failing tests, not deleting test data dir $tmpdir";
}
