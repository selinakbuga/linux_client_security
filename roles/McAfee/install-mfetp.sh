#!/bin/bash
# Copyright (C) 2016-2021 Musarubra US LLC. All Rights Reserved.
# Script to do installation for McAfee Endpoint Security Platform for Linux and McAfee Endpoint Security for Linux Threat Prevention
# Standalone installation supports silent (without EULA) and prompt (with EULA) installation type
# ePO installation supports only epo (with DAT extraction and without EULA) installation type
# Script also supports upgrading from VSEL 1.9.x / 2.0.x

# Exit codes on failure in this script are
# 1 - This script can be run by bash shell only.
# 3 - Invalid command line option passed during installation. Please see KB88299.
# 5 - Must be a root user to run this script.
# 6 - 64bit MFEcma 5.6.4-110 or above is required for installation to continue.
# 7 - Installation file is missing.
# 8 - Installation RPM or DEB file is missing.
# 9 - Installation failed.
# 10 - Failed to extract downloaded installation file.
# 11 - Installation aborted after EULA was rejected.
# 12 - Installation aborted as EULA could not be shown.
# 13 - Installation failed after DAT could not be extracted.
# 14 - Uninstallation failed.
# 15 - Installation was successful. Please reboot the system to complete the installation.
# 17 - Installation conflicts with existing FW installation.
# 19 - Product is unsupported on this distribution. Please see KB87073.
# 22 - Product Installation failed due to insufficient space in tmp directory.
# 24 - Product Installation failed due to insufficient space in install directory.
# 26 - Product Installation failed due to insufficient space in var directory.
# 0 - Installation was successful
# NOTE: Exit codes are kept uniform for all installation and uninstallation scripts

# Use only bash for executing the script
ps -o args= -p "$$" | grep bash > /dev/null
if [ $? -ne 0 ]
then
    echo "Error: This script can be run by bash shell only"
    echo "Usage: $0 [installtype] [oasoff] [usefanotify] [gtioff] [apoff] [apon] [nocontentupdate] [alttmppath=/home/installfolder] [usedeferredscan] [oascpulimit=value]"
    echo "'oasoff' is an optional parameter which can be used to prevent OAS from starting automatically after installation"
    echo "'usefanotify' is an optional parameter which can be used to give preference to use fanotify for OAS for supported systems instead of using kernel modules"
    echo "'gtioff' is an optional parameter which can be used to prevent sending of queries to GTI after installation"
    echo "'apoff' is an optional parameter which can be used to turn off Access Protection. In the absence of this, Access Protection would be enabled for ePO installation."
    echo "'apon' is an optional parameter which can be used to turn on Access Protection. In the absence of this, Access Protection would be disabled by default for standalone installation."
    echo "'nocontentupdate' is an optional parameter which can be used to disable the first-time content update which is run after ENSL start-up."
    echo "'alttmppath' is an optional parameter which can be used to change the default folder location from where ENSL gets installed. In the absence of this, ENSL will be installed from /tmp folder by default."
    echo "'usedeferredscan' is an optional parameter which can be used to enable OAS deferred scanning in fanotify supported systems"
    echo "'oascpulimit' is an optional parameter which can be used to set CPU usage limit for OAS in fanotify supported systems"
    exit 1
fi

# Reset the LANG to C
unset LC_ALL
unset LANG
export LANG=C
export LC_ALL=C
# Set this to 1, if this is a ePO installer
ePOInstaller=0

# ePO Installer script should not be executed in standalone mode
if [ ${ePOInstaller} = 1 -a -t 1 ]
then
    echo "ERROR: This script should be run only by McAfee agent and does not support standalone installation"
    echo "Use the standalone installer instead"
    exit 9
fi

# Store mfetpd service status
serviceRunning=true

# Flag to check if isectp is currently installed
# 0 - Not installed, 1 - Installed
isectpInstalled=0

#unset the LD_LIBRARY_PATH
unset LD_LIBRARY_PATH

usage()
{
    echo "Usage: $0 [installtype] [oasoff] [usefanotify] [gtioff] [apoff] [apon] [nocontentupdate] [alttmppath=/home/installfolder] [usedeferredscan] [oascpulimit=value]"
    if [ "${ePOInstaller}" -eq 0 ]
    then
        echo "Install type can be 'silent' or 'prompt'"
    else
        echo "Install type can be 'epo'"
    fi
    echo "'oasoff' is an optional parameter which can be used to prevent OAS from starting automatically after installation"
    echo "'usefanotify' is an optional parameter which can be used to give preference to use fanotify for OAS for supported systems instead of using kernel modules"
    echo "'gtioff' is an optional parameter which can be used to prevent sending of queries to GTI after installation"
    echo "'apoff' is an optional parameter which can be used to turn off Access Protection. In the absence of this, Access Protection would be enabled."
    echo "'apon' is an optional parameter which can be used to turn on Access Protection. In the absence of this, Access Protection would be disabled by default for standalone installation."
    echo "'nocontentupdate' is an optional parameter which can be used to disable the first-time content update which is run after ENSL start-up."
    echo "'alttmppath' is an optional parameter which can be used to change the default folder location from where ENSL gets installed. In the absence of this, ENSL will be installed from /tmp folder by default."
    echo "'usedeferredscan' is an optional parameter which can be used to enable OAS deferred scanning in fanotify supported systems"
    echo "'oascpulimit' is an optional parameter which can be used to set CPU usage limit for OAS in fanotify supported systems"
    exit 3
}

# Function to log messages to stdout and syslog
logMessage()
{
    echo "${1}"
    logger -t "${me}" "${1}"
    # If running in prompt mode, save the output to the log file as well
    if [ -n "${installType}" ]
    then
        if [ ${installType} = "prompt" ]
        then
            echo "${1}" >> ${log}
        fi
    fi
}

# Function to log an empty line to stdout only
showNewLine()
{
    echo ""
}

