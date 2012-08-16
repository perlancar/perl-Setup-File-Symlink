package Setup::File::Symlink;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use File::Copy::Recursive qw(rmove);
use File::Path qw(remove_tree);
use Perinci::Sub::Gen::Undoable 0.23 qw(gen_undoable_func);
use Setup::File;
use UUID::Random;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_symlink);

# VERSION

our %SPEC;

my $res;

$res = gen_undoable_func(
    v           => 2,
    name        => 'rmsym',
    summary     => 'Delete symlink',
    description => <<'_',

Will not delete non-symlinks.

Fixed state: `path` doesn't exist.

Fixable state: `path` exists, is a symlink, (and if `target` is defined, points
to `target`).

_
    args        => {
        path => {
            schema => 'str*',
        },
        target => {
            summary => 'Only delete if existing symlink has this target',
            schema => 'str*',
        },
    },
    check_args => sub {
        # TMP, schema
        my $args = shift;
        defined($args->{path}) or return [400, "Please specify path"];
        [200, "OK"];
    },
    check_or_fix_state => sub {
        my ($which, $args, $undo) = @_;

        my $do_log   = !$args->{-check_state};
        my $path     = $args->{path};
        my $target   = $args->{target};
        my $is_sym   = (-l $path);
        my $exists   = $is_sym || (-e _);
        my $curtarget; $curtarget = readlink($path) if $is_sym;
        my @u;
        if ($which eq 'check') {
            return [412, "Not a symlink"] if $exists && !$is_sym;
            return [412, "Target does not match ($curtarget)"] if $is_sym &&
                defined($target) && $curtarget ne $target;
            if ($exists) {
                $log->info("nok: Symlink $path should be removed") if $do_log;
                push @u, [__PACKAGE__.'::ln_s', {
                    symlink => $path,
                    target  => $target // $curtarget,
                }];
            }
            return @u ? [200,"OK",undef,{undo_data=>\@u}]:[304,"Nothing to do"];
        }
        if (unlink $path) {
            return [200, "OK"];
        } else {
            return [500, "Can't remove symlink: $!"];
        }
    },
);
die "Can't generate rmsym: $res->[0] - $res->[1]" unless $res->[0] == 200;

$res = gen_undoable_func(
    v           => 2,
    name        => 'ln_s',
    summary     => 'Create symlink',
    description => <<'_',

Fixed state: `symlink` exists and points to `target`.

Fixable state: `symlink` doesn't exist.

_
    args        => {
        symlink => {
            summary => 'Path to symlink',
            schema => 'str*',
        },
        target => {
            summary => 'Path to target',
            schema => 'str*',
        },
    },
    check_args => sub {
        # TMP, schema
        my $args = shift;
        defined($args->{symlink}) or return [400, "Please specify symlink"];
        [200, "OK"];
    },
    check_or_fix_state => sub {
        my ($which, $args, $undo) = @_;

        my $do_log   = !$args->{-check_state};
        my $symlink  = $args->{symlink};
        my $target   = $args->{target};
        my $is_sym   = (-l $symlink);
        my $exists   = $is_sym || (-e _);
        my $curtarget; $curtarget = readlink($symlink) if $is_sym;
        my @u;
        if ($which eq 'check') {
            return [412, "Path already exists"] if $exists && !$is_sym;
            return [412, "Symlink points to another target"] if $is_sym &&
                $curtarget ne $target;
            if (!$exists) {
                $log->info("nok: Symlink $symlink -> $target should be created")
                    if $do_log;
                push @u, [__PACKAGE__.'::rmsym', {path => $symlink}];
            }
            return @u ? [200,"OK",undef,{undo_data=>\@u}]:[304,"Nothing to do"];
        }
        if (symlink $target, $symlink) {
            return [200, "OK"];
        } else {
            return [500, "Can't symlink: $!"];
        }
    },
);
die "Can't generate ln_s: $res->[0] - $res->[1]" unless $res->[0] == 200;

