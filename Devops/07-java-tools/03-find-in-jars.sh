#!/bin/bash
# 在目录下所有jar文件里，查找类或资源文件。

# @Function
# Find files in the jar files under specified directory, search jar files recursively(include subdirectory).
#
# @Usage
#   $ find-in-jars 'log4j\.properties'
#   # search file log4j.properties/log4j.xml at zip root
#   $ find-in-jars '^log4j\.(properties|xml)$'
#   $ find-in-jars 'log4j\.properties$' -d /path/to/find/directory
#   $ find-in-jars '\.properties$' -d /path/to/find/dir1 -d path/to/find/dir2
#   $ find-in-jars 'Service\.class$' -e jar -e zip
#   $ find-in-jars 'Mon[^$/]*Service\.class$' -s ' <-> '
#
# @online-doc https://github.com/oldratlee/useful-scripts/blob/dev-2.x/docs/java.md#-find-in-jars
# @author Jerry Lee (oldratlee at gmail dot com)
#
# NOTE about Bash Traps and Pitfalls:
#
# 1. DO NOT combine var declaration and assignment which value supplied by subshell!
#    for example: readonly var1=$(echo value1)
#                 local var1=$(echo value1)
#
#    declaration make exit code of assignment to be always 0,
#      aka. the exit code of command in subshell is discarded.
#      tested on bash 3.2.57/4.2.46
set -eEuo pipefail

# NOTE: DO NOT declare var PROG as readonly, because its value is supplied by subshell.
PROG="$(basename "$0")"
readonly PROG_VERSION='2.4.0-dev'

################################################################################
# util functions
################################################################################

# NOTE: $'foo' is the escape sequence syntax of bash
readonly ec=$'\033'      # escape char
readonly eend=$'\033[0m' # escape end
readonly nl=$'\n'        # new line
# How to delete line with echo?
# https://unix.stackexchange.com/questions/26576
#
# terminal escapes: http://ascii-table.com/ansi-escape-sequences.php
# In particular, to clear from the cursor position to the beginning of the line:
# echo -e "\033[1K"
# Or everything on the line, regardless of cursor position:
# echo -e "\033[2K"
readonly clear_line=$'\033[2K\r'

redEcho() {
    # -t check: is a terminal device?
    [ -t 1 ] && echo "${ec}[1;31m$*$eend" || echo "$*"
}

# Getting console width using a bash script
# https://unix.stackexchange.com/questions/299067
#
# NOTE: DO NOT declare columns var as readonly, because its value is supplied by subshell.
[ -t 2 ] && columns=$(stty size | awk '{print $2}')

printResponsiveMessage() {
    if ! $show_responsive || [ ! -t 2 ]; then
        return
    fi

    local message="$*"
    # http://www.linuxforums.org/forum/red-hat-fedora-linux/142825-how-truncate-string-bash-script.html
    echo -n "$clear_line${message:0:columns}" >&2
}

clearResponsiveMessage() {
    if ! $show_responsive || [ ! -t 2 ]; then
        return
    fi

    echo -n "$clear_line" >&2
}

die() {
    clearResponsiveMessage
    redEcho "Error: $*" 1>&2
    exit 1
}

