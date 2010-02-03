#!/bin/bash

# Copyright (c) Daed Lee <daed@thoughtsofcode.com>
#
# Licensed under the New BSD License (the "License").
# You may not use this file except in compliance with the License.
#
# You should have received a copy of the License along with this program. If not,
# contact the copyright holder.


#########################
#   Install functions   #
#########################

install_on_mac_os_x()
{
    # Sanity check
    is_mac_os_x || log_error "$FUNCNAME() can only be called on a Mac OS X system." "$LINENO" "$FUNCNAME"
    
    # We require MacPorts to bootstrap our Rootless installation
    program_exists 'port' || log_error 'Please install MacPorts (http://www.macports.org/install.php) before installing Rootless.'
    
    # GoboLinux prerequisites. The +with_default_names part is needed so that the executables are accessible without the g prefix, otherwise for example, ls would be gls.
    sudo port selfupdate
    sudo port install coreutils +with_default_names
    sudo port install gsed +with_default_names
    sudo port install wget
    
    install_goborootless
    add_programs_to_blacklist 'Bash
GCC
Procps
Util-Linux-NG'
    post_process_install
    
    # Mac OS X doesn't ship with this and we need it to unpack libtool
    Compile --batch LZMA-Utils
    
    install_programs
    
    return 0
}


install_on_ubuntu()
{
    # Sanity check
    is_ubuntu || log_error "$FUNCNAME() can only be called on an Ubuntu system." "$LINENO" "$FUNCNAME"
    
    # GoboLinux prerequisites
    sudo aptitude update
    sudo aptitude --assume-yes install build-essential
    sudo aptitude --assume-yes install libncurses-dev
    
    # Need this to interact with CreateRootlessEnvironment
    sudo aptitude --assume-yes install expect
    
    install_goborootless
    add_programs_to_blacklist 'Bash
GCC'
    post_process_install
    
    # According to http://gobo.kundor.org/wiki/Rootless_on_Debian/Ubuntu, Ubuntu defaults to mawk instead of gawk. This difference can cause seemingly arbitrary and deeply embedded errors. We Compile Gawk within Rootless as a workaround.
    Compile --batch Gawk
    
    install_programs
    
    return 0
}


install_goborootless()
{
    # Create the Rootless install folder
    sudo mkdir -p "$install_folder"
    sudo chown "$USER":"$(id --group --name)" "$install_folder"
    
    # Download the CreateRootlessEnvironment script
    wget --directory-prefix="$HOME" 'http://svn.gobolinux.org/tools/trunk/Scripts/bin/CreateRootlessEnvironment'
    chmod u+x "$HOME"/CreateRootlessEnvironment
    
    # Need to apply this patch or else OpenSSL fails to build with a "zlib.h: No such file or directory" error.
    # Also see this: http://lists.gobolinux.org/pipermail/gobolinux-users/2009-April/008213.html
    patch --directory="$HOME" --strip=1 < "$script_folder"/CreateRootlessEnvironment.patch
    
    # Run CreateRootlessEnvironment, using expect to respond to input prompts
    expect -c '
        set timeout 40
        spawn '"$HOME"'/CreateRootlessEnvironment '"$install_folder"'
        expect_after timeout {send_user "Rootless installation failed.\n"; exit 1}
        expect {
            -ex {Press Enter to continue or Ctrl+C to abort.} {send "\r"; exp_continue}
            -ex {Recompile binaries for your system? [Y/n]} {send "y\r"; exp_continue}
            -re {1 mod: Settings/Scripts/Dependencies\.blacklist.*\[A\]uto-merge/\[V\]iew/\[U\]se new/\[S\]kip/\[L\]ist/\[M\]erge and edit/\[SA\]Skip all} {send "u\r"; exp_continue}
            -re {2 mod: Settings/bashrc.*\[A\]uto-merge/\[V\]iew/\[U\]se new/\[S\]kip/\[L\]ist/\[M\]erge and edit/\[SA\]Skip all} {send "u\r"; exp_continue}
            -re {~/\.(?:profile|bash_profile|zshrc|xprofile)\? \[Y/n\]} {send "n\r"; exp_continue}
            eof {send_user "Finished installing Rootless.\n"}
        }
    '
    
    # Delete the CreateRootlessEnvironment script since we don't need it anymore
    rm "$HOME"/CreateRootlessEnvironment
    
    return 0
}


add_programs_to_blacklist()
{
    local programs="$1"  # String containing one program per line
    
    # Add programs to the dependencies blacklist so they aren't installed by Compile
    echo -e "$programs" >> "/$install_folder"/Programs/Scripts/Settings/Scripts/Dependencies.blacklist
    
    return 0
}