# Compares two product versions a and b and return its value. Both should be in 10.2.2.1105 format
# Returns 1 for more (a > b), 2 for less (a < b) and 0 for equal version (a == b)
vercomp () {
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    a=$1
    b=$2
    a=$(echo ${a}| sed 's/-/./')
    b=$(echo ${b} | sed 's/-/./')
    local IFS=.
    local i ver1=($a) ver2=($b)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

restoreProcessStateAndAbort()
{
    installFailExitCode=$1
    restoreProcessState
    cleanup ${installFailExitCode}
}

# Check if any incompatible products are installed
# 1st param - Product Name
# 2nd param - Product Description
# 3rd param - Minimum supported product version
checkForIncompatibleProduct()
{
    productName=$1
    productDesc=$2
    minProductVersion=$3
    if [ "${DEB_VARIANT}" = "no" ]
    then
        INSTALLED_PROD_VERSION_STRING=$(rpm -qa --queryformat "%{NAME}-%{VERSION}.%{RELEASE}\n" | grep -i $productName | sort | head -1)
        if [ ! -z "${INSTALLED_PROD_VERSION_STRING}" ]
        then
            INSTALLED_PROD_VERSION_INT=$(echo "${INSTALLED_PROD_VERSION_STRING}" | awk -F '-' '{print $2}')
        fi
    else
        INSTALLED_PROD_VERSION_STRING=$(dpkg -s $productName 2>/dev/null  | grep ^Version | awk -F ': ' '{print $2}')
        if [ ! -z "${INSTALLED_PROD_VERSION_STRING}" ]
        then
            INSTALLED_PROD_VERSION_INT=$(echo "${INSTALLED_PROD_VERSION_STRING}" | sed -e 's:-:.:g')
        fi
    fi
    if [ ! -z "${INSTALLED_PROD_VERSION_INT}" ]
    then
        vercomp ${minProductVersion} ${INSTALLED_PROD_VERSION_INT}
        returnValue=$?
        if [ "${returnValue}" -eq 1 ]
        then
            logMessage "Existing $productDesc ${INSTALLED_PROD_VERSION_INT} is incompatible with McAfee Endpoint Security for Linux Threat Prevention 10.7.9-31. Aborting installation."
            restoreProcessStateAndAbort 19
        fi
    fi
}

#check if the service state (running or stopped)
checkIfServiceIsRunning()
{
    serviceName="mfetpd"
    if [ "${isectpInstalled}" -eq 1 ]
    then
        serviceName="isectpd"
    fi
    if (( $(ps -ef | grep -v grep | grep $serviceName | wc -l) > 0 ))
    then
        serviceRunning=true
    else
        serviceRunning=false
    fi
}

#Function to restore the state of mfetpd
restoreProcessState()
{
    if [ $serviceRunning == true ]
    then
        if [ "${isectpInstalled}" -eq 1 ]
        then
            /opt/isec/ens/threatprevention/bin/isectpdControl.sh start 2>/dev/null || :
        else
            /opt/McAfee/ens/tp/init/mfetpd-control.sh start 2>/dev/null || :
        fi
    else
        if [ "${isectpInstalled}" -eq 1 ]
        then
            /opt/isec/ens/threatprevention/bin/isectpdControl.sh stop 2>/dev/null || :
        else
            /opt/McAfee/ens/tp/init/mfetpd-control.sh stop 2>/dev/null || :
        fi
    fi
}

# check for disk space in the supplied directory
# $1 specifies the directory for space check
# $2 specifies the required space for that directory
# $3 specifies the error code to be returned if there is not enough space available
checkSpace()
{
    DISK_SPACE_AVAIL=$(df -Pk $1 | awk '/^\// { print $4; }')
    if [ -z $DISK_SPACE_AVAIL ]
    then
        DISK_SPACE_AVAIL=$(df -Pk $1 | awk '/[0-9]%/ { print $4; }')
    fi

    if [ ! -z $DISK_SPACE_AVAIL ]
    then
        if [ $2 -ge $DISK_SPACE_AVAIL ]
        then
            logMessage "Insufficient disk space in $1, need $2k but only ${DISK_SPACE_AVAIL}k available"
            restoreProcessStateAndAbort $3
        fi
    fi
}

# Used for purging a Debian package
# $1 is the package name to be purged
purgeDebPackage()
{
    local PACKAGE_NAME=$1
    dpkg -s ${PACKAGE_NAME} > /dev/null 2>&1
    if [ $? -ne 0 ]
    then
        logMessage "${PACKAGE_NAME} is currently not installed."
    else
        logMessage "Removing ${PACKAGE_NAME}"
        dpkg -P ${PACKAGE_NAME} 2>/dev/null
        if [ $? -ne 0 ]
        then
            logMessage "Error in removing ${PACKAGE_NAME}"
        else
            logMessage "Successfully removed ${PACKAGE_NAME}"
        fi
    fi
}
# Delete symlink kernel module directories
# Modversion of AAC and File Access kernel modules may have created symlinks to existing directories
# During an upgrade to newer version, rpm cannot replace these symlinks with new directories
# As a workaround for rpm based systems, only during an upgrade; delete any symlinked kernel module directories
deleteSymlinkedKernelModuleDirs()
{
    # Use the global value to determine if this is an upgrade scenario for a RPM system
    if [ ${mcafeeTPInstall} = 2 -a "${DEB_VARIANT}" = "no" ]
    then
        /bin/rm -f /var/McAfee/ens/esp/fileaccess/kernel/* 2>/dev/null || :
        /bin/rm -f /var/McAfee/ens/esp/aac/kernel/* 2>/dev/null || :
    fi
}


# Function to install or upgrade TP
# 1st param - Absolute path of the package to be installed
# 2nd param - 1 to indicate it is a fresh installation, 2 to indicate it is an upgrade
installOrUpgradeTP()
{
    PACKAGE_FILE=$1
    if [ ! -f "${PACKAGE_FILE}" ]
    then
        logMessage "Could not find ${PACKAGE_FILE} to install / upgrade"
        restoreProcessStateAndAbort 8
    fi
    INSTALL_TYPE=$2
    PACKAGE_NAME=$(basename "${PACKAGE_FILE}")
    retOfPkgMgrCmd=0
    case "${INSTALL_TYPE}" in
        # Check if Install
        "1"|\
        "2")
            if [ "${forceInstall}" = "no" ]
            then
                if [ ! -d /opt/McAfee/ens ]
                then
                    mkdir -p /opt/McAfee/ens
                    chmod 755 /opt/McAfee/ens
                fi
                #Check if space is available in install directory for TP
                checkSpace /opt/McAfee/ens 750000 24
                #Check if space is available in /var/McAfee directory for TP
                if [ -d /var/McAfee ]
                then
                    checkSpace /var/McAfee 750000 26
                else
                    logMessage "MFEcma(x86_64) 5.6.4-110 or above is required for installation to continue."
                    restoreProcessStateAndAbort 6
                fi
            fi
            cp -f ${PACKAGE_FILE} ${pkgMgrDir}
            if [ "${DEB_VARIANT}" = "no" ]
            then
                if [ "${SUSE_VARIANT}" = "yes" ]
                then
                    logMessage "Performing zypper update"
                    # Delete symlinked kernel module directories to prevent any rpm conflicts
                    deleteSymlinkedKernelModuleDirs
                    # Run install from Cache instead of checking in external site
                    # Command line zypper shows the warning message - "packages are not supported by their vendor"
                    # Send output to /dev/null to avoid confusing users
                    zypper --no-refresh --no-cd --no-remote --no-gpg-checks -q -n install ${pkgMgrDir}/*.rpm > /dev/null 2>&1
                    retOfPkgMgrCmd=$?
                    if [ ${retOfPkgMgrCmd} -ne 0 ]
                    then
                        logMessage "zypper exited with error code - ${retOfPkgMgrCmd}"
                    fi
                else
                    logMessage "Performing yum update"
                    # Delete symlinked kernel module directories to prevent any rpm conflicts
                    deleteSymlinkedKernelModuleDirs
                    # Run install by disabling all repo to prevent checking in external site
                    # If another yum is already running, then the following command will wait till first yum exits, use --setopt="exit_on_lock=true" to return without waiting
                    yum -y --nogpgcheck --noplugins --disablerepo=* install ${pkgMgrDir}/*.rpm
                    retOfPkgMgrCmd=$?
                    if [ ${retOfPkgMgrCmd} -ne 0 ]
                    then
                        logMessage "yum exited with error code - ${retOfPkgMgrCmd}"
                    fi
                fi
            else
                # There is no guarantee that a file based apt-repository is already available, so create again
                echo "deb file:${pkgMgrDir} ./" > ${pkgMgrDir}/sources.list
                # Create the cache and lib directory
                mkdir -p ${pkgMgrDir}/cache/apt/archives
                mkdir -p ${pkgMgrDir}/lib/apt/lists
                # Reuse the existing system dpkg directory
                ln -sf /var/lib/dpkg ${pkgMgrDir}/lib/dpkg
                if [ $? -ne 0 ]
                then
                    logMessage "Error in creating a symlink to existing dpkg administrative directory."
                    restoreProcessStateAndAbort 9
                fi
                pushd ${pkgMgrDir} > /dev/null 2>&1
                apt-ftparchive packages . > Packages
                gzip -f Packages
                popd > /dev/null 2>&1
                cp -f ${pkgMgrDir}/Packages.gz ${pkgMgrDir}/lib/apt/lists/
                showNewLine
                logMessage "Performing apt-get update"
                apt-get -q -o Dir::Etc::Sourcelist=${pkgMgrDir}/sources.list -o Dir::Etc::SourceParts=${pkgMgrDir} -o Dir::Cache::Archives=${pkgMgrDir}/cache/apt/archives -o Dir::State::Lists=${pkgMgrDir}/lib/apt/lists -o DPkg::Options::=--admindir=${pkgMgrDir}/lib/dpkg -o Acquire::AllowInsecureRepositories=true -o APT::Sandbox::User=root update > /dev/null 2>&1
                retOfPkgMgrCmd=$?
                if [ ${retOfPkgMgrCmd} -ne 0 ]
                then
                    logMessage "Error in running apt-get update from temporary apt repository, error code - ${retOfPkgMgrCmd}"
                else
                    showNewLine
                    logMessage "Performing apt-get install"
                    # Disable interactive mode and make the install silent and non-intrusive.
                    # remove is enabled by default to remove obsolete packages at the end
                    DEBIAN_FRONTEND=noninteractive apt-get -q --yes --allow-unauthenticated -o Dir::Etc::Sourcelist=${pkgMgrDir}/sources.list -o Dir::Etc::SourceParts=${pkgMgrDir} -o Dir::Cache::Archives=${pkgMgrDir}/cache/apt/archives -o Dir::State::Lists=${pkgMgrDir}/lib/apt/lists -o DPkg::Options::=--admindir=${pkgMgrDir}/lib/dpkg -o Acquire::AllowInsecureRepositories=true -o APT::Sandbox::User=root install mcafeetp mcafeeesp mcafeeespfileaccess mcafeeespaac mcafeert
                    retOfPkgMgrCmd=$?
                    if [ ${retOfPkgMgrCmd} -ne 0 ]
                    then
                        logMessage "apt-get exited with error code - ${retOfPkgMgrCmd}"
                    fi
                fi
            fi
            if [ ${retOfPkgMgrCmd} -ne 0 ]
            then
                if [ ${INSTALL_TYPE} -eq 1 ]
                then
                    logMessage "Failed to install ${PACKAGE_NAME}"
                else
                    logMessage "Failed to upgrade ${PACKAGE_NAME}"
                fi
                restoreProcessStateAndAbort 9
            else
                if [ ${INSTALL_TYPE} -eq 1 ]
                then
                    logMessage "Successfully installed ${PACKAGE_NAME}"
                else
                    if [ "${DEB_VARIANT}" = "yes" ]
                    then
                        # Clean up McAfee FMP, and pre 10.6.6 isec products in case of upgrade using dpkg purge
                        # apt-get remove will not work here as the package will be in 'rc' state
                        purgeDebPackage mcafeefmp
                        purgeDebPackage isectp
                        purgeDebPackage isecespaac
                        purgeDebPackage isecespfileaccess
                        purgeDebPackage isecesp
                    fi
                    logMessage "Successfully upgraded ${PACKAGE_NAME}"
                fi
                showNewLine
            fi
            # When older isectp is upgraded to mfetp, the task schedule information is deleted from /etc/crontab
            # Add these entries back to /etc/crontab from the tmp crontab file that was backed up during RPM and DEB upgrade
            if [ ${INSTALL_TYPE} -eq 2 ] && [ ${isectpInstalled} -eq 1 ]
            then
                if [ -f /opt/McAfee/ens/tp/tmp_crontab ]
                then
                    /bin/cat /opt/McAfee/ens/tp/tmp_crontab >> /etc/crontab
                    /bin/rm -f /opt/McAfee/ens/tp/tmp_crontab
                fi
            fi
    esac
}

# Function to check if product is supported on this distribution
# These checks are exactly same as the one kept in preinst of dpkg and %pre in the rpm.spec
checkForUnSupportedDistro()
{
    logMessage "Checking for Unsupported distributions"
    processorType=$(uname -m)
    if [ ${processorType} != "x86_64" ]
    then
        logMessage "Failed to detect a 64-bit distribution"
        echo "Product is unsupported on this distribution. Please see KB87073."
        cleanup 19
    fi
    # Flag to track version support
    isSupported="no"
    distribRel=""
    if [ ${DEB_VARIANT} = "yes" ]
    then
        if [ -f /etc/os-release ]
        then
            distribRelString=$(awk -F '=' '/^ID=/ {print $2}' /etc/os-release)
            distribRelMajNum=$(awk -F '=' '/^VERSION_ID=/ {print $2}' /etc/os-release | sed -e 's/\.//g' -e 's/"//g')
            distribRel=$(awk -F '=' '/^PRETTY_NAME=/ {print $2}' /etc/os-release)
        fi
        if [ -n "${distribRelString}" ]
        then
            if [ "${distribRelString}" = "ubuntu" ]
            then
                # For Ubuntu, 1910 and above will be supported. Only LTS versions of 1404, 1604 and 1804 will be supported
                if ( [ ${distribRelMajNum} -ge 1910 ] )
                then
                    isSupported="yes"
                else
                    case "${distribRelMajNum}" in
                        1404|\
                        1604|\
                        1804)
                            isSupported="yes"
                            ;;
                    esac 
                fi
            elif [ "${distribRelString}" = "debian" ]
            then
                # Debian 9 and above is supported
                if ( [ ${distribRelMajNum} -ge 9 ] )
                then
                    isSupported="yes"
                fi
            elif [ "${distribRelString}" = "linuxmint" ]
            then
                if ( [ ${distribRelMajNum} -ge 192 ] )
                then
                    isSupported="yes"
                else
                    case "${distribRelMajNum}" in
                        3|\
                        20|\
                        183)
                            isSupported="yes"
                            ;;
                    esac 
                fi
            fi
        else
            # For unknown distributions, assume a best case scenario that it is supported
            echo "Installing McAfeeTP on unknown distribution - ${distribRel}"
            isSupported="yes"
        fi
    else
        distribRelString="Unknown"
        if [ -f "/etc/redhat-release" ]
        then
            distribRel=$(cat /etc/redhat-release)
        elif [ -f "/etc/system-release" ]
        then
            distribRel=$(cat /etc/system-release)
        elif [ -f "/etc/SuSE-release" ]
        then
            # Need only the first line
            distribRel=$(head -n 1 /etc/SuSE-release)
        elif [ -f "/etc/os-release" ]
        then
            # /etc/os-release has all the information
            distribRelString=$(awk -F '=' '/^ID=/ {print $2}' /etc/os-release)
            distribRelMajNum=$(awk -F '=' '/^VERSION_ID=/ {print $2}' /etc/os-release | sed -e 's/\.//g' -e 's/"//g')
            distribRel=$(awk -F '=' '/^PRETTY_NAME=/ {print $2}' /etc/os-release)
        fi
        # Parse and format to identify OS if not already set
        if [ -n "$distribRel" -a "$distribRelString" = "Unknown" ]
        then
            # Replace any space or () with _
            # Converts SUSE Linux Enterprise Server 12 (x86_64) to SUSE_Linux_Enterprise_Server_12__x86_64_
            distribRelString=$(echo ${distribRel//[ ()]/_})
            # Delete any spaces a-z A-Z which will leave Distribution release number and ()
            # Converts "SUSE Linux Enterprise Server 12 (x86_64)" to "12(86_64)"
            distribRelMajNumTemp=$(echo ${distribRel//[a-zA-Z ]/})
            # Replace any () with . and then cut it on "." to get the major release number
            # Converts "12(86_64)" to "12.86_64" and then to "12"
            distribRelMajNum=$(echo ${distribRelMajNumTemp//[()]/.} | cut -d '.' -f1)
            # Replace any () with . and then cut it on "." to get the major release number
            # Converts "12(86_64)" to "12.86_64" and then to "86_64"
            distribRelMinNum=$(echo ${distribRelMajNumTemp//[()]/.} | cut -d '.' -f2)
        fi
        # Enable case insensitive match
        shopt -s nocasematch
        # Check if distribution release string starts with Red for Redhat
        redHatSearchPattern="^Red"
        # Check if distribution release string starts with CentOS for CentOS
        centOsSearchPattern="^Cent"
        # Check if distribution release string starts with SUSE for SUSE
        suseSearchPattern="^SUSE"
        # Check if distribution release string starts with SUSE for SUSE only till before SUSE 15
        suseLatestSearchPattern="^\"sles|^\"sled"
        # Check if distribution release string starts with openSUSE for openSUSE
        opensuseSearchPattern="^openSUSE|^\"openSUSE|^opensuse|^\"opensuse"
        # Check if distribution release string starts with Amazon for Amazon AMI
        amazonSearchPattern="^Amazon"
        # Check if distribution release string starts with fedora for Fedora
        fedoraSearchPattern="^Fedora"
        if [[ $distribRelString =~ $redHatSearchPattern ]]
        then
            # RHEL 6 and above is supported
            if ( [ ${distribRelMajNum} -ge 6 ] )
            then
                if ( [ ${distribRelMajNum} -eq 8 ] )
                then
                    RHEL8_VARIANT="yes"
                fi
                isSupported="yes"
            fi
        elif [[ $distribRelString =~ $centOsSearchPattern ]]
        then
            # CentOS 6 and above is supported
            if [ ${distribRelMajNum} -ge 6 ]
            then
                isSupported="yes"
            fi
        elif [[ $distribRelString =~ $suseSearchPattern ]]
        then
            # Suse 12 and above is supported
            if [ ${distribRelMajNum} -ge 12 ]
            then
                isSupported="yes"
            fi
        elif [[ $distribRelString =~ $suseLatestSearchPattern ]]
        then
            # SLES and SLED 15 and above is supported
            if [ ${distribRelMajNum} -ge 15 ]
            then
                isSupported="yes"
            fi
        elif [[ $distribRelString =~ $opensuseSearchPattern ]]
        then
            if [  ${distribRelMajNum} -eq 42 ]
            then
                isSupported="no"
            else
                # All openSUSE versions except 42.1 are currently considered to be supported
                isSupported="yes"
            fi
        elif [[ $distribRelString =~ $amazonSearchPattern ]]
        then
            # Amazon 2018 and above is supported
            if [ ${distribRelMajNum} -ge 2018 ]
            then
                isSupported="yes"
            fi
            # All Amazon Linux 2 and above are currently supported
            amazonlinuxrel2="^Amazon_Linux_"
            if [[ $distribRelString =~ $amazonlinuxrel2 ]]
            then
                if [ ${distribRelMajNum} -ge 2 ]
                then
                    isSupported="yes"
                fi
            fi
        elif [[ $distribRelString =~ $fedoraSearchPattern ]]
        then
            # Fedora 30 and above is supported
            if [ ${distribRelMajNum} -ge 30 ]
            then
                isSupported="yes"
            fi
        else
            # For unknown distributions, assume a best case scenario that it is supported
            echo "Installing McAfeeTP on unknown distribution - ${distribRel}"
            isSupported="yes"
        fi
    fi
    if [ "${isSupported}" = "no" ]
    then
        echo "McAfeeTP is not supported on this distribution - ${distribRel}"
        echo "Product is unsupported on this distribution. Please see KB87073."
        restoreProcessStateAndAbort 19
    fi
}

# Function to check if python is available on this machine
# This check is done only for RHEL8 distro as python was not available by default.
checkForPython()
{
    if which python >/dev/null 2>&1;
    then
        return
    elif which python2 >/dev/null 2>&1;
    then
        return
    elif which python3 >/dev/null 2>&1;
    then
        return
    else
        logMessage "Python is not available on this system. Install python and try again"
        cleanup 9
    fi
}

# Function to uninstall a file
# 1st param - Name of Package to be uninstalled
# 2nd param - Description of package uninstalled
uninstall()
{
    PACKAGE_NAME=$1
    PACKAGE_DESC=$2
    ${UNINSTALL_CMD} ${PACKAGE_NAME}
    if [ $? -ne 0 ]
    then
        logMessage "Failed to uninstall ${PACKAGE_DESC}"
        cleanup 14
    else
        logMessage "Successfully uninstalled ${PACKAGE_DESC}"
    fi
}

# Function to schedule default DAT and Engine update task.
# Return 0 on success, 1 on failure
scheduleDATAndEngineUpdate()
{
    # This will be returned and is 0 on success and 1 on failure
    scheduleSuccessful=1
    # This is the number of attempts that will be made to schedule the task
    totalAttempts=2
    currentAttempt=1
    # Do scheduling of default client update task.
    while [ ${currentAttempt} -le ${totalAttempts} ]
    do
        /opt/McAfee/ens/tp/bin/mfetpcli --scheduletask --index 3 --daily --starttime 00:15> /dev/null 2>&1
        retVal=$?
        case ${retVal} in
            0)
                scheduleSuccessful=0
                break
                ;;
            108)
                scheduleSuccessful=0
                break
                ;;
            *)
                ;;
        esac
        let currentAttempt=${currentAttempt}+1
        sleep 1
    done
    return ${scheduleSuccessful}
}

# Function to enable ScanOnWrite for standard profile
# If it fails the first time, try again
# Return 0 if enabled successfully, 1 on failure
setSOWForOASStandardProfile()
{
    # This will be returned and is 0 on success and 1 on failure
    scanOnWriteEnabled=1
    # This is the number of attempts that will be made to enable ScanOnWrite
    totalAttempts=2
    currentAttempt=1
    while [ ${currentAttempt} -le ${totalAttempts} ]
    do
        /opt/McAfee/ens/tp/bin/mfetpcli --setoasprofileconfig --profile standard --setmode sow > /dev/null 2>&1
        retVal=$?
        case ${retVal} in
        0)
            scanOnWriteEnabled=0
            break
            ;;
        108)
            scanOnWriteEnabled=0
            break
            ;;
        *)
            ;;
        esac
        let currentAttempt=${currentAttempt}+1
        sleep 1
    done
    return ${scanOnWriteEnabled}
}

# Function to check if OAS was enabled/disabled successfully depending on "enableOAS" parameter
# If the command fails the first time, try again
# Return 0 if enabled/disabled successfully, 1 on failure
isOASStateApplied()
{
    # This will be returned and is 0 on success and 1 on failure
    oasStateApplied=0
    # This is the number of attempts that will be made to get the status of OAS
    totalAttempts=2
    currentAttempt=1
    # Try to get the status of OAS
    while [ ${currentAttempt} -le ${totalAttempts} ]
    do
        /opt/McAfee/ens/tp/bin/mfetpcli --getoasconfig --summary > /dev/null 2>&1
        if [ $? -eq 0 ]
        then
            if [ ${enableOAS} == "yes" ]
            then
                /opt/McAfee/ens/tp/bin/mfetpcli --getoasconfig --summary | grep -e "On-Access Scan: Enabled" > /dev/null
                if [ $? -eq 0 ]
                then
                    oasStateApplied=0
                else
                    oasStateApplied=1
                fi
            else
                /opt/McAfee/ens/tp/bin/mfetpcli --getoasconfig --summary | grep -e "On-Access Scan: Disabled" > /dev/null
                if [ $? -eq 0 ]
                then
                    oasStateApplied=0
                else
                    oasStateApplied=1
                fi
            fi
            break
        fi
        let currentAttempt=${currentAttempt}+1
        if [ ${currentAttempt} -gt ${totalAttempts} ]
        then
            oasStateApplied=1
            break
        fi
        sleep 1
    done
    return ${oasStateApplied}
}

# Function to check if AP was enabled/disabled successfully depending on the value of "enableAP" parameter
# Returns 0 if enabled/disabled successfully else 1
isAPStateApplied()
{
    # This would be returned, 0 if the state of AP is changed successfully else 1
    apStateApplied=0
    # This is the number of attempts that will be made to get the status of AP
    totalAttempts=3
    currentAttempt=1
    # Try to get the status of Access Protection
    while [ ${currentAttempt} -le ${totalAttempts} ]
    do
        /opt/McAfee/ens/tp/bin/mfetpcli --getapstatus > /dev/null 2>&1
        if [ $? -eq 0 ]
        then
            if [ ${enableAP} == "yes" ]
            then
                /opt/McAfee/ens/tp/bin/mfetpcli --getapstatus | grep "Access Protection: Enabled" > /dev/null
                if [ $? -eq 0 ]
                then
                    apStateApplied=0
                else
                    apStateApplied=1
                fi
            else
                /opt/McAfee/ens/tp/bin/mfetpcli --getapstatus | grep "Access Protection: Disabled" > /dev/null
                if [ $? -eq 0 ]
                then
                    apStateApplied=0
                else
                    apStateApplied=1
                fi
            fi
            break
        fi
        let currentAttempt=${currentAttempt}+1
        if [ ${currentAttempt} -gt ${totalAttempts} ]
        then
            apStateApplied=1
            break
        fi
        sleep 3
    done
    return ${apStateApplied}
}

# Function to check if GTI was enabled/disabled successfully depending on the value of "enableGTI" parameter
# Return 0 if successfully changed GTI state, 1 on failure
isGTIStateApplied()
{
    # This will be returned and is 0 on success and 1 on failure
    gtiStateApplied=0
    # This is the number of attempts that will be made to get the state of GTI
    totalAttempts=2
    currentAttempt=1
    # Try to get the status of OAS
    while [ ${currentAttempt} -le ${totalAttempts} ]
    do
        /opt/McAfee/ens/tp/bin/mfetpcli --getoasconfig --summary > /dev/null 2>&1
        if [ $? -eq 0 ]
        then
            if [ ${enableGTI} == "yes" ]
            then
                /opt/McAfee/ens/tp/bin/mfetpcli --getoasconfig --summary | grep "GTI: Enabled" > /dev/null
                if [ $? -eq 0 ]
                then
                    gtiStateApplied=0
                else
                    gtiStateApplied=1
                fi
            else
                /opt/McAfee/ens/tp/bin/mfetpcli --getoasconfig --summary | grep "GTI: Disabled" > /dev/null
                if [ $? -eq 0 ]
                then
                    gtiStateApplied=0
                else
                    gtiStateApplied=1
                fi
            fi
            break
        fi
        let currentAttempt=${currentAttempt}+1
        if [ ${currentAttempt} -gt ${totalAttempts} ]
        then
            gtiStateApplied=1
            break
        fi
        sleep 1
    done
    return ${gtiStateApplied}
}

# Function to enable usefanotify before OAS enable
# Return 0 if enabled successfully, 1 on failure
enableUseFanotify()
{
    # This will return 0 on success and 1 on failure
    useFanotifyEnabled=1
    /opt/McAfee/ens/tp/bin/mfetpcli --usefanotify > /dev/null 2>&1
    retVal=$?
    case ${retVal} in
    0)
        useFanotifyEnabled=0
        ;;
    108)
        useFanotifyEnabled=0
        ;;
    *)
    ;;
    esac
    return ${useFanotifyEnabled}
}

# Function to check if OAS deferred scan was enabled/disabled successfully depending on the value of "enableOASDeferredScan" parameter
# Returns 0 if enabled/disabled successfully else 1
isDeferredScanStateApplied()
{
    # This would be returned, 0 if the state of OAS deferred scan is changed successfully else 1
    deferredScanStateApplied=0
    # This is the number of attempts that will be made to get the status of OAS deferred scan
    totalAttempts=3
    currentAttempt=1
    # Try to get the status of OAS deferred scan
    while [ ${currentAttempt} -le ${totalAttempts} ]
    do
        /opt/McAfee/ens/tp/bin/mfetpcli --getdeferredscan > /dev/null 2>&1
        if [ $? -eq 0 ]
        then
            if [ ${enableOASDeferredScan} == "yes" ]
            then
                /opt/McAfee/ens/tp/bin/mfetpcli --getdeferredscan | grep "Deferred Scan: Enabled" > /dev/null
                if [ $? -eq 0 ]
                then
                    deferredScanStateApplied=0
                else
                    deferredScanStateApplied=1
                fi
            else
                /opt/McAfee/ens/tp/bin/mfetpcli --getdeferredscan | grep "Deferred Scan: Disabled" > /dev/null
                if [ $? -eq 0 ]
                then
                    deferredScanStateApplied=0
                else
                    deferredScanStateApplied=1
                fi
            fi
            break
        fi
        let currentAttempt=${currentAttempt}+1
        if [ ${currentAttempt} -gt ${totalAttempts} ]
        then
            deferredScanStateApplied=1
            break
        fi
        sleep 3
    done
    return ${deferredScanStateApplied}
}

# Function to check if OAS cpu usage limit was set successfully depending on the value of "setOasCpuLimit" parameter
# Returns 0 if set successfully else 1
isOasCpuThrottlingApplied()
{
    # This would be returned, 0 if the OAS cpu throttling is applied successfully else 1
    oasCpuThrottlingApplied=0
    # This is the number of attempts that will be made to get OAS cpu limit
    totalAttempts=3
    currentAttempt=1
    # Try to get get OAS cpu limit value
    while [ ${currentAttempt} -le ${totalAttempts} ]
    do
        /opt/McAfee/ens/tp/bin/mfetpcli --getoascpulimit > /dev/null 2>&1
        if [ $? -eq 0 ]
        then
            if [ ${setOasCpuLimit} == "yes" ]
            then
                /opt/McAfee/ens/tp/bin/mfetpcli --getoascpulimit | grep -w  $oasCpuLimit > /dev/null
                if [ $? -eq 0 ]
                then
                    oasCpuThrottlingApplied=0
                else
                    oasCpuThrottlingApplied=1
                fi
            else
                /opt/McAfee/ens/tp/bin/mfetpcli --getoascpulimit | grep -w 100 > /dev/null
                if [ $? -eq 0 ]
                then
                    oasCpuThrottlingApplied=0
                else
                    oasCpuThrottlingApplied=1
                fi
            fi
            break
        fi
        let currentAttempt=${currentAttempt}+1
        if [ ${currentAttempt} -gt ${totalAttempts} ]
        then
            oasCpuThrottlingApplied=1
            break
        fi
        sleep 3
    done
    return ${oasCpuThrottlingApplied}
}

# Deletes older copies of ESP package and retains only the latest version (as determined by ls)
# This ensures that upgrade / installation is only attempted with latest version of ESP
# Deb uses apt-repository and can automatically pick the latest version.
# yum and zypper uses glob and is not capable of determining which is the latest version of ESP
# By deleting all older versions of ESP, yum and zypper will also work for ENSL TP and ENSL FW upgrade
# Does not return any error even if no ESP package was found
retainLatestESPPkg()
{
    pkgDirToCheck=$1
    pushd ${pkgDirToCheck} > /dev/null 2>&1
    if [ ${DEB_VARIANT} = "yes" ]
    then
        latestESPPkgFile=$(ls McAfeeESP-*.deb | tail -1)
        for espPkg in McAfeeESP-*.deb; do
            if [ "${espPkg}" != "${latestESPPkgFile}" ]
            then
                rm -f "${espPkg}"
            fi
        done
    else
        latestESPPkgFile=$(ls McAfeeESP-*.rpm | tail -1)
        for espPkg in McAfeeESP-*.rpm; do
            if [ "${espPkg}" != "${latestESPPkgFile}" ]
            then
                rm -f "${espPkg}"
            fi
        done
    fi
    popd > /dev/null 2>&1
}

# Function to extract Firewall Installer Tarball and copy the respective RPM / DEB to the installation directory
# Return 0, if Firewall installer was found; else returns 1 on error.
# Errors in extracting the tarball and copying it is ignored, next installation step will fail anyway
# Name of the Firewall installer depends on the keyword - standalone / ePO
extractAndCopyENSLFW()
{
    installFileKeyword=$1
    retVal=1
    for file in $(ls ${currentDir}/McAfeeFW-*-Release-${installFileKeyword}.tar.gz 2>/dev/null)
    do
        MFW_INSTALLER_TARBALL="${file}"
        fwTmpDir=$(mktemp -d -p ${tmpDir} 2>/dev/null)
        tar -C ${fwTmpDir} -xzf ${MFW_INSTALLER_TARBALL} 2>/dev/null
        tar -C ${fwTmpDir} -xzf ${fwTmpDir}/McAfeeFW-*-${installFileKeyword}.linux.tar.gz 2>/dev/null
        if [ ${DEB_VARIANT} = "yes" ]
        then
            /bin/cp -f ${fwTmpDir}/McAfeeFW-*.deb ${pkgMgrDir}/ 2>/dev/null
        else
            /bin/cp -f ${fwTmpDir}/McAfeeFW-*.x86_64.rpm ${pkgMgrDir}/ 2>/dev/null
        fi
        rm -rf ${fwTmpDir}
        retVal=0
        break
    done
    tar -C ${fwTmpDir} -xzf ${fwTmpDir}/McAfeeESP-Basic-*.linux.tar.gz 2>/dev/null
    # Copy only ESP package to package manager directory.
    # If in future there is a mandate for a minimum version of RT, then copy RT package and delete any older RT package
    if [ ${DEB_VARIANT} = "yes" ]
    then
        /bin/cp -f ${fwTmpDir}/McAfeeESP-*.deb ${pkgMgrDir}/ 2>/dev/null
    else
        /bin/cp -f ${fwTmpDir}/McAfeeESP-*.rpm ${pkgMgrDir}/ 2>/dev/null
    fi
    retainLatestESPPkg ${pkgMgrDir}
    return ${retVal}
}

# Function to cleanup temporary files
cleanup()
{
    if [ $# -ne 1 ]
    then
        exitCode=9
    else
        exitCode=$1
    fi
    # Delete the temporary directory
    rm -rf "${tmpDir}"
    # Installation case
    if [ "${mcafeeTPInstall}" -eq 1 ]
    then
        if [ "${DEB_VARIANT}" = "no" ]
        then
            # Check if McAfeeTP is installed, if not delete threatprevention directory
            INSTALLED_MFE_TP_VERSION_STRING=$(rpm -qa --queryformat "%{NAME}-%{VERSION}.%{RELEASE}\n" | grep -i McAfeeTP)
            if [ -z "${INSTALLED_MFE_TP_VERSION_STRING}" ]
            then
                rm -rf /opt/McAfee/ens/tp
                rmdir /opt/McAfee/ens >/dev/null 2>&1
            fi
        else
            # Check if McAfeeTP is installed, if not delete threatprevention directory
            dpkg -s McAfeeTP 2>/dev/null | grep "Status: install ok installed" >/dev/null 2>&1
            if [ $? -ne 0 ]
            then
                rm -rf /opt/McAfee/ens/tp
                rmdir /opt/McAfee/ens >/dev/null 2>&1
            fi
        fi
    fi
    # Delete temporary product upgrade directory
    rm -rf /opt/McAfee/upgradetmp/tp
    logMessage "Check log file for more details - /tmp/ensltp-standalone-setup.log"
    exit ${exitCode}
}

# Function to read or quit from the user input
readOrQuit()
{
    read
    if [ $? -ne 0 ]
    then
        # Exit with code 0
        cleanup 0
    fi
}

# Set log file
log="/tmp/ensltp-standalone-setup.log"
# This will be used to automatically determine the name of the output log file
declare -r me=${0##*/}
# Set default permissions of files to allow read / write only for owner
umask 077
# Used to track if this is a rpm or deb based system
DEB_VARIANT="no"
# Used to track if this uses zypper as the package management system
SUSE_VARIANT="no"
# Used to check if this is a RHEL 8 distro
RHEL8_VARIANT="no"
EULA_FILE="license.txt"
# Version of McAfeeTP for Linux in this package - example 8.0.0.118
PACKAGED_MFE_TP_VERSION_INT="10.7.9.31"

# Check installer is executed as root
ID="$(id -u)"
if [ $? -ne 0 -o "$ID" -ne 0 ]
then
    logMessage "Must be root to install this product"
    exit 5
fi

# There are three types of installation - silent, prompt and epo
# Default is prompt which shows EULA
# For 'silent', do not show EULA
# For 'epo', do not show EULA and extract DAT as well
installType=prompt

# Installation may resume after fetching conflicting FW, set it to yes in that case.
resumeInstall="no"
# OAS will not be enabled by default in the product default settings
# This script will enable it based on the value of the following flag.
enableOAS="yes"
# usefanotify is meant to use fanotify instead of kernel module for OAS
useFanotify="no"
# GTI will be enabled by default in the product default settings
# This script will enable or disable it based on the value of the following flag.
enableGTI="yes"
#By default the scanMode will be Let Mcafee decide.
#This script will enable scanMode to scanOnWrite if it is standalone fresh installation and
#based on the value of the following flag.
scanOnWrite="yes"
# Flag to turn Access Protection on/off. Default behavior is to keep it off for standalone installation and on for ePO installation
enableAP="no_cmdline_option_given_for_ap_state"
# Flag to check if auto content update on start-up should be disabled or not. By default ENS-L TP runs the DAT update task after start-up.
disableAutoContentUpdate="no"
# Flag to use alternate path for installation. Default behavior is to keep it off, so that installation happens from "/tmp" folder
useAltTmpPath="no"
# Flag to determine if EULA information is supposed to be shown for permission or not
showEULAInformation="no"
# Hidden flag to bypass unsupported distribution and space checks
forceInstall="no"
# Hidden flag to cleanup tempdir in case of install or upgrade failure
cleanUpTmp="no"
# Flag to bypass unsupported MACC
forceInstallWithMACC="no"
# OAS deferred scan will not be enabled by default in the product default settings
# This script will enable it based on the value of the following flag.
enableOASDeferredScan="no"
# Flag to set cpu usage limit for OAS. By default, no throttling is set.
setOasCpuLimit="no"

for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)
    case "$KEY" in
            alttmppath)
                if [ "${KEY}" = "${VALUE}" ] || [ "${VALUE}" = "" ]
                then
                    usage
                fi
                altTmpPath=${VALUE}
                useAltTmpPath="yes"
                ;;
            oascpulimit)
                if [ "${KEY}" = "${VALUE}" ] || [ "${VALUE}" = "" ]
                then
                    usage
                fi
                oasCpuLimit=${VALUE}
                setOasCpuLimit="yes"
                ;;
            *)
    esac
