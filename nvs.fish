# NVS (Node Version Switcher)
# Implemented as a POSIX-compliant function.
# To use, source this file from your profile.
# Inspired by NVM (https://github.com/creationix/nvm)
# and other node version switching tools.

# This shell script merely bootstraps node.exe if necessary, then forwards
# arguments to the main nvs.js script.

set NVS_ROOT (dirname (realpath (status current-filename)))
set NVS_OS (uname | sed 'y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/')

switch "$NVS_OS"
    case 'mingw64_nt*' 'msys_nt*'
        set NVS_OS 'win'
end

function nvs
	# The NVS_HOME path may be overridden in the environment.
	if not set -q NVS_HOME
		set NVS_HOME $NVS_ROOT
	end

 	# Generate 32 bits of randomness, to avoid clashing with concurrent executions.
 	set -gx NVS_POSTSCRIPT $NVS_HOME/nvs_tmp_(dd if=/dev/urandom count=1 2> /dev/null | cksum | cut -f1 -d" ").fish

	set -l NODE_EXE node
	if test "$NVS_OS" = "win"
		set NODE_EXE "node.exe"
	end

 	set -l NODE_PATH $NVS_HOME/cache/$NODE_EXE

	if not test -f $NODE_PATH
 		# Parse the bootstrap parameters from defaults.json. This isn't real JSON parsing so # 		# its extremely limited, but defaults.json should not be edited by the user anyway.
 		set -l NODE_VERSION (grep '"bootstrap" *:' "$NVS_ROOT/defaults.json" | sed -e 's/.*: *"//' -e 's/"[^\n]*//' -e 's/.*\///')
 		set -l NODE_REMOTE (grep '"bootstrap" *:' "$NVS_ROOT/defaults.json" | sed -e 's/.*: *"//' -e 's/"[^\n]*//' -e 's/\/.*//')
 		set -l NODE_BASE_URI (grep "\"$NODE_REMOTE\" *:" "$NVS_ROOT/defaults.json" | sed -e 's/.*: *"//' -e 's/"[^\n]*//')

 		set -l NODE_ARCHIVE_EXT ".tar.gz"
 		set -l TAR_FLAGS "-zxvf"

		if test "$NVS_OS" = "win"
			set NODE_ARCHIVE_EXT ".7z"
		else if test "$NVS_USE_XZ" = "1"
			set NODE_ARCHIVE_EXT ".tar.xz"
			set TAR_FLAGS "-Jxvf"
		end

 		# Download a node binary to use to bootstrap the NVS script.
 		# SmartOS (SunOS) reports `i86pc` which is synonymous with both x86 and x64.
 		set -l NODE_ARCH (uname -m | sed -e 's/x86_64/x64/;s/i86pc/x64/;s/i686/x86/;s/aarch64/arm64/')
 		# On AIX `uname -m` reports the machine ID number of the hardware running the system.
 		if test "$NVS_OS" = "aix"
 			set NODE_ARCH "ppc64"
 		end
 		# Automatically select x64 instead of arm64 when on macOS
 		if test "$NVS_OS" = "darwin"; and test "$NODE_ARCH" = "arm64"
 			set NODE_ARCH "x64"
 		end
 		set -l NODE_FULLNAME "node-v$NODE_VERSION-$NVS_OS-$NODE_ARCH"
 		set -l NODE_URI {$NODE_BASE_URI}v$NODE_VERSION/{$NODE_FULLNAME}$NODE_ARCHIVE_EXT
 		set -l NODE_ARCHIVE "$NVS_HOME/cache/$NODE_FULLNAME$NODE_ARCHIVE_EXT"

		if not test -d "$NVS_HOME/cache"
			mkdir -p "$NVS_HOME/cache"
		end

		echo "Downloading bootstrap node from $NODE_URI"
		if type noglob > /dev/null 2>&1
			noglob curl -L --progress-bar "$NODE_URI" -o "$NODE_ARCHIVE"
		else
			curl -L --progress-bar "$NODE_URI" -o "$NODE_ARCHIVE"
		end

 		if not test -f "$NODE_ARCHIVE"; and test "$NODE_ARCHIVE_EXT" = ".tar.xz"
 			# The .xz download was not found -- fallback to .gz
 			set NODE_ARCHIVE_EXT ".tar.gz"
 			set TAR_FLAGS "-zxvf"
 			set NODE_ARCHIVE "$NVS_HOME/cache/$NODE_FULLNAME$NODE_ARCHIVE_EXT"
 			echo "Retry download bootstrap node from $NODE_URI in gz format"
 			if type noglob > /dev/null 2>&1
 				noglob curl -L --progress-bar "$NODE_URI" -o "$NODE_ARCHIVE"
 			else
 				curl -L --progress-bar "$NODE_URI" -o "$NODE_ARCHIVE"
 			end
 		end

 		if not test -f "$NODE_ARCHIVE"
 			echo "Failed to download node binary."
 			return 1
 		end

 		if test "$NVS_OS" = "win"
			"$NVS_ROOT/tools/7-Zip/7zr.exe" e "-o$NVS_HOME/cache" -y "$NODE_ARCHIVE" "$NODE_FULLNAME/$NODE_EXE" > /dev/null 2>&1
 		else
 			if test "$NVS_OS" = "aix"
 				gunzip "$NODE_ARCHIVE" | tar -xvC "$NVS_HOME/cache" "$NODE_FULLNAME/bin/$NODE_EXE" > /dev/null 2>&1
 			else
 				tar $TAR_FLAGS "$NODE_ARCHIVE" -C "$NVS_HOME/cache" "$NODE_FULLNAME/bin/$NODE_EXE" > /dev/null 2>&1
 			end
 			mv "$NVS_HOME/cache/$NODE_FULLNAME/bin/$NODE_EXE" "$NVS_HOME/cache/$NODE_EXE" > /dev/null 2>& 1
 			rm -r "$NVS_HOME/cache/$NODE_FULLNAME" > /dev/null 2>& 1
 		end

 		if not test -f "$NODE_PATH"
 			echo "Failed to setup node binary."
 			return 1
 		end
 		echo ""
	end

	set -l EXIT_CODE 0

	# Check if invoked as a CD function that enables auto-switching.
	switch "$argv"
		case "cd"
			# Find the nearest .node-version file in current or parent directories
			set -l DIR $PWD

			while test "$DIR" != ""; and not test -e "$DIR/.node-version"; and not test -e "$DIR/.nvmrc"
				if test "$DIR" = "/"
					set -e DIR
				else
					set DIR (dirname "$DIR")
				end
			end

			# If it's different from the last auto-switched directory, then switch.
			if test "$DIR" != "$NVS_AUTO_DIRECTORY"
				eval "$NODE_PATH" "$NVS_ROOT/lib/index.js" auto
				set EXIT_CODE $status
			end

			set NVS_AUTO_DIRECTORY=$DIR
		case "*"
			# Forward args to the main JavaScript file.
			eval "$NODE_PATH" "$NVS_ROOT/lib/index.js" "$argv"
			set EXIT_CODE $status
	end

	if test $EXIT_CODE = 2
		# The bootstrap node version is wrong. Delete it and start over.
		rm "$NODE_PATH"
		nvs $argv
	end

	# Call the post-invocation script if it is present, then delete it.
	# This allows the invocation to potentially modify the caller's environment (e.g. PATH)
	if test -f "$NVS_POSTSCRIPT"
		source "$NVS_POSTSCRIPT"
		rm "$NVS_POSTSCRIPT"
		set -e NVS_POSTSCRIPT
	end

	return $EXIT_CODE
