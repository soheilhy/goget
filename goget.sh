#!/bin/bash
#
#	Copyright (c) 2015, Soheil Hassas Yeganeh (soheil@cs.toronto.edu)
#
# goget.sh [OPTIONS] pkg1 [pkg2 ...]
#    -v=GOVERSION: sets the minimum version of go required to
#                  install the package (default: 1.4.2).
#    -h=GOHOME: overrrides the default go install path (default: ~/go).
#

PLATFORM=`uname`
MACHINE=`uname -m`

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
CLEAR='\033[0m'

PROGRESS_MARKS=( "|" "/" "-" "\\" )
PROGRESS=0

progress_reset() {
  PROGRESS=0
  MARK=${PROGRESS_MARKS[$PROGRESS]}

  progress_print "$MARK" "$@"
}

progress_tick() {
  PROGRESS=$(((PROGRESS+1) % 4))
  MARK=${PROGRESS_MARKS[$PROGRESS]}

  progress_print "$MARK" "$@"
}

progress_print() {
  MARK=$1
  TITLE=$2
  MSG=$3

  if [ -n "$MSG" ]; then
    MSG=": $MSG"
  fi
  printf "\r%s${GREEN}${MARK}   ${WHITE}%s${CLEAR}%s" "$(tput el)" "$TITLE" \
      "$MSG"
}

progress_done() {
  TITLE=$1
  MSG=$2
  MARK="+"

  progress_print "$MARK" "$TITLE" "$MSG"
  printf "\n"
}

progress_error() {
  TITLE=$1
  MSG=$2

  printf "\r%s${RED}-   ${WHITE}%s${CLEAR}: ${RED}%s${CLEAR}\n" \
      "$(tput el)" "$TITLE" "$MSG"
}


progress_fatal() {
  progress_error "$@"
  exit -1
}

ask() {
  TITLE=$1
  QUESTION=$2

  printf "\r%s${YELLOW}?   ${WHITE}%s${CLEAR}: ${YELLOW}%s${CLEAR}" \
      "$(tput el)" "$TITLE" "$QUESTION"
  read -u 2 ASK_RESULT
}

confirm() {
  TITLE=$1
  QUESTION="$2 (YES or NO) "
  ASK_RESULT=""

  while [[ $ASK_RESULT != "YES" && $ASK_RESULT != "NO" ]]; do
    ask $TITLE "$QUESTION"
		ASK_RESULT=`echo ${ASK_RESULT} | awk '{print toupper($0)}'`
  done
}

BGDONE=$PWD/.goget.done

run_in_background() {
  CMD=$1
  PRG_TITLE=$2
  PRG_TICK=$3
	SUDO=$4

  rm -f $BGDONE

	CMD="($CMD && echo 0 > $BGDONE) || echo 1 > $BGDONE"
	if [ "$SUDO" ]; then 
		sudo bash -c "eval \"$CMD\" & disown"
	else
		eval "$CMD" & disown
	fi

  while [ ! -f $BGDONE ] ; do
    if [ ! -z "$PRG_TITLE" ]; then
      progress_tick "$PRG_TITLE" "$PRG_TICK"
    fi
    sleep .1
  done

	if [ "$SUDO" ]; then
		sudo chown $USER $BGDONE
	fi

  BGRETCODE=`cat $BGDONE`
  if [[ $BGRETCODE == '0' ]]; then
    BGRETCODE=''
  fi

  rm -f $BGDONE
}

install_deps() {
  progress_tick "go" "checking dependencies..."

	DEPS=()

  if ! hash git 2>/dev/null; then
		DEPS+=(git)
  fi

	if ! hash gcc 2>/dev/null; then
		DEPS+=(gcc)
		if [[ $PLATFORM == "Linux" ]]; then
			if hash apt-get 2>/dev/null; then 
				DEPS+=(libc6-dev)
			else
				DEPS+=(glibc-devel)
			fi
		fi
	fi

	if [ -z $DEPS ]; then
		progress_tick "go" "all dependencies are already installed"
		return
	fi

	progress_tick "go" "installing ${DEPS[@]}..."

	case $PLATFORM in 
		"Linux")
			if hash apt-get 2>/dev/null; then 
				CMD="apt-get -y update &>/dev/null &&
						 apt-get -y install ${DEPS[@]} &>/dev/null"
			else
				CMD="yum -y install ${DEPS[@]} &>/dev/null"
			fi
			;;
		"Darwin")
			if ! hash "xcode-select" 2>/dev/null; then
				progress_fatal "go" "please install X-Code"
			fi
			CMD="xcode-select --install"
			;;
	esac

	DEPS=`echo ${DEPS[@]}`
	DEPS=${DEPS// /,}
	run_in_background "$CMD" "go" "installing $DEPS..." "sudo"
	if [ $BGRETCODE ]; then
		progress_fatal "go" "cannot install $DEPS"
	fi
}