done

numargs=$#
for ((i=1 ; i <= numargs ; i++))
do
    case $1 in
        "epo")
            if [ "${ePOInstaller}" -eq 0 ]
            then
                logMessage "Invalid installation type epo provided for Standalone Installer"
                usage
            else
                installType="epo"
            fi
            ;;
        "prompt"|\
        "silent")
            if [ "${ePOInstaller}" -eq 0 ]
            then
                installType="$1"
            else
                logMessage "Invalid installation type $1 provided for ePO Installer"
                usage
            fi
            ;;
        "resume")
            resumeInstall="yes"
            ;;
        "oasoff")
            enableOAS="no"
            ;;
        "oason")
            enableOAS="yes"
            ;;
        "gtioff")
            enableGTI="no"
            ;;
        "usefanotify")
            useFanotify="yes"
            ;;
        "apoff")
            enableAP="no"
            ;;
        "apon")
            enableAP="yes"
            ;;
        "nocontentupdate")
            disableAutoContentUpdate="yes"
            ;;
        "force")
            forceInstall="yes"
            ;;
        "fwoff")
            # Ignore Firewall specific command line option
            ;;
        "nomacccheck")
            forceInstallWithMACC="yes"
            ;;
        "usedeferredscan")
            enableOASDeferredScan="yes"
            ;;
        "abortupgrade")
            cleanUpTmp="yes"
            ;;
        "--help")
            usage
            ;;
        "-h")
            usage
            ;;
        *)
            if [ ${useAltTmpPath} == "yes" ]
            then
                logMessage "Installation will be done from $altTmpPath"
            elif [ ${setOasCpuLimit} == "yes" ]
            then
                logMessage "OAS cpu usage limit will be set"
            else
                logMessage "Invalid option"
                usage
            fi
            ;;
    esac
    shift
