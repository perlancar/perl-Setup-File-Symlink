#!perl

use 5.010;
use strict;
use warnings;
use Test::More 0.96;

use File::chdir;
use File::Temp qw(tempdir);
use Setup::File::Symlink qw(setup_symlink);

plan skip_all => "symlink() not available"
    unless eval { symlink "", ""; 1 };

my $rootdir = tempdir(CLEANUP=>1);
$CWD = $rootdir;
my $undo_data;
my $redo_data;

test_setup_symlink(
    name       => "create (dry run)",
    symlink    => "/s",
    target     => "/t",
    other_args => {-dry_run=>1},
    status     => 200,
    exists     => 0,
);
test_setup_symlink(
    name       => "create",
    symlink    => "/s",
    target     => "/t",
    other_args => {},
    status     => 200,
    post_test  => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok(!$undo_data, "no undo data");
    },
    cleanup    => 1,
);
test_setup_symlink(
    name       => "create (with undo)",
    symlink    => "/s",
    target     => "/t",
    other_args => {-undo_action=>"do"},
    status     => 200,
    post_test  => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok($undo_data, "there is undo data");
    },
);
test_setup_symlink(
    name       => "unchanged",
    symlink    => "/s",
    target     => "/t",
    other_args => {},
    status     => 304,
);
test_setup_symlink(
    name       => "do not create",
    symlink    => "/s2",
    target     => "/t",
    other_args => {create=>0},
    status     => 412,
    exists     => 0,
);
# XXX create (undo, dry run)
test_setup_symlink(
    name       => "create (undo)",
    symlink    => "/s",
    target     => "/t",
    other_args => {-undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    exists     => 0,
    post_test  => sub {
        my $res = shift;
        $redo_data = $res->[3]{redo_data};
    }
);
# XXX create (redo, dry run)
test_setup_symlink(
    name       => "create (redo)",
    symlink    => "/s",
    target     => "/t",
    other_args => {-undo_action=>"redo", -redo_data=>$redo_data},
    status     => 200,
    exists     => 1,
);

test_setup_symlink(
    name       => "replace symlink (dry run)",
    symlink    => "/s",
    target     => "/t2",
    other_args => {-dry_run=>1},
    status     => 200,
    skip_test_target => 1,
    post_test  => sub {
        my $res = shift;
        is(readlink("$rootdir/s"), "$rootdir/t", "old symlink unreplaced");
    },
);
test_setup_symlink(
    name       => "replace symlink (with undo)",
    symlink    => "/s",
    target     => "/t2",
    other_args => {-undo_action=>"do"},
    status     => 200,
    post_test  => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
    },
);
test_setup_symlink(
    name       => "replace symlink (undo)",
    symlink    => "/s",
    target     => "/t2",
    other_args => {-undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    skip_test_target => 1,
    post_test  => sub {
        my $res = shift;
        $redo_data = $res->[3]{redo_data};
        is(readlink("$rootdir/s"), "$rootdir/t", "old symlink restored");
    },
);
test_setup_symlink(
    name       => "replace symlink (redo)",
    symlink    => "/s",
    target     => "/t2",
    other_args => {-undo_action=>"redo", -redo_data=>$redo_data},
    status     => 200,
    skip_test_target => 1,
    post_test  => sub {
        my $res = shift;
        is(readlink("$rootdir/s"), "$rootdir/t2", "new symlink restored");
    },
);
test_setup_symlink(
    name       => "do not replace symlink",
    symlink    => "/s",
    target     => "/t",
    other_args => {replace_symlink=>0},
    status     => 412,
    skip_test_target => 1,
    post_test  => sub {
        my $res = shift;
        is(readlink("$rootdir/s"), "$rootdir/t2", "old symlink unreplaced");
    },
);
# XXX reject invalid undo data?
# TODO replace_dir
# TODO replace_file

DONE_TESTING:
done_testing();
if (Test::More->builder->is_passing) {
    #diag "all tests successful, deleting test data dir";
    $CWD = "/";
} else {
    diag "there are failing tests, not deleting test data dir $rootdir";
}

sub test_setup_symlink {
    my (%args) = @_;
    subtest "$args{name}" => sub {

        my $symlink = $rootdir . $args{symlink};
        my $target  = $rootdir . $args{target};
        my %setup_args = (symlink => $symlink, target => $target);
        if ($args{other_args}) {
            while (my ($k, $v) = each %{$args{other_args}}) {
                $setup_args{$k} = $v;
            }
        }
        my $res;
        eval {
            $res = setup_symlink(%setup_args);
        };
        my $eval_err = $@;

        if ($args{dies}) {
            ok($eval_err, "dies");
        }
        if ($args{status}) {
            is($res->[0], $args{status}, "status $args{status}")
                or diag explain($res);
        }

        my $is_symlink = (-l $symlink);
        my $exists     = (-e _);
        my $cur_target = $is_symlink ? readlink($symlink) : "";

        my $te = $args{exists} // 1;
        if ($te) {
            ok($exists, "exists");
            if ($args{is_symlink} // 1) {
                ok($is_symlink, "is symlink");
            } else {
                ok(!$is_symlink, "not symlink");
            }
            unless ($args{skip_test_target}) {
                is($cur_target, $target, "target is $target");
            }
        } else {
            ok(!$exists, "does not exist");
        }

        if ($args{post_test}) {
            $args{post_test}->($res);
        }

        if ($args{cleanup}) {
            unlink $symlink;
        }
    };
}
