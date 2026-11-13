#!/bin/bash

set -e
mode=build 
for arg in "$@"
do
	case $arg in
		--start=*)
			start="yes"
			shift
			;;
		--name=*)
			name="${arg#*=}"
			shift
      ;;
		-m=*|--mode=*)
			mode="${arg#*=}"
			shift
			;;
		-s=*|--swap=*)
			: # Accepted legacy option; currently has no effect.
			shift
			;;
	esac
done


script_path=$0
script_name=$(basename $0)
if [ "$(whoami)" != "root" ]
then 
  echo "PERMISSION DENIED: $script_path requires root privilege"
  exit 1
fi 

# ------------------------------
# 
# --------------------------------
usage() {
  echo "Usage $script_name --name=username --mode=[dist|build]"
  exit 1
}

case $mode in
  build|dist)
    ;;
  *)
    usage
esac


if [[ $script_path =~ ^\/ ]]; then
  script_dir=$(dirname $script_path)
else 
  if [[ $script_path =~ ^\.\/ ]]; then
    script_path=$(echo $script_path | sed -e "s/^\.//")
    script_dir="$(pwd)$(dirname $script_path)"
  else 
    script_dir=$(pwd)/$(dirname $script_path)
  fi
fi 

# ------------------------------
# 
# --------------------------------
create_sys_user() {
  if [ -z $1 ]; then
    usage
  fi

  user=$1
  home=/home/$user
  if [ -d $home ]; then
    echo "$home exists"
    return 0
  fi
  zfs create data/home/$user
  useradd -m -d $home -s /bin/bash $user
  #useradd -d $home $user
  adduser $user www-data
  #mkdir $home
  #zfs create data/home/$user
  mkdir $home/.ssh
  chmod 700 $home/.ssh
  cp $script_dir/templates/.bashrc $home/
  cp $script_dir/templates/.profile $home/

  echo "
  [user]
    email = $user@drumee.net    
    name = $user 
  [push]
    default = simple" > $home/.gitconfig
  return 0
}


# ------------------------------
# 
# --------------------------------
create_target() {
  name=$1
  echo "Checking target $1"
  if [ ! -d $DRUMEE_UI_HOME/build/$name ]; then
    mkdir -p $DRUMEE_UI_HOME/build/$name
    chown -R $name:$name $DRUMEE_UI_HOME/build/$name
  fi
  if [ ! -d $DRUMEE_SERVER_HOME/build/$name ]; then
    mkdir -p $DRUMEE_SERVER_HOME/build/$name
    chown -R $name:$name $DRUMEE_SERVER_HOME/build/$name
  fi
  if [ ! -d $DRUMEE_LOG_DIR/$name ]; then
    mkdir -p $DRUMEE_LOG_DIR/$name
    chown -R www-data:www-data $DRUMEE_LOG_DIR/$name
  fi

}

if [ -z $name ]; then
  usage
fi 

source /etc/drumee/drumee.sh 
case $script_name in
  'create-user')
    create_sys_user $name
    ;;
  'create-devel')
    if [ ! -d /home/$name ]; then
      create_sys_user $name
    fi
    create_target $name
    ;;
  'create-instance')
    if [ ! -d /home/$name ]; then
      create_sys_user $name
    fi
    create_target $name
    if [ "$(/usr/share/drumee/setup/show-instance --name=$name)" == "" ]; then
      /usr/share/drumee/setup/add-instance --name=$name --mode=$mode
    fi 
    if [ "$start" == "yes" ]; then
      /usr/sbin/drumee start $name
      /usr/sbin/drumee start $name/service
    fi 
    ;;
esac