done

# Get the absolute path of the installer file
# Use directory where installer is running to check for pre configured package name
currentDir=$(dirname $0)
# During build, the default name of the package is set here
installerFile="${currentDir}/McAfeeTP-10.7.9-31-standalone.linux.tar.gz"
datTarFile="DAT.tar.gz"
if [ ! -f "${installerFile}" ]
then
    logMessage "Unable to locate the installation file ${installerFile}"
    exit 7
fi

# Setup file descriptors for silent or epo install
if [ "${installType}" = "silent" -o "${installType}" = "epo" ]
then
    exec 0<&-   # Close stdin
    if [ ${resumeInstall} == "yes" -o ${cleanUpTmp} == "yes" ]
    then
        exec 1>>$log # Redirects stdout to log file, by appending to it when installation is resumed
    else
        exec 1>$log # Redirects stdout to log file
    fi
    exec 2>&1   # Redirect stderr to stdout
    logMessage "Script execution time: $(date)"
fi

# Flags to set installation type for each module
# 0 - Do not install, 1 - Install, 2 - Upgrade module
mcafeeTPInstall=0
# Flag to check if VSEL is currently installed
# 0 - Not installed, 1 - Installed
vselInstalled=0
# Flag to check if VSEL 1.9.x is currently installed
# 0 - Not installed, 1 - Installed
vsel19Installed=0
# Flag to check if ensl 10.2 is installed on the system
# 0 - Not installed, 1 - Installed
ensl102Installed=0