usage() {
    local -r exit_code="${1:-0}"
    (($# > 0)) && shift
    # shellcheck disable=SC2015
    [ "$exit_code" != 0 ] && local -r out=/dev/stderr || local -r out=/dev/stdout

    (($# > 0)) && redEcho "$*$nl" >$out

    cat >$out <<EOF
Usage: ${PROG} [OPTION]... PATTERN

Find files in the jar files under specified directory,
search jar files recursively(include subdirectory).
The pattern default is *extended* regex.

Example:
  ${PROG} 'log4j\.properties'
  # search file log4j.properties/log4j.xml at zip root
  ${PROG} '^log4j\.(properties|xml)$'
  ${PROG} 'log4j\.properties$' -d /path/to/find/directory
  ${PROG} '\.properties$' -d /path/to/find/dir1 -d path/to/find/dir2
  ${PROG} 'Service\.class$' -e jar -e zip
  ${PROG} 'Mon[^$/]*Service\.class$' -s ' <-> '

Find control:
  -d, --dir              the directory that find jar files.
                         default is current directory. this option can specify
                         multiply times to find in multiply directories.
  -e, --extension        set find file extension, default is jar. this option
                         can specify multiply times to find multiply extension.
  -E, --extended-regexp  PATTERN is an extended regular expression (*default*)
  -F, --fixed-strings    PATTERN is a set of newline-separated strings
  -G, --basic-regexp     PATTERN is a basic regular expression
  -P, --perl-regexp      PATTERN is a Perl regular expression
  -i, --ignore-case      ignore case distinctions

Output control:
  -a, --absolute-path    always print absolute path of jar file
  -s, --separator        specify the separator between jar file and zip entry.
                         default is \`!'.
  -L, --files-not-contained-found
                         print only names of JAR FILEs NOT contained found
  -l, --files-contained-found
                         print only names of JAR FILEs contained found
  -R, --no-find-progress do not display responsive find progress

Miscellaneous:
  -h, --help             display this help and exit
  -V, --version          display version information and exit
EOF

    exit "$exit_code"
}

progVersion() {
    echo "$PROG $PROG_VERSION"
    exit
}

################################################################################
# parse options
################################################################################

declare -a dirs=()
declare -a extensions=()
declare -a args=()

separator='!'
regex_mode=-E
use_absolute_path=false
show_responsive=true
only_print_file_name=false

while (($# > 0)); do
    case "$1" in
    -d | --dir)
        dirs=(${dirs[@]:+"${dirs[@]}"} "$2")
        shift 2
        ;;
    -e | --extension)
        extensions=(${extensions[@]:+"${extensions[@]}"} "$2")
        shift 2
        ;;
    -E | --extended-regexp)
        regex_mode=-E
        shift
        ;;
    -F | --fixed-strings)
        regex_mode=-F
        shift
        ;;
    -G | --basic-regexp)
        regex_mode=-G
        shift
        ;;
    -P | --perl-regexp)
        regex_mode=-P
        shift
        ;;
    -i | --ignore-case)
        ignore_case_option=-i
        shift
        ;;
    -a | --absolute-path)
        use_absolute_path=true
        shift
        ;;
    # support the typo option name --seperator for compatibility
    -s | --separator | --seperator)
        separator="$2"
        shift 2
        ;;
    -L | --files-not-contained-found)
        only_print_file_name=true
        print_matched_files=false
        shift
        ;;
    -l | --files-contained-found)
        only_print_file_name=true
        print_matched_files=true
        shift
        ;;
    -R | --no-find-progress)
        show_responsive=false
        shift
        ;;
    -h | --help)
        usage
        ;;
    -V | --version)
        progVersion
        ;;
    --)
        shift
        args=(${args[@]:+"${args[@]}"} "$@")
        break
        ;;
    -*)
        usage 2 "${PROG}: unrecognized option '$1'"
        ;;
    *)
        args=(${args[@]:+"${args[@]}"} "$1")
        shift
        ;;
    esac
done

# shellcheck disable=SC2178
dirs=${dirs:-.}
# shellcheck disable=SC2178
extensions=${extensions:-jar}

(("${#args[@]}" == 0)) && usage 1 "No find file pattern!"
(("${#args[@]}" > 1)) && usage 1 "More than 1 file pattern: ${args[*]}"
readonly pattern="${args[0]}"

declare -a tmp_dirs=()
for d in "${dirs[@]}"; do
    [ -e "$d" ] || die "file $d(specified by option -d) does not exist!"
    [ -d "$d" ] || die "file $d(specified by option -d) exists but is not a directory!"
    [ -r "$d" ] || die "directory $d(specified by option -d) exists but is not readable!"

    # convert dirs to Absolute Path if has option -a, --absolute-path
    $use_absolute_path && tmp_dirs=(${tmp_dirs[@]:+"${tmp_dirs[@]}"} "$(cd "$d" && pwd)")
done
# set dirs to Absolute Path
$use_absolute_path && dirs=("${tmp_dirs[@]}")

# convert extensions to find -iname options
find_iname_options=()
for e in "${extensions[@]}"; do
    (("${#find_iname_options[@]}" == 0)) &&
        find_iname_options=(-iname "*.$e") ||
        find_iname_options=("${find_iname_options[@]}" -o -iname "*.$e")
done

################################################################################
# Check the existence of command for listing zip entry!
################################################################################

# `zipinfo -1`/`unzip -Z1` is ~25 times faster than `jar tf`, find zipinfo/unzip command first.
#
# How to list files in a zip without extra information in command line
# https://unix.stackexchange.com/a/128304/136953
if command -v zipinfo &>/dev/null; then
    readonly command_for_list_zip='zipinfo -1'
elif command -v unzip &>/dev/null; then
    readonly command_for_list_zip='unzip -Z1'
else
    if ! command -v jar &>/dev/null; then
        [ -n "$JAVA_HOME" ] || die "jar not found on PATH and JAVA_HOME env var is blank!"
        [ -f "$JAVA_HOME/bin/jar" ] || die "jar not found on PATH and \$JAVA_HOME/bin/jar($JAVA_HOME/bin/jar) file does NOT exists!"
        [ -x "$JAVA_HOME/bin/jar" ] || die "jar not found on PATH and \$JAVA_HOME/bin/jar($JAVA_HOME/bin/jar) is NOT executable!"
        export PATH="$JAVA_HOME/bin:$PATH"
    fi
    readonly command_for_list_zip='jar tf'
fi

################################################################################
# find logic
################################################################################

searchJarFiles() {
    printResponsiveMessage "searching jars under dir ${dirs[*]} , ..."

    local jar_files total_jar_count

    jar_files="$(find "${dirs[@]}" "${find_iname_options[@]}" -type f)"
    [ -n "$jar_files" ] || die "No ${extensions[*]} file found!"

    total_jar_count="$(echo "$jar_files" | wc -l)"
    # delete white space
    # because the output of mac system command `wc -l` contains white space!
    total_jar_count="${total_jar_count//[[:space:]]/}"

    echo "$total_jar_count"
    echo "$jar_files"
}

__outputResultOfJarFile() {
    local jar_file="$1" file

    if $only_print_file_name; then
        local matched=false
        # NOTE: Do NOT use -q flag with grep:
        #   With the -q flag the grep program will stop immediately when the first line of data matches.
        #   Normally you shouldn't use -q in a pipeline like this
        #   unless you are sure the program at the other end can handle SIGPIPE.
        # more info see:
        # - https://stackoverflow.com/questions/19120263/why-exit-code-141-with-grep-q
        # - https://unix.stackexchange.com/questions/305547/broken-pipe-when-grepping-output-but-only-with-i-flag
        # - http://www.pixelbeat.org/programming/sigpipe_handling.html
        if grep $regex_mode ${ignore_case_option:-} -c -- "$pattern" &>/dev/null; then
            matched=true
        fi

        if [ $print_matched_files != $matched ]; then
            return
        fi

        clearResponsiveMessage
        [ -t 1 ] && echo "${ec}[1;35m${jar_file}${eend}" || echo "${jar_file}"
    else
        {
            # Prevent grep from exiting in case of no match
            # https://unix.stackexchange.com/questions/330660
            # shellcheck disable=SC2086
            grep $regex_mode ${ignore_case_option:-} ${grep_color_option:-} -- "$pattern" || true
        } | while read -r file; do
            clearResponsiveMessage
            [ -t 1 ] &&
                echo "${ec}[1;35m${jar_file}${eend}${ec}[1;32m${separator}${eend}${file}" ||
                echo "${jar_file}${separator}${file}"
        done
    fi
}

findInJarFiles() {
    [ -t 1 ] && local -r grep_color_option='--color=always'

    local counter=1 total_jar_count jar_file

    read -r total_jar_count

    while read -r jar_file; do
        printResponsiveMessage "finding in jar($((counter++))/$total_jar_count): $jar_file"
        $command_for_list_zip "${jar_file}" | __outputResultOfJarFile "${jar_file}"
    done

    clearResponsiveMessage
}

searchJarFiles | findInJarFiles
