# Node Version Manager
# Implemented as a POSIX-compliant function
# Should work on sh, dash, bash, ksh, zsh
# To use source this file from your bash profile
#
# Implemented by Tim Caswell <tim@creationix.com>
# with much bash help from Matthew Ranney

NVM_SCRIPT_SOURCE="$_"

nvm_has() {
  type "$1" > /dev/null 2>&1
}

nvm_download() {
  if nvm_has "curl"; then
    curl $*
  elif nvm_has "wget"; then
    # Emulate curl with wget
    ARGS=$(echo "$*" | sed -e 's/--progress-bar /--progress=bar /' \
                           -e 's/-L //' \
                           -e 's/-I /--server-response /' \
                           -e 's/-s /-q /' \
                           -e 's/-o /-O /' \
                           -e 's/-C - /-c /')
    eval wget $ARGS
  fi
}

nvm_has_system_node() {
  [ "$(nvm deactivate 2> /dev/null && command -v node)" != '' ]
}

# Make zsh glob matching behave same as bash
# This fixes the "zsh: no matches found" errors
if nvm_has "unsetopt"; then
  unsetopt nomatch 2>/dev/null
  NVM_CD_FLAGS="-q"
fi

# Auto detect the NVM_DIR when not set
if [ -z "$NVM_DIR" ]; then
  if [ -n "$BASH_SOURCE" ]; then
    NVM_SCRIPT_SOURCE="${BASH_SOURCE[0]}"
  fi
  export NVM_DIR=$(cd $NVM_CD_FLAGS $(dirname "${NVM_SCRIPT_SOURCE:-$0}") > /dev/null && pwd)
fi
unset NVM_SCRIPT_SOURCE 2> /dev/null


# Setup mirror location if not already set
if [ -z "$NVM_NODEJS_ORG_MIRROR" ]; then
  export NVM_NODEJS_ORG_MIRROR="http://nodejs.org/dist"
fi

nvm_tree_contains_path() {
  local tree
  tree="$1"
  local node_path
  node_path="$2"

  if [ "@$tree@" = "@@" ] || [ "@$node_path@" = "@@" ]; then
    >&2 echo "both the tree and the node path are required"
    return 2
  fi

  local pathdir
  pathdir=$(dirname "$node_path")
  while [ "$pathdir" != "" ] && [ "$pathdir" != "." ] && [ "$pathdir" != "/" ] && [ "$pathdir" != "$tree" ]; do
    pathdir=$(dirname "$pathdir")
  done
  [ "$pathdir" = "$tree" ]
}