# All known rpm based systems either have /etc/redhat-release (Redhat, Fedora, CentOS) or /etc/SuSE-release (SuSE, openSuSE)
if [ -f /etc/redhat-release -o -f /etc/SuSE-release ]
then
    DEB_VARIANT="no"
    if [ -f /etc/SuSE-release ]
    then
        SUSE_VARIANT="yes"
    fi
elif [ -f /etc/system-release ]
then
    # Amazon Linux AMI is rpm based, has /etc/system-release and its content starts with Amazon
    distribRel=$(cat /etc/system-release)
    amazonSearchPattern="^Amazon"
    if [[ $distribRel =~ $amazonSearchPattern ]]
    then
        DEB_VARIANT="no"
    fi
elif [ -f /etc/os-release ]
then
    # SuSE 15 and above does not ship with /etc/SuSE-release; check /etc/os-release instead
    distribId=$(cat /etc/os-release | grep ^ID=)
    slesSearchPattern="sles|sled"
    opensuseSearchPattern="openSUSE|opensuse"
    if [[ $distribId =~ $slesSearchPattern ]]
    then
        SUSE_VARIANT="yes"
        DEB_VARIANT="no"
    elif [[ $distribId =~ $opensuseSearchPattern ]]
    then
        SUSE_VARIANT="yes"
        DEB_VARIANT="no"
    else
        DEB_VARIANT="yes"
    fi