version() {
  VER=$1
  echo ${VER//./ }
}

install_go() {
  GOVERSION=$1
  GOHOME=$2

  VARR=( `version $GOVERSION` )
  GOMAJOR=${VARR[0]}
  GOMINOR=${VARR[1]}
  GOPATCH=${VARR[2]}

  progress_reset "go" "installing go..."

  if hash go 2>/dev/null; then
    progress_tick "go" "checking go version..."

    INSTALLVERSION=`go version | cut -d " " -f 3`
    # Drop the go prefix from go version.
    INSTALLVERSION=${INSTALLVERSION:2}

    VARR=( `version $INSTALLVERSION` )
    INSTALLMINOR=${VARR[1]}
    if (( $GOMINOR <= $INSTALLMINOR )) ; then
      progress_done "go" "already installed"
      return
    fi

    confirm "go" \
        "do you want to upgrade go from $INSTALLVERSION to $GOVERSION?"
    if [[ $ASK_RESULT != "YES" ]]; then
      progress_fatal "go" "cannot install $GOVERSION"
    fi

    progress_tick go "upgrading go from $INSTALLVERSION to $GOVERSION"
  fi

  if [ -e $GOHOME ]; then
    confirm "go" "do you want to remove $GOHOME?"
    if [[ $ASK_RESULT != "YES" ]]; then
      progress_fatal "go" "$GOHOME already exists"
    fi
    rm -rf $GOHOME
  fi

  LIB=$GOHOME/lib
  mkdir -p $LIB || progress_fatal "go" "cannot create $LIB"
  progress_tick "go" "$GOHOME created"

  install_deps

  TARBALL="go$GOVERSION.src.tar.gz"
  TARBALL_URL="https://storage.googleapis.com/golang/$TARBALL"
  run_in_background "curl $TARBALL_URL >$TARBALL 2>/dev/null" "go" \
      "downloading go..."

  if [[ $BGRETCODE ]]; then
    rm -rf $GOHOME
    progress_fatal "go" "cannot download $TARBALL_URL"
  fi

  run_in_background "tar -xvzf $TARBALL -C $LIB &>/dev/null" "go" \
      "unpacking ${TARBALL}..."

  if [[ $BGRETCODE ]]; then
    rm -rf $GOHOME
    rm $TARBALL
    progress_fatal "go" "cannot unpack $TARBALL"
  fi

  progress_tick "go" "installing go..."
	rm -f "$TARBALL" 2>/dev/null

  # Reset go environment variables in case we have an older setup.
  export GOROOT=""
  export GOPATH=""

  GOROOT=$LIB/go$GOVERSION
  mv $LIB/go $GOROOT 2>/dev/null || progress_fatal "go" \
      "cannot move $LIB/go to $GOROOT"

  PREV=$PWD
  cd $GOROOT/src
  run_in_background "./make.bash &>/dev/null" "go" "building go..."
  cd $PREV
  if [[ $BGRETCODE ]]; then
    rm -rf $GOHOME
    progress_fatal "go" "cannot build go"
  fi

  progress_tick "go" "setting up environment variables..."

  export GOROOT
  export PATH="$GOPATH/bin:$GOROOT/bin:$PATH"

	add_to_rc "GOROOT=$GOROOT" "PATH=\$GOROOT/bin:$PATH"

  progress_done go "$GOVERSION successfully installed"
}

setup_workspace() {
  GOHOME=$1

  progress_reset "workspace" "setting up workspace..."
  if [ ! -z "$GOPATH" ]; then
		HAS_WORKSPACE="yes"
    progress_done "workspace" "reusing workspace in $GOPATH"
    return
  fi

  progress_tick "workspace" "setting up environment variables..."
  export GOPATH=$GOHOME/workspace
  mkdir -p $GOPATH || progress_fatal "workspace" "cannot create $GOPATH"
  export PATH="$GOPATH/bin:$GOROOT/bin:$PATH"

  add_to_rc "GOPATH=$GOPATH" "PATH=\$GOPATH/bin:$PATH"

  progress_done "workspace" "successfully created in $GOPATH"
}

add_to_rc() {
	if [[ $PLATFORM == "Darwin" ]]; then
		PROFILES=("$HOME/.bash_profile")
	else
		PROFILES=("$HOME/.bashrc")
	fi

	if [ -s $HOME/.zshrc ]; then
		PROFILES=("${PROFILES[@]}" "$HOME/.zshrc")
	fi

  for PROFILE in ${PROFILES[@]}; do
    echo >> $PROFILE
    echo "# The followings lines are generated by goget.sh" >> $PROFILE
    for LINE in $@; do
      echo "export $LINE" >> $PROFILE
    done
  done
}

get_package() {
  PKG=$1

  progress_reset $PKG
  run_in_background "go get $PKG &>/dev/null" "$PKG" "installing..."
  if [[ $BGRETCODE ]]; then
    progress_fatal "$PKG" "error in installing $PKG. run go get $PKG again"
  fi

  progress_done $PKG "successfully installed"
}

print_summary() {
  PKG=$1

	if [ $HAS_WORKSPACE ]; then
		return
	fi

  printf "\n${WHITE}packages are installed in %s/src${CLEAR}\n" "$GOPATH"
	printf "please open a new terminal, or run \"exec -l $SHELL\"\n"
}

usage_exit() {
  printf "goget.sh [-v=goversion] [-h=gohome] pkg1 [pkg2 ...]\n" 1>&2
  exit -1
}

GOHOME=${HOME}/go
GOVERSION=1.4.2
PKGS=()

for ARG in $@; do 
  case $ARG in
    -v=*)
      GOVERSION="${ARG#*=}"
      ;;
    -h=*)
      GOHOME="${ARG#*=}"
      ;;
    -*)
      usage_exit
      ;;
    *)
      PKGS+=($ARG)
      ;;
  esac
done

if [ -z $PKGS ]; then 
	usage_exit
fi

install_go $GOVERSION $GOHOME
setup_workspace $GOHOME

for PKG in ${PKGS[@]}; do
  get_package $PKG
done

print_summary

