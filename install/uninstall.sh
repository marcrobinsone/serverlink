#!/bin/bash
umask 022

usage() {
  local prog=`basename "$0"`
  echo "
Usage: $prog -y [ options ] <install_dir>

  Options:
    -d          enable debug, print every command executed
    -T          don't stop taskd

  This script removes all DevPanel software and related data. You'll lose
  data if you run this script!
"

  if [ $EUID -ne 0 ]; then
    echo "This script requires ROOT privileges to be run."
    echo
  fi

  exit 1
}

set_global_variables() {
  local source_dir="$1"
  local target_dir="$2"
  local distro="$3"

  # initialize global variables used throughout this script

  local we_config_dir="$source_dir/config"

  # main config file to be used by DevPanel
  dp_config_file="$target_dir/etc/devpanel.conf"

  _apache_logs_dir=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/var/log/apache_logs_dir")
  if [ $? -ne 0  -o -z "$_apache_logs_dir" ]; then
    echo "unable to set global variable _apache_logs_dir" 1>&2
    return 1
  fi

   _apache_vhost_logs_dir=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/var/log/apache_vhosts")
  if [ $? -ne 0  -o -z "$_apache_vhost_logs_dir" ]; then
    echo "unable to set global variable _apache_vhost_logs_dir" 1>&2
    return 1
  fi
  
  _apache_base_dir=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/etc/apache_base_dir")
  if [ $? -ne 0  -o -z "$_apache_base_dir" ]; then
    echo "unable to set global variable _apache_base_dir" 1>&2
    return 1
  fi

  _apache_includes_dir=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/etc/apache_includes_dir")
  if [ $? -ne 0  -o -z "$_apache_includes_dir" ]; then
    echo "unable to set global variable _apache_includes_dir" 1>&2
    return 1
  fi

  _apache_vhosts=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/etc/apache_vhosts")
  if [ $? -ne 0  -o -z "$_apache_vhosts" ]; then
    echo "unable to set global variable _apache_vhosts" 1>&2
    return 1
  fi

  _apache_vhosts_removed=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/etc/apache_vhosts_removed")
  if [ $? -ne 0  -o -z "$_apache_vhosts_removed" ]; then
    echo "unable to set global variable _apache_vhosts_removed" 1>&2
    return 1
  fi

  _apache_user=`head -1 "$we_config_dir/os.$distro/names/apache.user"`
  if [ $? -ne 0 -o -z "$_apache_user" ]; then
    echo "unable to resolve apache user" 1>&2
    return 1
  fi


  _apache_group=`head -1 "$we_config_dir/os.$distro/names/apache.group"`
  if [ $? -ne 0 ]; then
    echo "unable to resolve apache group" 1>&2
    return 1
  fi

  _apache_exec_group=`head -1 "$we_config_dir/os.$distro/names/apache-exec.group"`
  if [ $? -ne 0 ]; then
    echo "unable to resolve apache exec group" 1>&2
    return 1
  fi

  _apache_main_config_file=`readlink "$we_config_dir/os.$distro/pathnames/etc/apache_main_config_file"`
  if [ $? -ne 0 -o -z "$_apache_main_config_file" ]; then
    echo "unable to resolve apache_main_config_file" 1>&2
    return 1
  fi

  return 0
}

# main

[ $# -eq 0 ] && usage

if [ "${0:0:1}" != / ]; then
  echo "Error: please run this script with the full path, non-relative." 1>&2
  exit 1
fi
script_dir=`dirname "$0"`

if [ $EUID -ne 0 ]; then
  echo "Error: This script needs to run with ROOT privileges." 1>&2
  exit 1
fi

unset confirmed dont_stop_taskd
getopt_flags='ydT'
while getopts $getopt_flags OPTN; do
  case "$OPTN" in
    y)
      confirmed=1
      ;;
    d)
      set -x
      ;;
    T)
      dont_stop_taskd=1
      ;;
    *)
      exit 1
      ;;
  esac
done
shift $(( $OPTIND - 1 ))

if [ -z "$confirmed" ]; then
  echo "Error: please use option -y to confirm that you really want to uninstall the software and lose data" 1>&2
  exit 1
fi