else
    DEB_VARIANT="yes"
fi

#Temporary Directory used to install package
if [ ${useAltTmpPath} = "yes" ]
then
    tmpDir="${altTmpPath}/ens_pkg"
else
    tmpDir="/tmp/ens_pkg"
fi

# If abortupgrade command line option is passed to the installer script, then the cleanup will be called.
# Currently, this handles the specific case of upgrade failure when Firewall package could not be downloaded from ePO.
# This can be improved later to handle any failure scenarios by maybe passing the error codes.
if [ "${cleanUpTmp}" = "yes" ]
then
    logMessage "Upgrade aborted as McAfeeFW could not be downloaded for upgrade"
    cleanup
fi

# If installation is being resumed, then reuse the older directory; else recreate the directory
if [ "${resumeInstall}" = "no" ]
then
    rm -rf ${tmpDir}
    # Create temporary directory to extract the installer file
    mkdir -p ${tmpDir}
    # Set owner to the temporary directory
    chown root:root ${tmpDir}
    chmod 600 ${tmpDir}
    rm -rf ${tmpDir}/*
fi

# Validate if this is a supported distribution, if force Installation is disabled
if [ "${forceInstall}" = "no" ]
then
    checkForUnSupportedDistro
    # In case of RHEL8 check if python is available as python will not be available by default
    if [ "${RHEL8_VARIANT}" = "yes" ]
    then
        checkForPython
    fi
    checkSpace $tmpDir 200000 22
fi

# Installation script may need to shut down ENSL TP before attempting an upgrade
# This section determines if pre 10.6.6 ISecTP or ENSL TP is installed.
if [ "${DEB_VARIANT}" = "no" ]
then
    INSTALLED_ISEC_TP_VERSION_STRING=$(rpm -qa --queryformat "%{NAME}-%{VERSION}.%{RELEASE}\n" | grep -i ISecTP)
    if [ ! -z "${INSTALLED_ISEC_TP_VERSION_STRING}" ]
    then
        logMessage "ISecTP installed in this system is - ${INSTALLED_ISEC_TP_VERSION_STRING}"
        isectpInstalled=1
        INSTALLED_ISEC_TP_VERSION_INT=$(echo "${INSTALLED_ISEC_TP_VERSION_STRING}" | awk -F '-' '{print $2}')
    fi
else
    # Convert "Version: 8.0.0-118" to "8.0.0-118"
    INSTALLED_ISEC_TP_VERSION_STRING=$(dpkg -s isectp 2>/dev/null  | grep ^Version | awk -F ': ' '{print $2}')
    if [ ! -z "${INSTALLED_ISEC_TP_VERSION_STRING}" ]
    then
        logMessage "isectp installed in this system is - ${INSTALLED_ISEC_TP_VERSION_STRING}"
        isectpInstalled=1
        INSTALLED_ISEC_TP_VERSION_INT=$(echo "${INSTALLED_ISEC_TP_VERSION_STRING}" | sed -e 's:-:.:g')
    fi
fi
#Check if mfetpd service is running
checkIfServiceIsRunning

# Install only if MACC 6.4.1 or later is present and forceInstallWithMACC option is not provided for the script.
if [ "${forceInstallWithMACC}" == "no" ]
then
    checkForIncompatibleProduct "solidcoreS3" "McAfee Solidifier for Linux" "6.4.1"
fi

if [ ${isectpInstalled} -eq 1 ]
then
    # If installed ENSL version is less than "10.5.0" set the ensl102Installed to "1"
    # This is being done to make sure that when upgrading from ensl 1023 to latest versions of ENSL
    # Access protection is enabled, in case "apoff" flag is not passed to the install script.
    ISEC_TP_VERSION_10_5_INT=10.5.0.0
    vercomp ${ISEC_TP_VERSION_10_5_INT} ${INSTALLED_ISEC_TP_VERSION_INT}
    returnValue=$?
    if [ "${returnValue}" -eq 1 ]
    then
        ensl102Installed=1
    fi

    if [ ${DEB_VARIANT} = "yes" ]
    then
        # Check if MOVE product is installed. If yes, then abort installation and send error code.
        checkForIncompatibleProduct "mcafeemoveagntls" "MOVE AV Agentless" "4.9.0"
    fi
fi

#This check for installType is added to ensure that the license file is never shown during ePO deployment
if [ "${installType}" = "prompt" ]
then
    if [ "${DEB_VARIANT}" = "no" ]
    then
        # For rpm based systems
        # Check if McAfeeTP for Linux is installed
        INSTALLED_MFE_TP_VERSION_STRING=$(rpm -qa --queryformat "%{NAME}-%{VERSION}.%{RELEASE}\n" | grep -i McAfeeTP)
        if [ -z "${INSTALLED_MFE_TP_VERSION_STRING}" ] && [ "${isectpInstalled}" -eq 0 ]
        then
            showEULAInformation="yes"
        else
            showEULAInformation="no"
        fi
    else
        # Check if McAfeeTP is installed
        dpkg -s McAfeeTP 2>/dev/null | grep "Status: install ok installed" >/dev/null 2>&1
        if [ $? -ne 0 ] && [ "${isectpInstalled}" -eq 0 ]
        then
            showEULAInformation="yes"
        else
            showEULAInformation="no"
        fi
    fi
fi

# Directory from where package managers will install our packages
pkgMgrDir=${tmpDir}/install

# Stop the process if mfetpd is running
if [ $serviceRunning == true ]
then
    if [ "${isectpInstalled}" -eq 1 ]
    then
        /opt/isec/ens/threatprevention/bin/isectpdControl.sh stop 2>/dev/null || :
    else
        /opt/McAfee/ens/tp/init/mfetpd-control.sh stop 2>/dev/null || :
    fi
fi

if [ "${resumeInstall}" = "no" ]
then
    tar -C "${tmpDir}" --no-same-owner -xzf ${installerFile}
    if [ $? -ne 0 ]
    then
        logMessage "Failed to extract the installation file ${installerFile}"
        restoreProcessStateAndAbort 10
    fi
fi

# Show the EULA for prompt option
if [ "${showEULAInformation}" = "yes" ]
then
    if [ -f "${tmpDir}/${EULA_FILE}" ]
    then
        more "${tmpDir}/${EULA_FILE}"
        showNewLine
        MORE=1
        ACCEPTED_EULA='yes'
        while [ ${MORE} -eq 1 ]
        do
            echo -n "Enter accept or reject: "
            readOrQuit
            if [ "${REPLY}" = "accept" ]
            then
                MORE=0
            else
                if [ "${REPLY}" = "reject" ]
                then
                    ACCEPTED_EULA='no'
                    MORE=0
                fi
            fi

        done
    else
        logMessage "Failed to show the license file"
        restoreProcessStateAndAbort 12
    fi
    # Abort if EULA is not accepted
    if [ "${ACCEPTED_EULA}" = 'no' ]
    then
        logMessage "Aborting installation"
        restoreProcessStateAndAbort 11
    fi
    # cleanup on interrupt and termination (only in prompt mode)
    trap cleanup 2 15
fi

if [ ${DEB_VARIANT} = "yes" ]
then
    logMessage "Detected deb based distribution"
    UNINSTALL_CMD="dpkg --purge "
    # Format is McAfeeTP-8.0.0-1600.deb
    MFE_TP_PACKAGE_FILE="${tmpDir}/McAfeeTP-10.7.9-31.deb"
else
    logMessage "Detected rpm based distribution"
    UNINSTALL_CMD="rpm -e "
    # Format is McAfeeTP-8.0.0-1600.x86_64.rpm
    MFE_TP_PACKAGE_FILE="${tmpDir}/McAfeeTP-10.7.9-31.x86_64.rpm"
fi

if [ "${DEB_VARIANT}" = "no" ]
then
    # Check if VSEL is installed
    # Get in format of "McAfeeVSEForLinux-2.0.3.29216"
    INSTALLED_VSEL_VERSION_STRING=$(rpm -qa --queryformat "%{NAME}-%{VERSION}\n" | grep -i McAfeeVSEForLinux)
    if [ ! -z "${INSTALLED_VSEL_VERSION_STRING}" ]
    then
        # VSEL is present
        vselInstalled=1
        logMessage "McAfeeVSEForLinux installed in this system is - ${INSTALLED_VSEL_VERSION_STRING}"
        # Check if VSEL 1.9.x is installed, if not, then check if ISecGRt can be uninstalled
        if [[ "${INSTALLED_VSEL_VERSION_STRING}" =~ ^McAfeeVSEForLinux-1.9+ ]]
        then
            vsel19Installed=1
        fi
    fi

    # Check if McAfeeTP is installed
    # Get in format of "McAfeeTP-8.0.0.118"
    INSTALLED_MFE_TP_VERSION_STRING=$(rpm -qa --queryformat "%{NAME}-%{VERSION}.%{RELEASE}\n" | grep -i McAfeeTP)
    if [ -z "${INSTALLED_MFE_TP_VERSION_STRING}" ]
    then
        if [ "${vselInstalled}" -eq 1 ]
        then
            logMessage "McAfeeVSEForLinux will be upgraded to McAfeeTP"
            # VSEL should be upgraded to McAfeeTP
            mcafeeTPInstall=2
        elif [ "${isectpInstalled}" -eq 1 ]
        then
            logMessage "ISecTP will be upgraded to McAfeeTP"
            # ISecTP should be upgraded to McAfeeTP
            mcafeeTPInstall=2
        else
            logMessage "McAfeeTP will be installed"
            # Install McAfeeTP
            mcafeeTPInstall=1
        fi
    else
        logMessage "McAfeeTP installed in this system is - ${INSTALLED_MFE_TP_VERSION_STRING}"
        # Convert "McAfeeTP-8.0.0.118" to "8.0.0.118"
        INSTALLED_MFE_TP_VERSION_INT=$(echo "${INSTALLED_MFE_TP_VERSION_STRING}" | awk -F '-' '{print $2}')
        vercomp ${PACKAGED_MFE_TP_VERSION_INT} ${INSTALLED_MFE_TP_VERSION_INT}
        upgradeType=$?
        # Upgrade McAfeeTP if older version is installed
        if [ "${upgradeType}" -eq 1 ]
        then
            logMessage "Upgrading McAfeeTP since version installed in this system is ${INSTALLED_MFE_TP_VERSION_INT}, which is older than packaged version ${PACKAGED_MFE_TP_VERSION_INT}"
            # Upgrade McAfeeTP
            mcafeeTPInstall=2
        elif [ "${upgradeType}" -eq 2 ]
        then
            logMessage "Not upgrading McAfeeTP since version installed in this system is ${INSTALLED_MFE_TP_VERSION_INT}, which is newer than packaged version ${PACKAGED_MFE_TP_VERSION_INT}."
            restoreProcessState
        else
            logMessage "Not upgrading McAfeeTP since version installed in this system is ${INSTALLED_MFE_TP_VERSION_INT}, which is same as packaged version ${PACKAGED_MFE_TP_VERSION_INT}."
            restoreProcessState
        fi
    fi
else
    # For debian based systems
    # Check if VSEL is installed
    dpkg -s McAfeeVSEForLinux 2>/dev/null | grep "Status: install ok installed" >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
        # Convert "Version: 8.0.0-118" to "8.0.0-118"
        INSTALLED_VSEL_VERSION_STRING=$(dpkg -s McAfeeVSEForLinux | grep ^Version | awk -F ': ' '{print $2}')
        # VSEL is present
        vselInstalled=1
        logMessage "McAfeeVSEForLinux installed in this system is - ${INSTALLED_VSEL_VERSION_STRING}"
        # Check if VSEL 1.9.x is installed, if not, then check if ISecGRt can be uninstalled
        if [[ "${INSTALLED_VSEL_VERSION_STRING}" =~ ^McAfeeVSEForLinux-1.9+ ]]
        then
            vsel19Installed=1
        fi
    fi

    # Check if McAfeeTP is installed
    dpkg -s McAfeeTP 2>/dev/null | grep "Status: install ok installed" >/dev/null 2>&1
    if [ $? -ne 0 ]
    then
        if [ "${vselInstalled}" -eq 1 ]
        then
            logMessage "McAfeeVSEForLinux will be upgraded to McAfeeTP"
            # VSEL should be upgraded to McAfeeTP
            mcafeeTPInstall=2
        elif [ "${isectpInstalled}" -eq 1 ]
        then
            logMessage "isectp will be upgraded to mcafeetp"
            # ISecTP should be upgraded to McAfeeTP
            mcafeeTPInstall=2
        else
            logMessage "Installing McAfeeTP as it is currently not installed"
            # Install McAfeeTP
            mcafeeTPInstall=1
        fi
    else
        # Convert "Version: 8.0.0-118" to "8.0.0-118"
        INSTALLED_MFE_TP_VERSION_STRING=$(dpkg -s McAfeeTP | grep ^Version | awk -F ': ' '{print $2}')
        logMessage "McAfeeTP installed in this system is - ${INSTALLED_MFE_TP_VERSION_STRING}"
        INSTALLED_MFE_TP_VERSION_INT=$(echo "${INSTALLED_MFE_TP_VERSION_STRING}" | sed -e 's:-:.:g')
        # Check if packaged version of McAfeeTP is greater than installed version
        dpkg --compare-versions "${PACKAGED_MFE_TP_VERSION_INT}" gt "${INSTALLED_MFE_TP_VERSION_INT}"
        if [ $? -eq 0 ]
        then
            logMessage "Upgrading McAfeeTP since version installed in this system is ${INSTALLED_MFE_TP_VERSION_INT}, which is older than packaged version ${PACKAGED_MFE_TP_VERSION_INT}"
            # Upgrade McAfeeTP
            mcafeeTPInstall=2
        else
            dpkg --compare-versions "${PACKAGED_MFE_TP_VERSION_INT}" lt "${INSTALLED_MFE_TP_VERSION_INT}"
            if [ $? -eq 0 ]
            then
                logMessage "Not upgrading McAfeeTP since version installed in this system is ${INSTALLED_MFE_TP_VERSION_INT}, which is newer than packaged version ${PACKAGED_MFE_TP_VERSION_INT}."
                restoreProcessState
            else
                logMessage "Not upgrading McAfeeTP since version installed in this system is ${INSTALLED_MFE_TP_VERSION_INT}, which is same as packaged version ${PACKAGED_MFE_TP_VERSION_INT}."
                restoreProcessState
            fi
        fi
    fi
fi

# If installation is being resumed, then extract and copy Firewall tarball
if [ "${resumeInstall}" = "yes" ]
then
    # If Firewall tarball is present for the same release type, then extract it and go ahead with TP installation
    # If Firewall tarball is not present, then return that error that installation cannot continue
    extractAndCopyENSLFW ePO
    if [ $? -ne 0 ]
    then
        logMessage "ESP and associated packages conflicts with existing McAfeeFW. Installation cannot continue."
        # Start the service again forcefully, if installation is being resumed
        serviceRunning="true"
        restoreProcessStateAndAbort 17
    fi
# Only for a fresh installation, invoke ESP installer script to install runtime, ESP, ESP for FileAccess and ESP Arbitrary Access Control
else
    if [ "${forceInstall}" = "no" ]
    then
        if [ ! -d /opt/McAfee/ens ]
        then
            mkdir -p /opt/McAfee/ens
            chmod 755 /opt/McAfee/ens
        fi
        #Check if space is available in install directory for TP
        checkSpace /opt/McAfee/ens 750000 24
        #Check if space is available in /var/McAfee directory for TP
        if [ -d /var/McAfee ]
        then
            checkSpace /var/McAfee 750000 26
        else
            logMessage "MFEcma(x86_64) 5.6.4-110 or above is required for installation to continue."
            restoreProcessStateAndAbort 6
        fi
    fi
    chmod +x ${tmpDir}/validate-mfeesp.sh
    mkdir -p ${pkgMgrDir}
    # ESP Kernel Module Tarball may be in temporary or in current directory
    if [ -f ${tmpDir}/McAfeeESP-KernelModule-10.7.9-134-Full.linux.tar.gz ]
    then
        bash ${tmpDir}/validate-mfeesp.sh ${installType} ${log} ${pkgMgrDir} ${tmpDir}/McAfeeESP-Basic-10.7.9-134-Full.linux.tar.gz ${tmpDir}/McAfeeESP-KernelModule-10.7.9-134-Full.linux.tar.gz
    else
        bash ${tmpDir}/validate-mfeesp.sh ${installType} ${log} ${pkgMgrDir} ${tmpDir}/McAfeeESP-Basic-10.7.9-134-Full.linux.tar.gz ${currentDir}/McAfeeESP-KernelModule-10.7.9-134-Full.linux.tar.gz
    fi
    # Zero error code indicates ESP is already installed or its installation does not have any conflicts
    espRetVal=$?
    if [ ${espRetVal} -ne 0 ]
    then
        if [ ${installType} = "epo" ]
        then
            # Check if ESP installation gave a conflict with Firewall
            if [ ${espRetVal} -eq 17 -o ${espRetVal} -eq 18 ]
            then
                # For ePO based installations, if Firewall is conflicting, then exit with that error without a cleanup
                # Detection script is expected to download Firewall package if available and continue with the TP installation again
                logMessage "ESP and associated packages conflicts with existing McAfeeFW which should also be upgraded during ePO deployment."
                exit 17
            # For ePO based installation, conflicts with TP will be ignored assuming that new package will resolve it
            # Any other error will abort the installation immediately
            elif [ ${espRetVal} -ne 16 ]
            then
                restoreProcessStateAndAbort ${espRetVal}
            fi
        else
            # Check if ESP installation gave a conflict with Firewall
            if [ ${espRetVal} -eq 17 -o ${espRetVal} -eq 18 ]
            then
                # For standalone based installations, if Firewall tarball is present for the same release type, then extract it and go ahead with TP installation
                # If Firewall tarball is not present, then return that error that installation cannot continue
                extractAndCopyENSLFW standalone
                if [ $? -ne 0 ]
                then
                    logMessage "ESP and associated packages conflicts with existing McAfeeFW. Installation cannot continue."
                    restoreProcessStateAndAbort 17
                fi
            # For standalone based installation, conflicts with TP will be ignored assuming that new package will resolve it
            # Any other error will abort the installation immediately
            elif [ ${espRetVal} -ne 16 ]
            then
                restoreProcessStateAndAbort ${espRetVal}
            fi
        fi
    fi
fi

# Install / Upgrade McAfeeTP. Do not do anything with ESP if TP never gets installed or updated.
if [ "${mcafeeTPInstall}" -ne 0 ]
then
    # DAT is packaged separately only for ePO package hence only if install type is ePO we need to extract DAT
    if [ ${installType} = "epo" ]
    then
        # Fresh installation
        if [ "${mcafeeTPInstall}" -eq 1 ]
        then
            # Copy the DAT files before installation of the product
            tar -C / -xzf "${tmpDir}/${datTarFile}"
            if [ $? -ne 0 ]
            then
                logMessage "Failed to extract the DAT files from ${tmpDir}/${datTarFile} to /"
                restoreProcessStateAndAbort 13
            fi
        fi
        # Upgrade Scenario
        if [ "${mcafeeTPInstall}" -eq 2 ]
        then
            rm -rf /opt/McAfee/upgradetmp/tp
            # Create the temp upgrade directory
            mkdir -p /opt/McAfee/upgradetmp/tp
            # Copy the DAT files before upgrade of the product
            tar -C /opt/McAfee/upgradetmp/tp -xzf "${tmpDir}/${datTarFile}"
            if [ $? -ne 0 ]
            then
                logMessage "Failed to extract the DAT files from ${tmpDir}/${datTarFile} to /opt/McAfee/upgradetmp/tp"
                restoreProcessStateAndAbort 13
            fi
        fi
        # In case of ePO deployment disable auto content update on start-up as it will be done by MA based on MA policy.
        disableAutoContentUpdate="yes"
    fi

    if [ ${disableAutoContentUpdate} == "yes" ]
    then
        # The env variable MFE_DISABLE_CONTENT_UPDATE will be read in postinst scripts of RPM and Debian and the prefs.xml will be updated accordingly.
        export MFE_DISABLE_CONTENT_UPDATE="yes"
    fi

    if [ "${mcafeeTPInstall}" -ne 2 ] || [ ${vselInstalled} -eq 1 ]
    then
        if [ ${enableGTI} == "no" ]
        then
            # The env variable MFE_DISABLE_GTI will be read in postinst scripts of RPM and Debian and the prefs.xml will be updated accordingly.
            export MFE_DISABLE_GTI="yes"
        fi
    fi

    if [ ${enableOAS} == "no" ]
    then
        # The env variable MFE_DISABLE_OAS will be read in postinst scripts of RPM and Debian and the prefs.xml will be updated accordingly.
        export MFE_DISABLE_OAS="yes"
    else
        # If it is a fresh installation, then only try enabling OAS. Since it is possible that previously
        # customer might have intentionally turned it off. Maintain that state forward.
        if [ ${mcafeeTPInstall} -eq 1 ]
        then
            export MFE_DISABLE_OAS="no"
        fi
    fi

    # if no cli option is given for AP state, then by default disable AP
    if [ ${enableAP} == "no_cmdline_option_given_for_ap_state" ]
    then
        # Disable AP by default if its a fresh install and no command line option is given for ap.
        if [ "${mcafeeTPInstall}" -eq 1 ]
        then
            export MFE_DISABLE_AP="yes"
        fi
    elif [ ${enableAP} == "no" ]
    then
        export MFE_DISABLE_AP="yes"
    else
        export MFE_DISABLE_AP="no"
    fi

    if [ ${enableOASDeferredScan} == "yes" ]
    then
        # The env variable MFE_ENABLE_OAS_DEFERRED_SCAN will be read in postinst scripts of RPM and Debian and the prefs.xml will be updated accordingly.
        export MFE_ENABLE_OAS_DEFERRED_SCAN="yes"
    fi

    if [ ${setOasCpuLimit} == "yes" ]
    then
        # The env variable MFE_SET_OAS_CPU_LIMIT will be read in postinst scripts of RPM and Debian and the prefs.xml will be updated accordingly.
        export MFE_SET_OAS_CPU_LIMIT="yes"
        export MFE_OAS_CPU_LIMIT_VALUE=$oasCpuLimit
    fi

    installOrUpgradeTP "${MFE_TP_PACKAGE_FILE}" ${mcafeeTPInstall}
    # If VSEL was previously installed on a ubuntu system, then
    # - For debian system, uninstall VSEL as it does not get automatically uninstalled
    if [ "${vselInstalled}" -eq 1 ]
    then
        if [ ${DEB_VARIANT} != "no" ]
        then
            uninstall  McAfeeVSEForLinux "McAfeeVSEForLinux"
        fi
    fi

    # After VSEL is uninstalled, the library cache may not be updated
    # Run ldconfig to update the library cache
    LANG=C LC_CTYPE=C /opt/McAfee/ens/runtime/3.0/lib/ldconfig -C /etc/ld-mfeensrt-3.0.so.cache -f /etc/ld-mfeensrt-3.0.so.conf >/dev/null 2>&1

    # Do scheduling of default client update task, only if this is not an upgrade scenario
    if [ ${mcafeeTPInstall} -ne 2 ]
    then
        scheduleDATAndEngineUpdate
        if [ $? -eq 0 ]
        then
            logMessage "Schedule for Default DAT and Engine update task was successfully added"
        else
            logMessage "Failed to add schedule for Default DAT and Engine update task"
        fi
    fi

    # Give time for McAfeeTP to start and Message Bus to initialize
    sleep 3

    # Use Fanotify depending on the value of the flag 'useFanotify'
    if [ ${mcafeeTPInstall} -ne 2 -o "${vselInstalled}" -eq 1 ]
    then
        if [ ${useFanotify} == "yes" ]
        then
            FILEACCESS_KMOD_SCRIPTS_DIR=/opt/McAfee/ens/esp/modules/fileaccess/scripts
            ${FILEACCESS_KMOD_SCRIPTS_DIR}/fileaccess-control.sh usefanotify
            if [ $? -eq 1 ]
            then
                enableUseFanotify
                if [ $? -eq 0 ]
                then
                    logMessage "Fanotify is enabled for OAS successfully"
                else
                    logMessage "Failed to enable Fanotify for OAS"
                fi
            else
                logMessage "usefanotify option is not supported in this distribution, ignoring usefanotify option"
            fi
        fi
    fi

    if [ ${mcafeeTPInstall} -ne 2 -a "${ePOInstaller}" -eq 0  ]
    then
        if [ ${scanOnWrite} == "yes" ]
        then
            setSOWForOASStandardProfile
        fi
    fi

    if [ "${mcafeeTPInstall}" -ne 2 ] || [ ${vselInstalled} -eq 1 ]
    then
        # Check if GTI is enabled or disabled as per configuration
        isGTIStateApplied
        if [ $? -eq 0 ]
        then
            if [ ${enableGTI} == "yes" ]
            then
                logMessage "Successfully enabled GTI"
            else
                logMessage "GTI was specifically disabled during installation"
            fi
        else
            logMessage "Failed to apply GTI configuration"
        fi
    fi

    if [ ${enableOAS} == "no" ]
    then
        # Check if OAS is enabled or disabled as per configuration
        isOASStateApplied
        if [ $? -eq 0 ]
        then
            logMessage "OAS was specifically disabled during installation"
        else
            logMessage "Failed to disable OAS"
        fi
    else
        if [ ${mcafeeTPInstall} -eq 1 ]
        then
            logMessage "Enabling OAS, please wait for some time"
            isOASStateApplied
            if [ $? -eq 0 ]
            then
                logMessage "OAS was successfully enabled"
            else
                logMessage "Failed to enable OAS"
            fi
        fi
    fi

    if [ ${mcafeeTPInstall} -eq 1 ]
    then
        # Check if OAS deferred scan is enabled or disabled as per configuration
        isDeferredScanStateApplied
        if [ $? -eq 0 ]
        then
            if [ ${enableOASDeferredScan} == "yes" ]
            then
                logMessage "Successfully enabled OAS deferred scan"
                logMessage "Run setoascpulimit to set CPU usage limit for OAS. Note: Default limit is 100."
            fi
        else
            logMessage "Failed to apply OAS deferred scan configuration"
        fi
        # Check if OAS cpu throttling is set as per configuration
        isOasCpuThrottlingApplied
        if [ $? -eq 0 ]
        then
            if [ ${setOasCpuLimit} == "yes" ]
            then
                logMessage "Successfully set OAS cpu usage limit"
            fi
        else
            logMessage "Failed to apply OAS cpu usage limit configuration"
        fi
    fi

    if [ ${enableAP} == "no_cmdline_option_given_for_ap_state" ]
    then
        if [ "${mcafeeTPInstall}" -eq 1 ]
        then
            enableAP="no"
            isAPStateApplied
            if [ $? -eq 0 ]
            then
                logMessage "Access Protection was specifically disabled during installation"
            else
                logMessage "Failed to disable Access Protection"
            fi
        fi
    elif [ ${enableAP} == "no" ]
    then
        isAPStateApplied
        if [ $? -eq 0 ]
        then
            logMessage "Access Protection was specifically disabled during installation"
        else
            logMessage "Failed to disable Access Protection"
        fi
    else
        isAPStateApplied
        if [ $? -eq 0 ]
        then
            logMessage "Access Protection was specifically enabled during installation"
        else
            logMessage "Failed to enable Access Protection"
        fi
    fi
fi
# Delete the temporary directory
rm -rf "${tmpDir}"

# For 'prompt' install type, show message
# For 'silent' install type, do nothing
# For 'epo' install type, do nothing
# Only in case of fresh install execute this code
if [ "${mcafeeTPInstall}" -eq 1 ]
then
    if [ "${installType}" = "prompt" ]
    then
        logMessage "McAfeeTP is ready for use now"
    fi
fi

# Try to uninstall legacy runtime packages which are not shipped by ESP anymore
bash /opt/McAfee/ens/esp/scripts/uninstall-legacy-rt.sh > /dev/null 2>&1

# For VSEL 1.9.x, show a message to the user to reboot the system
if [ "${vsel19Installed}" -eq 1 ]
then
    logMessage "Please reboot the machine to uninstall McAfeeVSEForLinux"
    exit 15
fi
exit 0
