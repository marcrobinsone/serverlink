ubuntu_set_variables() {
  return 0
}

ubuntu_pre_run() {
  return 0
}

ubuntu_install_distro_packages() {
  local install_dir="$1"
  local ubuntu_version="${2:-0}"

  export DEBIAN_FRONTEND='noninteractive'

  apt-get update

  echo -n Checking for update-rc.d availability: 
  if hash update-rc.d ; then
    echo Already there
  else
      echo Not found, installing sysvinit
      apt-get -y install sysvinit
  fi

  for i in \
    curl apache2 libapache2-mod-macro apache2-suexec zlib1g libapache2-mod-fcgid \
    mysql-server git subversion \
    php5 php5-cli php-pear php5-gd php5-curl php5-mysql \
    php5-cgi php5-mcrypt php5-sqlite libjson-xs-perl libcrypt-ssleay-perl libcgi-session-perl
  do
    apt-get -y install $i
  done

  # this is Ubuntu specific, that right now doesn't ship with a default MTA
  # if there isn't anything listening on port 25/tcp then we install Postfix
  # for the sites to be able to send e-mail
  if ! fuser -s 25/tcp; then
    apt-get install postfix
  fi
}

ubuntu_adjust_system_config() {
  local install_dir="$1"

  if [ -r /etc/apparmor.d/usr.sbin.mysqld ]
  then
    sed -i 's/^[:space:]*[^#]/#/' /etc/apparmor.d/usr.sbin.mysqld
    if [ -r /etc/init.d/apparmor ]
    then
      /etc/init.d/apparmor reload
    fi
  fi

  for module in rewrite macro suexec ssl proxy proxy_http; do
    if [ ! -e "$_apache_base_dir/mods-enabled/$module.load" \
      -a -f "$_apache_base_dir/mods-available/$module.load" ]; then
      ln -sf ../mods-available/$module.load "$_apache_base_dir"/mods-enabled/
    fi
  done

  # fuser fails on slicehost CentOS  (/proc/net/tcp is empty)
  #if fuser 443/tcp >/dev/null || netstat -ln --tcp|grep -q :443
  #then
  #  :
  #else
  #  echo 'Listen 443' >> "$_apache_base_dir"/conf.d/webenabled.conf
  #fi

  [ -e "$_apache_base_dir"/mods-enabled/php5.load ] && rm -f "$_apache_base_dir"/mods-enabled/php5.load
  [ -e "$_apache_base_dir"/mods-enabled/php5.conf ] && rm -f "$_apache_base_dir"/mods-enabled/php5.conf

  [ -e /etc/init.d/dbmgr ] && rm -f /etc/init.d/dbmgr
  ln -s "$install_dir"/compat/dbmgr/current/bin/dbmgr.init /etc/init.d/devpanel-dbmgr
  update-rc.d devpanel-dbmgr defaults
}

ubuntu_post_users_n_groups() {
  return 0
}

ubuntu_post_software_install() {
  return 0
}
