package Setup::File::Symlink;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use Data::Dump::Partial qw(dumpp);
use File::Copy::Recursive qw(rmove);
use File::Path qw(remove_tree);
use Perinci::Sub::Gen::Undoable qw(gen_undoable_func);
use UUID::Random;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_symlink);

# VERSION

our %SPEC;

my $res = gen_undoable_func(
    name        => __PACKAGE__ . '::setup_symlink',
    summary     => "Setup symlink (existence, target)",
    description => <<'_',

On do, will create symlink which points to specified target. If symlink already
exists but points to another target, it will be replaced with the correct
symlink if replace_symlink option is true. If a file already exists, it will be
removed (or, backed up to temporary directory) before the symlink is created, if
replace_file option is true.

On undo, will delete symlink if it was created by this function, and restore the
original symlink/file/dir if it was replaced during do.

_
    tx          => {use=>1},
    trash_dir   => 1,
    args        => {
        symlink => {
            summary => 'Path to symlink',
            schema => ['str*' => {match => qr!^/!}],
            req => 1,
            pos => 1,
            description => <<'_',

Symlink path needs to be absolute so it's normalized.

_
        },
        target => {
            summary => 'Target path of symlink',
            schema => 'str*',
            req => 1,
            pos => 1,
        },
        create => {
            summary => "Create if symlink doesn't exist",
            schema => [bool => {default=>1}],
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

_
        },
        replace_symlink => {
            summary => "Replace previous symlink if it already exists ".
                "but doesn't point to the wanted target",
            schema => ['bool' => {default => 1}],
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

_
        },
        replace_file => {
            summary => "Replace if there is existing non-symlink file",
            schema => ['bool' => {default => 0}],
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

_
        },
        replace_dir => {
            summary => "Replace if there is existing dir",
            schema => ['bool' => {default => 0}],
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

_
        },
    },

    hook_check_args => sub {
        my $args = shift;
        $args->{symlink}         or return [400, "Please specify symlink"];
        defined($args->{target}) or return [400, "Please specify target"];
        $args->{symlink} =~ m!^/!
            or return [400, "Please specify an absolute path for symlink"];
        $args->{create}          //= 1;
        $args->{replace_file}    //= 0;
        $args->{replace_dir}     //= 0;
        $args->{replace_symlink} //= 1;
        [200, "OK"];
    },

    build_steps => sub {
        my %args = @_;

        my $symlink    = $args{symlink};
        my $target     = $args{target};

        my $is_symlink = (-l $symlink); # -l performs lstat()
        my $exists     = (-e _);        # now we can use -e
        my $is_dir     = (-d _);
        my $cur_target = $is_symlink ? readlink($symlink) : "";

        my @steps;
        if ($exists && !$is_symlink) {
            $log->infof("nok: $symlink exists but not a symlink");
            if ($is_dir) {
                if (!$args{replace_dir}) {
                    return [412, "must replace dir but instructed not to"];
                }
                push @steps, ["rm_r"], ["ln"];
            } else {
                if (!$args{replace_file}) {
                    return [412, "must replace file but instructed not to"];
                }
                push @steps, ["rm_r"], ["ln"];
            }
        } elsif ($is_symlink && $cur_target ne $target) {
            $log->infof("nok: $symlink doesn't point to correct target");
            if (!$args{replace_symlink}) {
                return [412, "must replace symlink but instructed not to"];
            }
            push @steps, ["rmsym"], ["ln"];
        } elsif (!$exists) {
            $log->infof("nok: $symlink doesn't exist");
            if (!$args{create}) {
                return [412, "must create symlink but instructed not to"];
            }
            push @steps, ["ln"];
        }

        [200, "OK", \@steps];
    },

    steps => {
        rm_r => {
            summary => 'Delete file/dir that is to be replaced by symlink',
            description => <<'_',
It actually moves the file/dir to a unique name in trash and save the unique
_name as undo data.
_
            gen_undo => sub {
                my ($args, $step) = @_;
                my $f  = $args->{symlink};
                my $sp = "$args->{-undo_trash_dir}/".
                    UUID::Random::generate;
                if ((-l $f) || (-e _)) {
                    return ["restore", $sp];
                }
                return;
            },
            run => sub {
                my ($args, $step, $undo) = @_;
                my $f  = $args->{symlink};
                if (rmove $f, $undo->[1]) {
                    return [200, "OK"];
                } else {
                    return [500, "Can't move $f -> $undo->[1]: $!"];
                }
            },
        },
        restore => {
            summary => 'Restore file/dir previously deleted by rm_r',
            description => <<'_',
Rename back file/dir in the trash to the original path.
_
            gen_undo => sub {
                my ($args, $step) = @_;
                return ["rm_r"];
            },
            run => sub {
                my ($args, $step, $undo) = @_;
                my $f  = $args->{symlink};
                if ((-l $f) || (-e _)) {
                    return [412, "Can't restore $step->[1]: $f exists"];
                } elsif (!(rmove $step->[1], $f)) {
                    return [500, "Can't restore $step->[1] -> $f: $!"];
                }
            },
        },
        rmsym => {
            summary => 'Delete symlink',
            description => <<'_',
The original symlink target is saved as undo data.
_
            gen_undo => sub {
                my ($args, $step) = @_;
                my $s = $args->{symlink};
                if ((-l $s) || (-e _)) {
                    my $t = readlink($s) // "";
                    return ["ln", $t];
                }
                return;
            },
            run => sub {
                my ($args, $step, $undo) = @_;
                my $s = $args->{symlink};

                if (unlink $s) {
                    return [200, "OK"];
                } else {
                    return [500, "Can't remove $s: $!"];
                }
            },
        },
        ln => {
            summary => 'Create symlink',
            description => <<'_',
Create symlink which points to arg[1], or by default to 'target'.
_
            gen_undo => sub {
                my ($args, $step) = @_;
                my $s = $args->{symlink};
                my $t = $step->[1] // $args->{target};
                unless ((-l $s) && readlink($s) eq $t) {
                    return ["rmsym"];
                }
                return;
            },
            run => sub {
                my ($args, $step, $undo) = @_;
                my $s = $args->{symlink};
                my $t = $step->[1] // $args->{target};
                if (symlink $t, $s) {
                    return [200, "OK"];
                } else {
                    return [500, "Can't symlink $s -> $t: $!"];
                }
            },
        },
    },
);

die "Can't generate setup_symlink(): $res->[0] - $res->[1]"
    unless $res->[0] == 200;
$SPEC{setup_symlink} = $res->[2]{meta};

1;
# ABSTRACT: Setup symlink (existence, target)

=head1 SYNOPSIS

 use Setup::File::Symlink 'setup_symlink';

 # simple usage (doesn't save undo data)
 my $res = setup_symlink symlink => "/baz", target => "/qux";
 die unless $res->[0] == 200 || $res->[0] == 304;

 # perform setup and save undo data
 my $res = setup_symlink symlink => "/foo", target => "/bar",
                         -undo_action => 'do';
 die unless $res->[0] == 200 || $res->[0] == 304;
 my $undo_data = $res->[3]{undo_data};

 # perform undo
 my $res = setup_symlink symlink => "/symlink", target=>"/target",
                         -undo_action => "undo", -undo_data=>$undo_data;
 die unless $res->[0] == 200;


=head1 DESCRIPTION

This module uses L<Log::Any> logging framework.

This module has L<Rinci> metadata.


=head1 SEE ALSO

L<Setup>

L<Setup::File>

=cut