end


function nvsudo
	# Forward the current version path to the sudo environment.
	set -l NVS_CURRENT (nvs which)
	if test -n "$NVS_CURRENT"
		set NVS_CURRENT (dirname "$NVS_CURRENT")
	end
	sudo "env NVS_CURRENT=$NVS_CURRENT" "$NVS_ROOT/nvs" $argv
end

if test "$NVS_OS" != "win"; and test "$NVS_OS" != "aix"
	# Check if `tar` has xz support. Look for a minimum libarchive or gnutar version.
	if test -z "$NVS_USE_XZ"
		set -gx LIBARCHIVE_VER (tar --version | sed -n "s/.*libarchive \([0-9][0-9]*\(\.[0-9][0-9]*\)*\).*/\1/p")
		if test -n "$LIBARCHIVE_VER"
			set LIBARCHIVE_VER (printf "%.3d%.3d%.3d" (echo "$LIBARCHIVE_VER" | sed "s/\\./ /g"))
			if test $LIBARCHIVE_VER -ge 002008000
				set -gx NVS_USE_XZ 1
				if test "$NVS_OS" = "darwin"
					set -gx MACOS_VER (printf "%.3d%.3d%.3d" (sw_vers -productVersion | sed "s/\\./ /g"))
					if $MACOS_VER -ge 010009000
						set -gx NVS_USE_XZ 1
					else
						set -gx NVS_USE_XZ 0
					end
					set -gx MACOS_VER
				end
			else
				set -gx NVS_USE_XZ 0
			end
		else
			set -gx LIBARCHIVE_VER (tar --version | sed -n "s/.*(GNU tar) \([0-9][0-9]*\(\.[0-9][0-9]*\)*\).*/\1/p")
			if test -n "$LIBARCHIVE_VER"
				set LIBARCHIVE_VER (printf "%.3d%.3d%.3d" (echo "$LIBARCHIVE_VER" | sed "s/\\./ /g"))
				if test $LIBARCHIVE_VER -ge 001022000
					if command -v xz &> /dev/null
						set -gx NVS_USE_XZ 1
					else
						set -gx NVS_USE_XZ 0
					end
				else
					set -gx NVS_USE_XZ 0
				end
			end
		end
		set -e LIBARCHIVE_VER
	end
end

# # If some version is linked as the default, begin by using that version.
if test -d "$NVS_HOME/default"
	if test -f "$NVS_HOME/default/bin/node"
		fish_add_path -p "$NVS_HOME/default/bin"
		set -e NPM_CONFIG_PREFIX
	else if test -f "$NVS_HOME/default/node"
		fish_add_path -p "$NVS_HOME/default"
		set -e NPM_CONFIG_PREFIX
	end
end

# # If sourced with parameters, invoke the function now with those parameters.
if test -n "$argv"; and test -z "$NVS_EXECUTE"
	nvs $argv
end