install_dir="$1"
if [[ "$install_dir" =~ ^/*$ ]]; then
  echo "Error: install_dir can't be /" 1>&2
  exit 1
fi

if [ ! -e "$install_dir" ]; then
  echo "Error: path '$install_dir' doesn't exist" 1>&2
  exit 1
fi

if [ ! -d "$install_dir" ]; then
  echo "Error: path '$install_dir' is not a directory" 1>&2
  exit 1
fi

# cd / to avoid being on the same path of a dir being removed
cd /

lib_file="$install_dir/lib/functions"
if ! source "$lib_file"; then
  echo "Error. Unable to load auxiliary functions from file " 1>&2
  exit 1
fi

linux_distro=$(wedp_auto_detect_distro)
status=$?
if [ $status -ne 0 ]; then
  error "unable to detect the system distribution"
fi

if [ "$linux_distro" == "macosx" ]; then
  exec "$script_dir/uninstall.$linux_distro.sh" -y "$install_dir"
fi

if [ -z "$dont_stop_taskd" ]; then # missing -T
  "$install_dir/libexec/system-services" devpanel-taskd stop
fi

if [ -d "/etc/init.d" ]; then
  rm -f /etc/init.d/devpanel-*
fi

if [ -d "/etc/init.d" ]; then
  rm -f /etc/init/devpanel-*
fi

apache_ctl="$install_dir/config/os/pathnames/sbin/apachectl"

[ -e "$apache_ctl" ] && "$apachectl" stop

rm -f "$_apache_base_dir"/webenabled*
rm -f "$_apache_base_dir"/devpanel*

rm -f "$_apache_includes_dir"/webenabled*
rm -f "$_apache_includes_dir"/devpanel*

if [ -n "$_apache_vhost_logs_dir" ] && \
  ! [[ "$_apache_vhost_logs_dir" =~ ^/*$ ]]; then

  find "$_apache_vhost_logs_dir"/* -exec rm -rf {} \;
fi

# remove databases and vhosts
while read passwd_line; do
  IFS=":" read user x uid gid gecos home shell <<< "$passwd_line"

  if [ ${#user} -gt 2 -a "${user:0:2}" == "w_" ]; then
    vhost=${user#w_}

    # if there's a matching db in db-daemons, then ...
    if db_line=`egrep "^b_$vhost:" "$install_dir/compat/dbmgr/config/db-daemons.conf"`; then
      if getent passwd "b_$vhost" &>/dev/null; then
        # b_et:mysql:5.1.41-gm2:/home/clients/databases/b_et/mysql:127.0.0.1:4018:::
        IFS=":" read db_user db_type db_ver db_dir db_host db_port remaining <<< "$db_line"
        if fuser "$db_port/tcp" &>/dev/null; then
          "$install_dir/libexec/remove-vhost" "$vhost" - >/dev/null
          if [ $? -ne 0 ]; then
            "$install_dir/libexec/remove-user" "b_$vhost"
            "$install_dir/libexec/remove-user" "w_$vhost"
          fi
        else
          "$install_dir/libexec/remove-user" "b_$vhost"
          "$install_dir/libexec/remove-user" "w_$vhost"
        fi
      fi
    else # no matching db, just remove the w_ user
      userdel -r "$user"
    fi
  fi
done < <(getent passwd | egrep ^w_)

# remove database users in case it didn't have the w_user companion on
# previous loop
while read passwd_line; do
  IFS=":" read user x uid gid gecos home shell <<< "$passwd_line"
  userdel -r "$user"
done < <(getent passwd | egrep ^b_)

if [ -d /home/clients/databases ]; then
  rm -rf /home/clients/databases/*

  for D in /home/clients/databases/*; do
    fuser -k "$D/mysql" 
  done
fi

if [ -d /home/clients/websites ]; then 
  rm -rf /home/clients/websites/*

  for D in /home/clients/websites/*; do
    fuser -k "$D"
  done
fi

vagrant_dir=~devpanel/vagrant
if [ -d "$vagrant_dir" ]; then
  for D in "$vagrant_dir"/*; do
    if [ -d "$D" ]; then
      echo "Destroying VM `basename "$D"`..."
      su -l -c "cd $D && vagrant destroy -f ; cd $D/.. ; rm -rf $D" devpanel
    fi
  done
fi

for u in git w_ devpanel; do
  if getent passwd "$u" &>/dev/null; then
    userdel -r "$u"
  fi
done

for g in virtwww weadmin w_ devpanel; do
  if getent group "$g" &>/dev/null; then
    groupdel "$g"
  fi
done

rm -rf "$install_dir"

if [ -z "$dont_stop_taskd" ]; then # missing -T
  [ -d /var/log/webenabled ] && rm -rf /var/log/webenabled
fi

echo
echo "Successfully removed devPanel software"