# Traverse up in directory tree to find containing folder
nvm_find_up() {
  local path
  path=$PWD
  while [ "$path" != "" ] && [ ! -f "$path/$1" ]; do
    path=${path%/*}
  done
  echo "$path"
}


nvm_find_nvmrc() {
  local dir
  dir="$(nvm_find_up '.nvmrc')"
  if [ -e "$dir/.nvmrc" ]; then
    echo "$dir/.nvmrc"
  fi
}

# Obtain nvm version from rc file
nvm_rc_version() {
  local NVMRC_PATH
  NVMRC_PATH="$(nvm_find_nvmrc)"
  if [ -e "$NVMRC_PATH" ]; then
    read NVM_RC_VERSION < "$NVMRC_PATH"
    echo "Found '$NVMRC_PATH' with version <$NVM_RC_VERSION>"
  else
    >&2 echo "No .nvmrc file found"
    return 1
  fi
}

nvm_version_greater() {
  local LHS
  LHS=$(nvm_normalize_version "$1")
  local RHS
  RHS=$(nvm_normalize_version "$2")
  [ $LHS -gt $RHS ];
}

nvm_version_greater_than_or_equal_to() {
  local LHS
  LHS=$(nvm_normalize_version "$1")
  local RHS
  RHS=$(nvm_normalize_version "$2")
  [ $LHS -ge $RHS ];
}

nvm_version_dir() {
  local NVM_USE_NEW_DIR
  NVM_USE_NEW_DIR="$1"
  if [ -z "$NVM_USE_NEW_DIR" ] || [ "$NVM_USE_NEW_DIR" = "new" ]; then
    echo "$NVM_DIR/versions"
  elif [ "$NVM_USE_NEW_DIR" = "old" ]; then
    echo "$NVM_DIR"
  else
    echo "unknown version dir" >&2
    return 3
  fi
}

nvm_version_path() {
  local VERSION
  VERSION="$1"
  if [ -z "$VERSION" ]; then
    echo "version is required" >&2
    return 3
  elif nvm_version_greater 0.12.0 "$VERSION"; then
    echo "$(nvm_version_dir old)/$VERSION"
  else
    echo "$(nvm_version_dir new)/$VERSION"
  fi
}

# Expand a version using the version cache
nvm_version() {
  local PATTERN
  PATTERN=$1
  local VERSION
  # The default version is the current one
  if [ -z "$PATTERN" ]; then
    PATTERN='current'
  fi

  if [ "$PATTERN" = "current" ]; then
    nvm_ls_current
    return $?
  fi

  VERSION=`nvm_ls $PATTERN | tail -n1`
  echo "$VERSION"

  if [ "$VERSION" = 'N/A' ]; then
    return 3
  fi
}

nvm_remote_version() {
  local PATTERN
  PATTERN=$1
  local VERSION
  VERSION=`nvm_ls_remote $PATTERN | tail -n1`
  echo "$VERSION"

  if [ "$VERSION" = 'N/A' ]; then
    return 3
  fi
}

nvm_normalize_version() {
  echo "$1" | sed -e 's/^v//' | \awk -F. '{ printf("%d%06d%06d\n", $1,$2,$3); }'
}

nvm_format_version() {
  echo "$1" | sed -e 's/^\([0-9]\)/v\1/g'
}

nvm_num_version_groups() {
  local VERSION
  VERSION="$1"
  if [ -z "$VERSION" ]; then
    echo "0"
    return
  fi
  local NVM_NUM_DOTS
  NVM_NUM_DOTS=$(echo "$VERSION" | sed -e 's/^v//' | sed -e 's/\.$//' | sed -e 's/[^\.]//g')
  local NVM_NUM_GROUPS
  NVM_NUM_GROUPS=".$NVM_NUM_DOTS"
  echo "${#NVM_NUM_GROUPS}"
}

nvm_strip_path() {
  echo "$1" | sed -e "s#$NVM_DIR/[^/]*$2[^:]*:##g" -e "s#:$NVM_DIR/[^/]*$2[^:]*##g" -e "s#$NVM_DIR/[^/]*$2[^:]*##g"
}

nvm_prepend_path() {
  if [ -z "$1" ]; then
    echo "$2"
  else
    echo "$2:$1"
  fi
}

nvm_binary_available() {
  # binaries started with node 0.8.6
  local FIRST_VERSION_WITH_BINARY
  FIRST_VERSION_WITH_BINARY="0.8.6"
  nvm_version_greater_than_or_equal_to "$1" "$FIRST_VERSION_WITH_BINARY"
}

nvm_ls_current() {
  local NODE_PATH
  NODE_PATH="$(which node 2> /dev/null)"
  if [ $? -ne 0 ]; then
    echo 'none'
  elif nvm_tree_contains_path "$NVM_DIR" "$NODE_PATH"; then
    local VERSION
    VERSION=`node -v 2>/dev/null`
    if [ "$VERSION" = "v0.6.21-pre" ]; then
      echo "v0.6.21"
    else
      echo "$VERSION"
    fi
  else
    echo 'system'
  fi
}

nvm_ls() {
  local PATTERN
  PATTERN=$1
  local VERSIONS
  VERSIONS=''
  if [ "$PATTERN" = 'current' ]; then
    nvm_ls_current
    return
  fi

  if [ -f "$NVM_DIR/alias/$PATTERN" ]; then
    nvm_version `cat $NVM_DIR/alias/$PATTERN`
    return
  fi
  # If it looks like an explicit version, don't do anything funny
  if [ "~$(echo "$PATTERN" | cut -c1-1)" = "~v" ] &&  [ "~$(nvm_num_version_groups "$PATTERN")" = "~3" ]; then
    if [ -d "$(nvm_version_path "$PATTERN")" ]; then
      VERSIONS="$PATTERN"
    fi
  else
    PATTERN=$(nvm_format_version $PATTERN)
    if [ "~$PATTERN" != "~system" ]; then
      local NUM_VERSION_GROUPS
      NUM_VERSION_GROUPS="$(nvm_num_version_groups "$PATTERN")"
      if [ "~$NUM_VERSION_GROUPS" = "~2" ] || [ "~$NUM_VERSION_GROUPS" = "~1" ]; then
        PATTERN="$(echo "$PATTERN" | sed -e 's/\.*$//g')."
      fi
    fi
    if [ -d "$(nvm_version_dir new)" ]; then
      VERSIONS=`find "$(nvm_version_dir new)/" "$(nvm_version_dir old)/" -maxdepth 1 -type d -name "$PATTERN*" -exec basename '{}' ';' \
        | sort -t. -u -k 1.2,1n -k 2,2n -k 3,3n | \grep -v '^ *\.' | \grep -e '^v' | \grep -v -e '^versions$'`
    else
      VERSIONS=`find "$(nvm_version_dir old)/" -maxdepth 1 -type d -name "$PATTERN*" -exec basename '{}' ';' \
        | sort -t. -u -k 1.2,1n -k 2,2n -k 3,3n | \grep -v '^ *\.' | \grep -e '^v'`
    fi
  fi

  if nvm_has_system_node; then
    if [ -z "$PATTERN" ]; then
      VERSIONS="$VERSIONS$(printf '\n%s' 'system')"
    elif [ "$PATTERN" = 'system' ]; then
      VERSIONS="$(printf '%s' 'system')"
    fi
  fi

  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  fi

  echo "$VERSIONS"
  return
}

nvm_ls_remote() {
  local PATTERN
  PATTERN=$1
  local VERSIONS
  local GREP_OPTIONS
  GREP_OPTIONS=''
  if [ -n "$PATTERN" ]; then
    PATTERN=`nvm_format_version "$PATTERN"`
  else
    PATTERN=".*"
  fi
  VERSIONS=`nvm_download -s $NVM_NODEJS_ORG_MIRROR/ -o - \
              | \egrep -o 'v[0-9]+\.[0-9]+\.[0-9]+' \
              | \grep -w "${PATTERN}" \
              | sort -t. -u -k 1.2,1n -k 2,2n -k 3,3n`
  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  fi
  echo "$VERSIONS"
  return
}

nvm_checksum() {
  if nvm_has "sha1sum"; then
    checksum=$(sha1sum $1 | \awk '{print $1}')
  elif nvm_has "sha1"; then
    checksum=$(sha1 -q $1)
  else
    checksum=$(shasum $1 | \awk '{print $1}')
  fi

  if [ "$checksum" = "$2" ]; then
    return
  elif [ -z "$2" ]; then
    echo 'Checksums empty' #missing in raspberry pi binary
    return
  else
    echo 'Checksums do not match.' >&2
    return 1
  fi
}

nvm_print_versions() {
  local VERSION
  local FORMAT
  local NVM_CURRENT
  NVM_CURRENT=$(nvm_ls_current)
  echo "$1" | while read VERSION; do
    if [ "$VERSION" = "$NVM_CURRENT" ]; then
      FORMAT='\033[0;32m-> %9s\033[0m'
    elif [ -d "$(nvm_version_path "$VERSION")" ]; then
      FORMAT='\033[0;34m%12s\033[0m'
    elif [ "$VERSION" = "system" ]; then
      FORMAT='\033[0;33m%12s\033[0m'
    else
      FORMAT='%12s'
    fi
    printf "$FORMAT\n" $VERSION
  done
}

nvm() {
  if [ $# -lt 1 ]; then
    nvm help
    return
  fi

  # Try to figure out the os and arch for binary fetching
  local uname
  uname="$(uname -a)"
  local os
  local arch
  arch="$(uname -m)"
  local GREP_OPTIONS
  GREP_OPTIONS=''
  case "$uname" in
    Linux\ *) os=linux ;;
    Darwin\ *) os=darwin ;;
    SunOS\ *) os=sunos ;;
    FreeBSD\ *) os=freebsd ;;
  esac
  case "$uname" in
    *x86_64*) arch=x64 ;;
    *i*86*) arch=x86 ;;
    *armv6l*) arch=arm-pi ;;
  esac

  # initialize local variables
  local VERSION
  local ADDITIONAL_PARAMETERS
  local ALIAS

  case $1 in
    "help" )
      echo
      echo "Node Version Manager"
      echo
      echo "Usage:"
      echo "    nvm help                    Show this message"
      echo "    nvm --version               Print out the latest released version of nvm"
      echo "    nvm install [-s] <version>  Download and install a <version>, [-s] from source. Uses .nvmrc if available"
      echo "    nvm uninstall <version>     Uninstall a version"
      echo "    nvm use <version>           Modify PATH to use <version>. Uses .nvmrc if available"
      echo "    nvm run <version> [<args>]  Run <version> with <args> as arguments. Uses .nvmrc if available for <version>"
      echo "    nvm current                 Display currently activated version"
      echo "    nvm ls                      List installed versions"
      echo "    nvm ls <version>            List versions matching a given description"
      echo "    nvm ls-remote               List remote versions available for install"
      echo "    nvm deactivate              Undo effects of NVM on current shell"
      echo "    nvm alias [<pattern>]       Show all aliases beginning with <pattern>"
      echo "    nvm alias <name> <version>  Set an alias named <name> pointing to <version>"
      echo "    nvm unalias <name>          Deletes the alias named <name>"
      echo "    nvm copy-packages <version> Install global NPM packages contained in <version> to current version"
      echo "    nvm unload                  Unload NVM from shell"
      echo
      echo "Example:"
      echo "    nvm install v0.10.24        Install a specific version number"
      echo "    nvm use 0.10                Use the latest available 0.10.x release"
      echo "    nvm run 0.10.24 myApp.js    Run myApp.js using node v0.10.24"
      echo "    nvm alias default 0.10.24   Set default node version on a shell"
      echo
      echo "Note:"
      echo "    to remove, delete, or uninstall nvm - just remove ~/.nvm, ~/.npm, and ~/.bower folders"
      echo
    ;;

    "install" | "i" )
      # initialize local variables
      local binavail
      local t
      local url
      local sum
      local tarball
      local nobinary
      local version_not_provided
      version_not_provided=0
      local provided_version

      if ! nvm_has "curl" && ! nvm_has "wget"; then
        echo 'nvm needs curl or wget to proceed.' >&2;
        return 1
      fi

      if [ $# -lt 2 ]; then
        version_not_provided=1
        nvm_rc_version
        if [ -z "$NVM_RC_VERSION" ]; then
          nvm help
          return
        fi
      fi

      shift

      nobinary=0
      if [ "$1" = "-s" ]; then
        nobinary=1
        shift
      fi

      if [ "$os" = "freebsd" ]; then
        nobinary=1
      fi

      provided_version=$1

      if [ -z "$provided_version" ]; then
        if [ $version_not_provided -ne 1 ]; then
          nvm_rc_version
        fi
        provided_version="$NVM_RC_VERSION"
      else
        shift
      fi
      [ -d "$(nvm_version_path "$provided_version")" ] && echo "$provided_version is already installed." >&2 && return

      VERSION=`nvm_remote_version $provided_version`
      ADDITIONAL_PARAMETERS=''

      while [ $# -ne 0 ]
      do
        ADDITIONAL_PARAMETERS="$ADDITIONAL_PARAMETERS $1"
        shift
      done

      if [ -d "$(nvm_version_path "$VERSION")" ]; then
        echo "$VERSION is already installed." >&2
        nvm use "$VERSION"
        return $?
      fi

      if [ "$VERSION" = "N/A" ]; then
        echo "Version '$provided_version' not found - try \`nvm ls-remote\` to browse available versions." >&2
        return 3
      fi

      # skip binary install if no binary option specified.
      if [ $nobinary -ne 1 ]; then
        # shortcut - try the binary if possible.
        if [ -n "$os" ]; then
          if nvm_binary_available "$VERSION"; then
            t="$VERSION-$os-$arch"
            url="$NVM_NODEJS_ORG_MIRROR/$VERSION/node-${t}.tar.gz"
            sum=`nvm_download -s $NVM_NODEJS_ORG_MIRROR/$VERSION/SHASUMS.txt -o - | \grep node-${t}.tar.gz | \awk '{print $1}'`
            local tmpdir
            tmpdir="$NVM_DIR/bin/node-${t}"
            local tmptarball
            tmptarball="$tmpdir/node-${t}.tar.gz"
            if (
              mkdir -p "$tmpdir" && \
              nvm_download -L -C - --progress-bar $url -o "$tmptarball" && \
              nvm_checksum "$tmptarball" $sum && \
              tar -xzf "$tmptarball" -C "$tmpdir" --strip-components 1 && \
              rm -f "$tmptarball" && \
              mv "$tmpdir" "$(nvm_version_path "$VERSION")"
              )
            then
              nvm use $VERSION
              return $?
            else
              echo "Binary download failed, trying source." >&2
              rm -rf "$tmptarball" "$tmpdir"
            fi
          fi
        fi
      fi

      if [ -n "$ADDITIONAL_PARAMETERS" ]; then
        echo "Additional options while compiling: $ADDITIONAL_PARAMETERS"
      fi

      tarball=''
      sum=''
      make='make'
      if [ "$os" = "freebsd" ]; then
        make='gmake'
        MAKE_CXX="CXX=c++"
      fi
      local tmpdir
      tmpdir="$NVM_DIR/src"
      local tmptarball
      tmptarball="$tmpdir/node-$VERSION.tar.gz"
      if [ "`nvm_download -s -I "$NVM_NODEJS_ORG_MIRROR/$VERSION/node-$VERSION.tar.gz" -o - 2>&1 | \grep '200 OK'`" != '' ]; then
        tarball="$NVM_NODEJS_ORG_MIRROR/$VERSION/node-$VERSION.tar.gz"
        sum=`nvm_download -s $NVM_NODEJS_ORG_MIRROR/$VERSION/SHASUMS.txt -o - | \grep node-$VERSION.tar.gz | \awk '{print $1}'`
      elif [ "`nvm_download -s -I "$NVM_NODEJS_ORG_MIRROR/node-$VERSION.tar.gz" -o - | \grep '200 OK'`" != '' ]; then
        tarball="$NVM_NODEJS_ORG_MIRROR/node-$VERSION.tar.gz"
      fi
      if (
        [ -n "$tarball" ] && \
        mkdir -p "$tmpdir" && \
        nvm_download -L --progress-bar $tarball -o "$tmptarball" && \
        nvm_checksum "$tmptarball" $sum && \
        tar -xzf "$tmptarball" -C "$tmpdir" && \
        cd "$tmpdir/node-$VERSION" && \
        ./configure --prefix="$(nvm_version_path "$VERSION")" $ADDITIONAL_PARAMETERS && \
        $make $MAKE_CXX && \
        rm -f "$(nvm_version_path "$VERSION")" 2>/dev/null && \
        $make $MAKE_CXX install
        )
      then
        nvm use $VERSION
        if ! nvm_has "npm" ; then
          echo "Installing npm..."
          if nvm_version_greater 0.2.0 "$VERSION"; then
            echo "npm requires node v0.2.3 or higher" >&2
          elif nvm_version_greater_than_or_equal_to "$VERSION" 0.2.0; then
            if nvm_version_greater 0.2.3 "$VERSION"; then
              echo "npm requires node v0.2.3 or higher" >&2
            else
              nvm_download https://npmjs.org/install.sh -o - | clean=yes npm_install=0.2.19 sh
            fi
          else
            nvm_download https://npmjs.org/install.sh -o - | clean=yes sh
          fi
        fi
      else
        echo "nvm: install $VERSION failed!" >&2
        return 1
      fi
    ;;
    "uninstall" )
      [ $# -ne 2 ] && nvm help && return
      PATTERN=`nvm_format_version $2`
      if [ "$PATTERN" = `nvm_version` ]; then
        echo "nvm: Cannot uninstall currently-active node version, $PATTERN." >&2
        return 1
      fi
      VERSION=`nvm_version $PATTERN`
      if [ ! -d "$(nvm_version_path "$VERSION")" ]; then
        echo "$VERSION version is not installed..." >&2
        return;
      fi

      t="$VERSION-$os-$arch"

      # Delete all files related to target version.
      rm -rf "$NVM_DIR/src/node-$VERSION" \
             "$NVM_DIR/src/node-$VERSION.tar.gz" \
             "$NVM_DIR/bin/node-${t}" \
             "$NVM_DIR/bin/node-${t}.tar.gz" \
             "$(nvm_version_path "$VERSION")" 2>/dev/null
      echo "Uninstalled node $VERSION"

      # Rm any aliases that point to uninstalled version.
      for ALIAS in `\grep -l $VERSION $NVM_DIR/alias/* 2>/dev/null`
      do
        nvm unalias `basename $ALIAS`
      done

    ;;
    "deactivate" )
      local NEWPATH
      NEWPATH="$(nvm_strip_path "$PATH" "/bin")"
      if [ "$PATH" = "$NEWPATH" ]; then
        echo "Could not find $NVM_DIR/*/bin in \$PATH" >&2
      else
        export PATH="$NEWPATH"
        hash -r
        echo "$NVM_DIR/*/bin removed from \$PATH"
      fi

      NEWPATH="$(nvm_strip_path "$MANPATH" "/share/man")"
      if [ "$MANPATH" = "$NEWPATH" ]; then
        echo "Could not find $NVM_DIR/*/share/man in \$MANPATH" >&2
      else
        export MANPATH="$NEWPATH"
        echo "$NVM_DIR/*/share/man removed from \$MANPATH"
      fi

      NEWPATH="$(nvm_strip_path "$NODE_PATH" "/lib/node_modules")"
      if [ "$NODE_PATH" = "$NEWPATH" ]; then
        echo "Could not find $NVM_DIR/*/lib/node_modules in \$NODE_PATH" >&2
      else
        export NODE_PATH="$NEWPATH"
        echo "$NVM_DIR/*/lib/node_modules removed from \$NODE_PATH"
      fi
    ;;
    "use" )
      if [ $# -eq 0 ]; then
        nvm help
        return 127
      fi
      if [ $# -eq 1 ]; then
        nvm_rc_version
        if [ -n "$NVM_RC_VERSION" ]; then
          VERSION=`nvm_version $NVM_RC_VERSION`
        fi
      else
        if [ $2 = 'system' ]; then
          if nvm_has_system_node && nvm deactivate; then
            echo "Now using system version of node: $(node -v 2>/dev/null)."
            return
          else
            echo "System version of node not found." >&2
            return 127
          fi
        else
          VERSION=`nvm_version $2`
        fi
      fi
      if [ -z "$VERSION" ]; then
        nvm help
        return 127
      fi
      if [ -z "$VERSION" ]; then
        VERSION=`nvm_version $2`
      fi
      local NVM_VERSION_DIR
      NVM_VERSION_DIR="$(nvm_version_path "$VERSION")"
      if [ ! -d "$NVM_VERSION_DIR" ]; then
        echo "$VERSION version is not installed yet" >&2
        return 1
      fi
      # Strip other version from PATH
      PATH=`nvm_strip_path "$PATH" "/bin"`
      # Prepend current version
      PATH=`nvm_prepend_path "$PATH" "$NVM_VERSION_DIR/bin"`
      if [ -z "$MANPATH" ]; then
        MANPATH=$(manpath)
      fi
      # Strip other version from MANPATH
      MANPATH=`nvm_strip_path "$MANPATH" "/share/man"`
      # Prepend current version
      MANPATH=`nvm_prepend_path "$MANPATH" "$NVM_VERSION_DIR/share/man"`
      # Strip other version from NODE_PATH
      NODE_PATH=`nvm_strip_path "$NODE_PATH" "/lib/node_modules"`
      # Prepend current version
      NODE_PATH=`nvm_prepend_path "$NODE_PATH" "$NVM_VERSION_DIR/lib/node_modules"`
      export PATH
      hash -r
      export MANPATH
      export NODE_PATH
      export NVM_PATH="$NVM_VERSION_DIR/lib/node"
      export NVM_BIN="$NVM_VERSION_DIR/bin"
      if [ "$NVM_SYMLINK_CURRENT" = true ] || [ -z "$NVM_SYMLINK_CURRENT" ]; then
        rm -f "$NVM_DIR/current" && ln -s "$NVM_VERSION_DIR" "$NVM_DIR/current"
      fi
      echo "Now using node $VERSION"
    ;;
    "run" )
      local provided_version
      local has_checked_nvmrc
      has_checked_nvmrc=0
      # run given version of node
      shift
      if [ $# -lt 1 ]; then
        nvm_rc_version && has_checked_nvmrc=1
        if [ -n "$NVM_RC_VERSION" ]; then
          VERSION=`nvm_version $NVM_RC_VERSION`
        else
          VERSION='N/A'
        fi
        if [ $VERSION = "N/A" ]; then
          nvm help
          return 127
        fi
      fi

      provided_version=$1
      if [ -n "$provided_version" ]; then
        VERSION=`nvm_version $provided_version`
        if [ $VERSION = "N/A" ]; then
          provided_version=''
          if [ $has_checked_nvmrc -ne 1 ]; then
            nvm_rc_version && has_checked_nvmrc=1
          fi
          VERSION=`nvm_version $NVM_RC_VERSION`
        else
          shift
        fi
      fi

      local NVM_VERSION_DIR
      NVM_VERSION_DIR=$(nvm_version_path "$VERSION")
      if [ ! -d "$NVM_VERSION_DIR" ]; then
        echo "$VERSION version is not installed yet" >&2
        return 1
      fi
      RUN_NODE_PATH=`nvm_strip_path "$NODE_PATH" "/lib/node_modules"`
      RUN_NODE_PATH=`nvm_prepend_path "$NODE_PATH" "$NVM_VERSION_DIR/lib/node_modules"`
      echo "Running node $VERSION"
      NODE_PATH=$RUN_NODE_PATH $NVM_VERSION_DIR/bin/node "$@"
    ;;
    "exec" )
      shift

      local provided_version
      provided_version=$1
      if [ -n "$provided_version" ]; then
        VERSION=`nvm_version $provided_version`
        if [ $VERSION = "N/A" ]; then
          provided_version=''
          nvm_rc_version
          VERSION=`nvm_version $NVM_RC_VERSION`
        else
          shift
        fi
      fi

      local NVM_VERSION_DIR
      NVM_VERSION_DIR=$(nvm_version_path "$VERSION")
      if [ ! -d "$NVM_VERSION_DIR" ]; then
        echo "$VERSION version is not installed yet" >&2
        return 1
      fi
      echo "Running node $VERSION"
      NODE_VERSION=$VERSION $NVM_DIR/nvm-exec "$@"
    ;;
    "ls" | "list" )
      local NVM_LS_OUTPUT
      local NVM_LS_EXIT_CODE
      NVM_LS_OUTPUT=$(nvm_ls "$2")
      NVM_LS_EXIT_CODE=$?
      nvm_print_versions "$NVM_LS_OUTPUT"
      if [ $# -eq 1 ]; then
        nvm alias
      fi
      return $NVM_LS_EXIT_CODE
    ;;
    "ls-remote" | "list-remote" )
      nvm_print_versions "`nvm_ls_remote $2`"
      return
    ;;
    "current" )
      nvm_version current
    ;;
    "alias" )
      mkdir -p $NVM_DIR/alias
      if [ $# -le 2 ]; then
        local DEST
        for ALIAS in $NVM_DIR/alias/$2*; do
          if [ -e "$ALIAS" ]; then
            DEST=`cat $ALIAS`
            VERSION=`nvm_version $DEST`
            if [ "$DEST" = "$VERSION" ]; then
              echo "$(basename $ALIAS) -> $DEST"
            else
              echo "$(basename $ALIAS) -> $DEST (-> $VERSION)"
            fi
          fi
        done
        return
      fi
      if [ -z "$3" ]; then
        rm -f $NVM_DIR/alias/$2
        echo "$2 -> *poof*"
        return
      fi
      mkdir -p $NVM_DIR/alias
      VERSION=`nvm_version $3`
      if [ $? -ne 0 ]; then
        echo "! WARNING: Version '$3' does not exist." >&2
      fi
      echo $3 > "$NVM_DIR/alias/$2"
      if [ ! "$3" = "$VERSION" ]; then
        echo "$2 -> $3 (-> $VERSION)"
      else
        echo "$2 -> $3"
      fi
    ;;
    "unalias" )
      mkdir -p $NVM_DIR/alias
      [ $# -ne 2 ] && nvm help && return 127
      [ ! -f "$NVM_DIR/alias/$2" ] && echo "Alias $2 doesn't exist!" >&2 && return
      rm -f $NVM_DIR/alias/$2
      echo "Deleted alias $2"
    ;;
    "copy-packages" )
      if [ $# -ne 2 ]; then
        nvm help
        return 127
      fi

      local PROVIDED_VERSION
      PROVIDED_VERSION="$2"

      if [ "$PROVIDED_VERSION" = "$(nvm_ls_current)" ] || [ "$(nvm_version $PROVIDED_VERSION)" = "$(nvm_ls_current)" ]; then
        echo 'Can not copy packages from the current version of node.' >&2
        return 2
      fi

      local INSTALLS
      if [ "$PROVIDED_VERSION" = "system" ]; then
        if ! nvm_has_system_node; then
          echo 'No system version of node detected.' >&2
          return 3
        fi
        INSTALLS=$(nvm deactivate > /dev/null && npm list -g --depth=0 | tail -n +2 | \grep -o -e ' [^@]*' | cut -c 2- | \grep -v npm | xargs)
      else
        local VERSION
        VERSION="$(nvm_version "$PROVIDED_VERSION")"
        INSTALLS=$(nvm use "$VERSION" > /dev/null && npm list -g --depth=0 | tail -n +2 | \grep -o -e ' [^@]*' | cut -c 2- | \grep -v npm | xargs)
      fi

      echo "$INSTALLS" | xargs npm install -g --quiet
    ;;
    "clear-cache" )
      rm -f $NVM_DIR/v* "$(nvm_version_dir)" 2>/dev/null
      echo "Cache cleared."
    ;;
    "version" )
      nvm_version $2
    ;;
    "--version" )
      echo "0.16.1"
    ;;
    "unload" )
      unset -f nvm nvm_print_versions nvm_checksum nvm_ls_remote nvm_ls nvm_remote_version nvm_version nvm_rc_version nvm_version_greater nvm_version_greater_than_or_equal_to > /dev/null 2>&1
      unset RC_VERSION NVM_NODEJS_ORG_MIRROR NVM_DIR NVM_CD_FLAGS > /dev/null 2>&1
    ;;
    * )
      nvm help
    ;;
  esac
}

if nvm ls default >/dev/null; then
  nvm use default >/dev/null
elif nvm_rc_version >/dev/null 2>&1; then
  nvm use >/dev/null
fi

