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

test_ln_s(
    name          => "fixable",
    symlink       => "/s",
    target        => "/t",
    check_unsetup => {exists=>0},
    check_setup   => {},
    cleanup       => sub { unlink "s" },
);

write_file("$rootdir/s", "");
test_ln_s(
    name          => "unfixable: s already exists (file)",
    symlink       => "/s",
    target        => "/t",
    check_unsetup => {exists=>1, is_symlink=>0},
    check_setup   => {},
    dry_do_error  => 412,
    cleanup       => sub { unlink "s" },
);

DONE_TESTING:
done_testing();
if (Test::More->builder->is_passing) {
    #diag "all tests successful, deleting test data dir";
    $CWD = "/";
} else {
    diag "there are failing tests, not deleting test data dir $rootdir";
}

sub test_ln_s {
    my (%targs) = @_;

    my %tsargs;

    $tsargs{tmpdir} = $rootdir;

    for (qw/name dry_do_error do_error set_state1 set_state2 prepare cleanup/) {
        $tsargs{$_} = $targs{$_};
    }
    $tsargs{function} = \&Setup::File::Symlink::ln_s;

    my $symlink = $rootdir . $targs{symlink};
    my $target  = $rootdir . $targs{target};
    my %fargs = (symlink => $symlink, target => $target,
                 -undo_trash_dir=>$rootdir, %{$targs{other_args} // {}},
             );
    $tsargs{args} = \%fargs;

    my $check = sub {
        my %cargs = @_;

        my $is_symlink = (-l $symlink);
        my $exists     = (-e _);
        my $cur_target = $is_symlink ? readlink($symlink) : "";

        my $te = $cargs{exists} // 1;
        if ($te) {
            ok($exists, "exists");
            if ($cargs{is_symlink} // 1) {
                ok($is_symlink, "is symlink");
                if (defined $cargs{target}) {
                    is($cur_target, $cargs{target}, "target is $cargs{target}");
                } elsif ($cargs{test_target} // 1) {
                    is($cur_target, $target, "target is $target");
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
