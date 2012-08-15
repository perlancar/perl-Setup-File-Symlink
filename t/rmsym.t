#!perl

use 5.010;
use strict;
use warnings;
use Test::More 0.96;

use File::chdir;
use File::Slurp;
use File::Temp qw(tempdir);
use Setup::File::Symlink;
use Test::Setup qw(test_setup);

plan skip_all => "symlink() not available"
    unless eval { symlink "", ""; 1 };

my $rootdir = tempdir(CLEANUP=>1);
$CWD = $rootdir;

symlink "x", "$rootdir/s";
test_rmsym(
    name          => "fixable",
    path          => "/s",
    check_unsetup => {exists=>1},
    check_setup   => {exists=>0},
);

symlink "x", "$rootdir/s";
test_rmsym(
    name          => "unfixable: target does not match",
    path          => "/s",
    target        => "y",
    check_unsetup => {exists=>1},
    dry_do_error  => 412,
);

unlink "$rootdir/s"; write_file("$rootdir/s", "");
test_rmsym(
    name          => "unfixable: path not symlink",
    path          => "/s",
    check_unsetup => {exists=>1, is_symlink=>0},
    dry_do_error  => 412,
);

DONE_TESTING:
done_testing();
if (Test::More->builder->is_passing) {
    #diag "all tests successful, deleting test data dir";
    $CWD = "/";
} else {
    diag "there are failing tests, not deleting test data dir $rootdir";
}

sub test_rmsym {
    my (%targs) = @_;

    my %tsargs;

    for (qw/name dry_do_error do_error set_state1 set_state2 prepare cleanup/) {
        $tsargs{$_} = $targs{$_};
    }
    $tsargs{function} = \&Setup::File::Symlink::rmsym;

    my $path = $rootdir . $targs{path};
    my $target; $target = $rootdir . $targs{target} if $targs{target};
    my %fargs = (path => $path, target => $target,
                 %{$targs{other_args} // {}},
             );
    $tsargs{args} = \%fargs;

    my $check = sub {
        my %cargs = @_;

        my $is_symlink = (-l $path);
        my $exists     = (-e _);
        my $cur_target = $is_symlink ? readlink($path) : "";

        my $te = $cargs{exists} // 1;
        if ($te) {
            ok($exists, "exists");
            if ($cargs{is_symlink} // 1) {
                ok($is_symlink, "is symlink");
                if (defined $cargs{target}) {
                    is($cur_target, $cargs{target}, "target is $cargs{target}");
                }
            } else {
                ok(!$is_symlink, "not symlink");
            }
        } else {
            ok(!$exists, "does not exist");
        }
        if ($cargs{extra}) {
            $cargs{extra}->();
        }
    };

    $tsargs{check_setup}   = sub { $check->(%{$targs{check_setup}}) };
    $tsargs{check_unsetup} = sub { $check->(%{$targs{check_unsetup}}) };
    if ($targs{check_state1}) {
        $tsargs{check_state1} = sub { $check->(%{$targs{check_state1}}) };
    }
    if ($targs{check_state2}) {
        $tsargs{check_state2} = sub { $check->(%{$targs{check_state2}}) };
    }

    test_setup(%tsargs);
}