$res = gen_undoable_func(
    v => 2,
    name        => 'setup_symlink',
    summary     => "Setup symlink (existence, target)",
    description => <<'_',

On do, will create symlink which points to specified target. If symlink already
exists but points to another target, it will be replaced with the correct
symlink if `replace_symlink` option is true. If a file already exists, it will
be removed (or, backed up to temporary directory) before the symlink is created,
if `replace_file` option is true.

On undo, will delete symlink if it was created by this function, and restore the
original symlink/file/dir if it was replaced during do.

_
    trash_dir   => 1,
    req_tx      => 1,
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
            pos => 0,
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

    check_args => sub {
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

    check_or_fix_state => sub {
        my ($which, $args, $undo) = @_;
        my $is_check = $which eq 'check';

        my $do_log     = !$args->{-check_state};
        my $dry_run    = $args->{-dry_run};
        my $tm         = $args->{-tx_manager};
        my $log_call   = $args->{-log_call} // 1;
        my $symlink    = $args->{symlink};
        my $target     = $args->{target};

        my $is_symlink = (-l $symlink); # -l performs lstat()
        my $exists     = (-e _);    # now we can use -e
        my $is_dir     = (-d _);
        my $cur_target = $is_symlink ? readlink($symlink) : "";

        my $save       = "$args->{-undo_trash_dir}/". UUID::Random::generate;

        my (@u, @d);

        if ($exists && !$is_symlink) {
            $log->info("nok: ".($is_dir ? "Dir" : "File")." $symlink ".
                           "should be replaced by symlink") if $do_log;
            if ($is_dir && !$args->{replace_dir}) {
                return [412, "must replace dir but instructed not to"];
            } elsif (!$args->{replace_file}) {
                return [412, "must replace file but instructed not to"];
            }
            if ($is_check) {
                push @u, (
                    [__PACKAGE__."::rmsym",
                     {path=>$symlink, target=>$target}],
                    ["Setup::File::mv",
                     {from=>$save, to=>$symlink}],
                );
            } else {
                push @d, (
                    ["Setup::File::rm_r",
                     {path=>$symlink, save_path=>$undo->[1][1]{from}}],
                    [__PACKAGE__."::ln_s",
                     {symlink=>$symlink, target=>$target}],
                );
            }
        } elsif ($is_symlink && $cur_target ne $target) {
            $log->infof("nok: Symlink $symlink doesn't point to correct target".
                            " $target") if $do_log;
            if (!$args->{replace_symlink}) {
                return [412, "must replace symlink but instructed not to"];
            }
            if ($is_check) {
                push @u, (
                    [__PACKAGE__."::rmsym",
                     {path=>$symlink, target=>$target}],
                    [__PACKAGE__."::ln_s",
                     {symlink=>$symlink, target=>$cur_target}],
                );
            } else {
                push @d, (
                    ["Setup::File::rm_r",
                     {path=>$symlink, save_path=>$undo->[1][1]{from}}],
                    [__PACKAGE__."::ln_s",
                     {symlink=>$symlink, target=>$target}],
                );
            }
        } elsif (!$exists) {
            $log->infof("nok: $symlink doesn't exist");
            if (!$args->{create}) {
                return [412, "must create symlink but instructed not to"];
            }
            if ($is_check) {
                push @u, (
                    [__PACKAGE__."::rmsym",
                     {path=>$symlink}],
                );
            } else {
                push @d, (
                    [__PACKAGE__."::ln_s",
                     {symlink=>$symlink, target=>$target}],
                );
            }
        }

        if ($is_check) {
            return [200, "OK", undef, {undo_data=>\@u}];
        } else {
            # since we'll be calling other transactional functions,
            # which will record undo data also.
            $tm->_empty_undo_data;
            return $tm->call(calls => \@d, dry_run=>$dry_run);
        }
    },
);
die "Can't generate ln_s: $res->[0] - $res->[1]" unless $res->[0] == 200;

1;
# ABSTRACT: Setup symlink (existence, target)

=head1 SEE ALSO

L<Setup>

L<Setup::File>

=cut