post_process_install()
{
    # Comment out default aliases
    sed -i "s:\(alias .*=\):#\1:" "$install_folder"/Programs/Scripts/Settings/bashrc
    
    # Start Rootless automatically when beginning a shell session
    if ! grep "source '$install_folder/Programs/Rootless/Current/bin/StartRootless'" ~/.bashrc > /dev/null
    then
        echo "
# Start Gobo Rootless
source '$install_folder/Programs/Rootless/Current/bin/StartRootless'" >> ~/.bashrc
    fi
    
    # Start Rootless in the current session
    source "$install_folder"/Programs/Rootless/Current/bin/StartRootless
    
    # Install Compile. We don't want any dependencies because we are building everything from source.
    # TODO: We need to wrap this with expect because InstallPackage prompts us to install dependencies even though
    # we pass the --no-dependencies option. This seems to be a bug.
    expect -c '
        set timeout 40
        spawn InstallPackage --batch --no-dependencies Compile
        expect_after timeout {send_user "Compile installation failed.\n"; exit 1}
        expect {
            -re {GnuPG not installed\. Unable to verify signature.*Press Enter to continue or Ctrl-C to cancel\.} {send "\r"; exp_continue}
            -ex {[I]Install/[S]Skip/[IA]Install All/[SA]Skip All} {send "sa\r"; exp_continue}
            eof {send_user "Finished installing Compile.\n"}
        }
    '

    # Ensure that the LocalRecipes folder exists
    mkdir -p "$install_folder"/Files/Compile/LocalRecipes
    
    # Copy over custom recipes
    cp --archive "$script_folder"/Recipes/* "$install_folder"/Files/Compile/LocalRecipes
    
    if [[ -n "$recipes_folder" ]]
    then        
        # Copy over user recipes
        cp --archive "$recipes_folder"/* "$install_folder"/Files/Compile/LocalRecipes
    fi
    
    # Install mtail so we get colored output
    # TODO: Not sure why we have an old version of Scripts on a new installation.
    if [[ "$(Compile --batch Mtail 2>&1)" =~ .*"Your Scripts package is too old. Please update it by running 'InstallPackage Scripts'".* ]]
    then
        expect -c '
            set timeout 40
            spawn InstallPackage --batch --no-dependencies Scripts
            expect_after timeout {send_user "Scripts installation failed.\n"; exit 1}
            expect {
                -re {GnuPG not installed\. Unable to verify signature.*Press Enter to continue or Ctrl-C to cancel\.} {send "\r"; exp_continue}
                eof {send_user "Finished installing Scripts.\n"}
            }
        '
        Compile --batch Mtail
    fi
    
    # Install Ruby so UpdateSettings can parse hint files
    Compile --batch Ruby
    
    return 0
}


install_programs()
{
    # Utilities
    Compile --batch Zip
    Compile --batch Unzip
    Compile --batch Rsync
    Compile --batch Tree
    
    # LAMP
    Compile --batch HTTPD
    Compile --batch MySQL
    Compile --batch Mod_PHP
    Compile --batch PHP
    
    # Version control
    Compile --batch Git
    Compile --batch Mercurial
    Compile --batch Subversion
    
    return 0
}


#########################
#   Utility functions   #
#########################

is_mac_os_x()
{
    if [[ "$(uname)" == Darwin ]]
    then
        return 0
    else
        return 1
    fi
}


is_ubuntu()
{
    # Ensure the lsb_release command exists
    program_exists 'lsb_release' || return 1
    
    # Ensure the output of lsb_release contains the string "Ubuntu"
    [[ "$(lsb_release -d)" =~ .*Ubuntu.* ]] || return 1
    
    return 0
}


program_exists()
{
    local program_name="$1"
    
    if [[ -n "$(type -p "$program_name")" ]]
    then
        return 0
    else
        return 1
    fi
}


################################
#   Error handling functions   #
################################

handle_errors()
{
    # Exit if a command fails
    set -o errexit
    
    # Exit if a command at the start or in the middle of a pipeline fails
    set -o pipefail
    
    # Trap failed commands and record the line number and function name if available
    trap 'log_error "Trapped failed command" "$LINENO" "$FUNCNAME"' ERR
    
    # Enable error tracing, so that functions, command substitutions, and subshell commands inherit the ERR trap.
    set -o errtrace
    
    return 0
}


log_error()
{
    # The error message parameter is required
    local error_message="$1"
    
    # The line number and function name parameters are optional. Set the local variable to to an empty string if its corresponding parameter is not passed to this function.
    local line_number_text="${2:+line $2: }"
    local function_name_text="${3:+$3(): }"
    
    # Send the error message to standard error
    echo "${line_number_text}${function_name_text}${error_message}" 1>&2
    
    exit 1
}


#################
#   Main code   #
#################

handle_errors

while getopts 'hi:r:' option
do
    case "$option" in
        h) log_error 'Usage: goborootless.sh [-h] [-i install folder] [-r recipes folder]';;
        i) install_folder="$OPTARG";;
        r) recipes_folder="$OPTARG";;
    esac
done
shift $((OPTIND-1))  # Get rid of the option arguments

# The folder this script is located in
script_folder="$(dirname "$(readlink --canonicalize-existing --no-newline "$0")")"

# Set the default install folder if it's not specified
install_folder="${install_folder:-$PWD/GoboRootless}"

if is_mac_os_x
then
    install_on_mac_os_x
elif is_ubuntu
then
    install_on_ubuntu
else
    log_error 'Unsupported system. Only Mac OS X and Ubuntu are currently supported.'
fi