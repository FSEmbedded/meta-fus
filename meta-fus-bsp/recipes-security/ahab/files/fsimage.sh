#!/bin/bash
#
# Script to list and extract the contents of a file with prepended F&S header.
#
# The header can optionally have a type, a description, a set of 16 1-bit flags
# and up to 32 8-bit parameters, 16 16-bit parameters, eight 32-bit parameters
# or four 64-bit parameters, or any combination of them. These parameters can
# be used arbitrarily, for example to specify an entry point for some kind of
# executable. The flags can be used to indicate the presence of some
# information. In addition, the size of the final image data can be padded with
# zeroes to satisfy alignment requirements and a CRC32 checksum (with or
# without the header) can be included if needed.
#
# The size of the header depends on the version, which is currently V0.0 (16
# bytes) or V1.0 (64 bytes). The old version V0.0 was used in the past to
# prepend the file size to a file so that a serial download program could
# download the file without having to know the size beforehand and thus
# requiring to pad the file to this size. So the header content actually only
# consisted of the magic number to indicate the presence of the header and the
# (32-bit) file size. The bytes for file_size_high, flags, padsize and version
# were reserved for future use and were always set to 0. This can be used now
# to detect the old header as V0.0.
#
# In fact from the current point of view, it does not contradict the header
# specification if the additional fields in the V0.0 header are set, too, as
# long as the version stays at 0.0. But the existing download programs (like
# i.MX6/Vybrid NBoot) will simply ignore these values. So for example the image
# size can not exceed 4 GiB (2^32 bytes) in V0.0 because only the lower 32 bits
# of the size are evaluated. This script will also ignore these additional
# fields in case of a V0.0 header.
#
# Newer applications like the F&S i.MX8 boot process will take advantage of the
# full features of the V1.0 header. It is recommended to use upper case
# characters for the type, avoid spaces in the type, and restrict type and
# description to printable ASCII characters (0x20..0x7e) to avoid any encoding
# problems (different codepages, multi-byte characters, etc). This script will
# show any other character as a simple '.', similar to common hexdump programs.
#
# struct fs_header_v0_0 {		/* Size: 16 Bytes */
#	char magic[4];			/* "FS" + two bytes operating system
#					   (e.g. "LX" for Linux) */
#	u32 file_size_low;		/* Image size [31:0] */
#	u32 file_size_high;		/* Image size [63:32] */
#	u16 flags;			/* See flags below */
#	u8 padsize;			/* Number of padded bytes at end */
#	u8 version;			/* Header version x.y:
#					   [7:4] major x, [3:0] minor y */#
# }
#
# struct fs_header_v1_0 {		/* Size: 64 bytes */
#	struct fs_header_V0_0 info;	/* Image info, see above */
#	char type[16];			/* Image type, e.g. "U-BOOT" */
#	union {
#		char descr[32];		/* Description, null-terminated */
#		u8 p8[32];		/* 8-bit parameters */
#		u16 p16[16];		/* 16-bit parameters */
#		u32 p32[8];		/* 32-bit parameters */
#		u64 p64[4];		/* 64-bit parameters */
#	} param;
# };
#
# /* Possible values for flags entry above */
# #define FSH_FLAGS_DESCR 0x8000	/* Description descr is present */
# #define FSH_FLAGS_CRC32 0x4000	/* CRC32 of image in type[12..15] */
# #define FSH_FLAGS_SECURE 0x2000	/* CRC32 of header in type[12..15] */
# #define FSH_FLAGS_INDEX 0x1000	/* Image contains an index */
# #define FSH_FLAGS_EXTRA 0x0800	/* Extra offset sub-header in p32[7] */

FSH_FLAGS_DESCR=0x8000
FSH_FLAGS_CRC32=0x4000
FSH_FLAGS_SECURE=0x2000
FSH_FLAGS_INDEX=0x1000
FSH_FLAGS_EXTRA=0x0800

# Possible fields in show command
fields="offset magic size os padsize type descr typedescr flags crc32 version"

# Several blanks, used for indendation
bl="                                                                         "

usage()
{
    if [[ $# -gt 0 ]]; then
	echo $* >&2
    fi
    cat <<__USAGE_EOF >&2

Usage:

  $0 [<options>] <in-file> [<index_or_type>]

  <in-file>             The name of the image to analyze
  <index_or_type>	Index or type of image to use (default: 0)

Options:
  -c | --crc32          Verify CRC32 checksum of an image
  -h | --help           Show this usage
  -l | --list           List the infos of all contained images (default)
  -o | --output <file>  Store result as file <file> (default stdout)
  -i | --info           Show all infos of image
  -s | --show <field>   Show appropriate header field; <field> may be one of:
                          version     Header version
                          offset      Offset to beginning of image
                          magic       Magic dumber of the image
                          os          OS part of the magic number
                          size        Size of the image data (incl. padding)
                          padsize     Number of bytes padded at the end
                          type        Type information (up to 16 characters)
                          descr       Description (up to 32 characters)
                          typedescr   Combination '<type> (<descr>)' as shown
                                      in image list
                          flags       Flags value
                          crc32       CRC32 checksum (as stored in the file)
                          p<s>[<i>]   Parameter of size <s> at index <n>
                                      Example: p16[6]
  -x | --xtract         Extract the image data (without header)
  -j | --just-header    Extract just the header (without image data)

__USAGE_EOF
	exit
}

# Reverse bytes in hex string (big endian to little endian or vice versa)
# Input string in $1 must have an even number of digits
reverse()
{
    in=$1
    out=
    while [ -n "$in" ]; do
	out=${in:0:2}$out
	in=${in:2}
    done
    echo $out
}

# Extract string from hex digits in $1
get_string()
{
    temp="$1"
    string=
    while [ -n "$temp" ]; do
	char=${temp:0:2}
	if [ "$char" = "00" ]; then
	    break;
	fi
	# Convert non-printable and non-ASCII characters to '.'
	if [ $((0x$char)) -ge 32 ] && [ $((0x$char)) -lt 127 ]; then
	    string="$string$(printf "\x$char")"
	else
	    string="${string}."
	fi
	temp=${temp:2}
    done
    echo "$string"
}

# Extract all header entries, but do not read more than $1 bytes. Returns 1 if
# no valid F&S header. When returning, variable $headersize contains the number
# of bytes that were actually read from the stream, even in case of error.
get_header_info()
{
    size=$1
    padsize=0
    crc32="[unknown]"
    os="[unknown]"
    version="[unknown]"
    type="[unknown]"
    typedescr="[padding/unknown data]"
    descr="[empty]"
    flags=0
    extra=0

    # Read the first 4 bytes (or less) of the header and use as magic number
    if [ $1 -lt 4 ]; then
	head=$(head -c $1 | xxd -l $1 -c $1 -p)
	globaloffs=$((globaloffs + $1))
    else
	head=$(head -c 4 | xxd -l 4 -c 4 -p)
	globaloffs=$((globaloffs + 4))
    fi
    headersize=$((${#head} / 2))
    magic="$(get_string $head)...."
    magic=${magic:0:$headersize}
    if [ "${magic:0:2}" != "FS" ]; then
#	echo "No FS magic: ${head:0:4}" >&2
	return 1;
    fi

    # Return error if remaining size is less then V0.0 header size
    if [ $1 -lt 16 ]; then
#	echo "Size < 16" >&2
	return 1
    fi

    # Read the next 12 bytes; return error if not enough data available
    head=$head$(head -c 12 | xxd -l 12 -c 12 -p)
    globaloffs=$((globaloffs + 12))
    headersize=$((${#head} / 2))
    if [ $headersize -lt 16 ]; then
#	echo "Size $headersize instead of 16" >&2
	return 1;
    fi

    # Parse V0.0 data; if it is a V0.0 header, then we are done
    os=${magic:2:2}
    size=$((0x$(reverse ${head:8:16})))
    vers=${head:30:2}
    version=$((0x${vers:0:1})).$((0x${vers:1:1}))
    if [ $vers == "00" ]; then
	typedescr="[header version 0.0]"
	size=$(($size & 0xffffffff))
	return 0
    fi

    # Return error if remaining size is less than V1.0 header size
    if [ $1 -lt 64 ]; then
#	echo "Size < 64" >&2
	return 1
    fi

    # Read 48 more bytes; return error if not enough data available
    head=$head$(head -c 48 | xxd -l 48 -c 48 -p)
    globaloffs=$((globaloffs + 48))
    headersize=$((${#head} / 2))
    if [ $headersize -lt 64 ]; then
#	echo "Size $headersize instead of 64" >&2
	return 1;
    fi

#    echo $head >&2

    # Parse V1.0 data
    padsize=$((0x${head:28:2}))
    type=$(get_string ${head:32:32})
    flags=$((0x$(reverse ${head:24:4})))
    if [ $((flags & (FSH_FLAGS_CRC32 | FSH_FLAGS_SECURE))) -ne 0 ]; then
	crc32=$(reverse ${head:56:8})
    fi
    if [ $((flags & (FSH_FLAGS_EXTRA))) -ne 0 ]; then
	extra=$((0x$(reverse ${head:120:8})))
    fi

    typedescr="$type"
    if [[ $(($flags & FSH_FLAGS_DESCR)) -ne 0 ]]; then
	descr=$(get_string ${head:64})
	if [ -n "$descr" ]; then
	    if [ -n "$typedescr" ]; then
		typedescr="$typedescr ($descr)"
	    else
		typedescr="($descr)"
	    fi
	fi
    fi

    return 0
}

# Compute CRC32 and compare with stored value; return 1 on mismatch
do_crc32()
{
    if [[ $(($flags & (FSH_FLAGS_CRC32 | FSH_FLAGS_SECURE))) -eq 0 ]]; then
	echo "File #$index '$typedescr' has no CRC32"
	return 0
    fi

    # If header is required, we need to use a temporary file
    if [[ $(($flags & FSH_FLAGS_SECURE)) -ne 0 ]]; then
	# If header is required, we need to use a temporary file. Set CRC32
	# entry in type[12..15] to 0x00000000 and compute crc32
	head_temp=${head:0:56}00000000${head:64}
	secu_temp=$(mktemp -p . "${0##*/}-temp.XXXXXXXXXX")
	echo -n $head_temp | xxd -r -p > $secu_temp
	if [[ $(($flags & FSH_FLAGS_CRC32)) -ne 0 ]]; then
	    head -c $size >> $secu_temp
	    globaloffs=$((globaloffs + size))
	fi
	computed=$(crc32 "$secu_temp")
	rm "$secu_temp"
    else
	computed=$(head -c $size | crc32 /dev/stdin)
	globaloffs=$((globaloffs + size))
    fi

    if [[ $crc32 = $computed ]]; then
	printf "CRC32 (%s) is OK\n" $crc32
	return 0
    fi
    printf "CRC32 failed, got %s, expected %s\n" $computed $crc32
    return 1
}

# Show all info of an image
do_info()
{
    # Instead of reversing every single number, reverse the whole parameter
    # list; remember that parameters are also ordered back to front then
    p=$(reverse ${head:64:64})

    printf "Image #%d '%s'\n" $index "$typedescr"
    printf "%s\n" "-------------------------------------------------------------------------------"
    printf "version:    %s\n" $version
    printf "offset:     0x$wx\n" $offset
    printf "magic:      %s\n" $magic
    printf "size:       0x$wx\n" $size
    if [ $vers = "00" ]; then
	return
    fi
    printf "padsize     0x%02x\n" $padsize
    printf "type:       '%s'\n" "$type"
    printf "descr:      '%s'\n" $descr
    printf "flags:      0x%04x" $flags
    [ $(($flags & $FSH_FLAGS_DESCR)) -ne 0 ] && printf " DESCR"
    [ $(($flags & $FSH_FLAGS_CRC32)) -ne 0 ] && printf " CRC32"
    [ $(($flags & $FSH_FLAGS_SECURE)) -ne 0 ] && printf " SECURE"
    [ $(($flags & $FSH_FLAGS_EXTRA)) -ne 0 ] && printf " EXTRA(0x%s)" ${p:0:8}
    printf "\ncrc32:      %s\n" $crc32
    printf "\nParameter Interpretations:\n"
    printf "p64[0..1]:  %s %s\n" ${p:48:16} ${p:32:16}
    printf "p64[2..3]:  %s %s\n" ${p:16:16} ${p:0:16}
    printf "p32[0..3]:  %s %s %s %s\n" ${p:56:8} ${p:48:8} ${p:40:8} ${p:32:8}
    printf "p32[4..7]:  %s %s %s %s\n" ${p:24:8} ${p:16:8} ${p:8:8} ${p:0:8}
    printf "p16[0..7]:  %s %s %s %s %s %s %s %s\n" ${p:60:4} ${p:56:4} ${p:52:4} ${p:48:4} ${p:44:4} ${p:40:4} ${p:36:4} ${p:32:4}
    printf "p16[8..15]: %s %s %s %s %s %s %s %s\n" ${p:28:4} ${p:24:4} ${p:20:4} ${p:16:4} ${p:12:4} ${p:8:4} ${p:4:4} ${p:0:4}
    printf "p8[0..15]:  %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s\n" ${p:62:2} ${p:60:2} ${p:58:2} ${p:56:2} ${p:54:2} ${p:52:2} ${p:50:2} ${p:48:2} ${p:46:2} ${p:44:2} ${p:42:2} ${p:40:2} ${p:38:2} ${p:36:2} ${p:34:2} ${p:32:2}
    printf "p8[16..31]: %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s\n" ${p:30:2} ${p:28:2} ${p:26:2} ${p:24:2} ${p:22:2} ${p:20:2} ${p:18:2} ${p:16:2} ${p:14:2} ${p:12:2} ${p:10:2} ${p:8:2} ${p:6:2} ${p:4:2} ${p:2:2} ${p:0:2}
}

# Show a single parameter, specification p<s>[<n>] in $show
do_showp()
{
    # Extract size by stripping the leading 'p' and the trailing '[<n>]'
    temp=${show#p}
    temp=${temp%%\[*}
    if ! size=$(printf "%d" $temp 2> /dev/null); then
	echo "Invalid size $temp in '$show'" >&2
	return 1
    fi
    if [[ ! " 8 16 32 64 " =~ .*\ $size\ .* ]]; then
	echo "Size $temp in '$show' is not one of: 8 16 32 64" >&2
	return 1
    fi

    # Divide by 4 to refer to hex digits
    size=$(($size / 4))

    # Extract index by stripping the leading 'p<s>[' and the trailing ']' 
    temp=${show#*\[}
    temp=${temp%%\]*}
    if ! index=$(printf "%d" $temp 2> /dev/null) || [ $index -lt 0 ]; then
	    echo "Invalid index $temp in '$show'" >&2
	    return 1
    fi
    index=$(($index * $size + 64))
    if [ $index -ge 128 ]; then
	echo "Index $temp in '$show' exceeds parameter area" >&2
	return 1
    fi

    # Output value
#    echo $((0x$(reverse ${head:$index:$size})))
    echo $(reverse ${head:$index:$size})
}

# Show a single value, i.e. the variable whose name is in $show
do_show()
{
    echo ${!show}
}

# Extract an image
do_xtract()
{
    if [ $offset -gt $globaloffs ]; then
	# Skip to real file in case of indexed image
	head -c $((offset - globaloffs)) > /dev/null
    elif [ "${magic:0:2}" != "FS" ]; then
	# In a non-F&S image, reinsert the header part that was already read 
	echo $head | xxd -r -p
	size=$(($size - $headersize))
    fi

    # Output the (remaining) image data, strip the padding
    head -c $(($size - $padsize))
}

# Extract the header of an image
do_justheader()
{
    # We are already beyond the header, but data is still in $head;
    # in a non-F&S image, this is the part that we show as magic number
    echo $head | xxd -r -p
}

# Execute the command in $cmd on the current image at offset $1, indendation $2
handle_command()
{
    offset=$1
    if [[ $cmd = "list" ]]; then
	if [ $(($flags & $FSH_FLAGS_DESCR)) -ne 0 ]; then
	    fl=D
	else
	    fl=-
	fi
	if [ $(($flags & $FSH_FLAGS_CRC32)) -ne 0 ]; then
	    fl=${fl}C
	else
	    fl=${fl}-
	fi
	if [ $(($flags & $FSH_FLAGS_SECURE)) -ne 0 ]; then
	    fl=${fl}S
	else
	    fl=${fl}-
	fi
	if [ $(($flags & $FSH_FLAGS_INDEX)) -ne 0 ]; then
	    fl=${fl}I
	else
	    fl=${fl}-
	fi
	if [ $(($flags & $FSH_FLAGS_EXTRA)) -ne 0 ]; then
	    fl=${fl}E
	else
	    fl=${fl}-
	fi
	printf "%2d: $wx $wx %s %s\n" $index $offset $size $fl "${bl:0:$2}$typedescr"
    elif [ "$sel" = "$type" ] || [ "$sel" = "$typedescr" ] || [ $selnum -eq $index ]; then
	do_$cmd
	exit
    fi

    index=$(($index + 1))
}

# Parse the F&S image; $1: image size, $2: indendation
parse_image()
{
    local remaining=$1
    local savedextra savedoffs found imgoffs

#    echo "in: offs=$offs remaining=$remaining" >&2

    handle_command $((globaloffs - headersize)) $2

    found=0
    if [ $(($flags & $FSH_FLAGS_INDEX)) -ne 0 ]; then
	# An index image consists of headers only, the real images (i.e. the
	# content of each image) follow the index image, one per header
	imgoffs=$((globaloffs + size));

	while [ $remaining -gt 0 ]; do
	    if get_header_info $remaining; then
		# Handle the headers in the index image
		handle_command $imgoffs $2
		imgoffs=$((imgoffs + size))
		remaining=$((remaining - headersize))
	    else
		# Skip remaining part of index image
		remaining=$((remaining - headersize))
		head -c $remaining > /dev/null
		globaloffs=$((globaloffs + remaining))
		remaining=0
	    fi
	done

	# Skip the real images
	head -c $((imgoffs - globaloffs)) > /dev/null
	globaloffs=$imgoffs
    else
	if [ $extra -gt 0 ]; then
	    savedextra=$extra
	    get_header_info $savedextra
	    remaining=$((remaining - headersize))
	    savedextra=$((savedextra - headersize))

        while [[ "${head:6:2}" == "87" ]]; do      
        container
        done

	    typedescr="[header/extra data]"
	    handle_command $((globaloffs - headersize)) $(($2 + 1))
	    head -c $savedextra > /dev/null
	    globaloffs=$((globaloffs + savedextra))
	    remaining=$((remaining - savedextra))
	fi
	while [ $remaining -gt 0 ]; do
	    if get_header_info $remaining; then
		remaining=$((remaining - headersize))
#		if [ $found -eq 0 ]; then
#		    printf "    $wx ----  Starting sub-image list\n" $offs
#		    savedoffs=$globaloffs
#		fi
		found=1
		offs=$globaloffs
		parse_image $((size + extra)) $(($2 + 1))
		remaining=$((remaining - (globaloffs - offs)))
	    else
		remaining=$((remaining - headersize))
		if [ $found -eq 1 ]; then
		    handle_command $((globaloffs - headersize)) $(($2 + 1))
		fi
		# We have already read $headersize bytes, skip remaining image
		head -c $remaining > /dev/null
		globaloffs=$((globaloffs + $remaining))
		remaining=0
	    fi
#	    if [ $remaining -eq 0 ] && [ $found -eq 1 ]; then
#		printf "    $wx ----  Ending sub-image list from offset $wx\n" $globaloffs $savedoffs
#	    fi
#	    echo "globaloffs=$globaloffs remaining=$remaining" >&2
	done
    fi
}

container()
{
        # wir sind bereits 0x4 über den header da die aufrufende Funktion diese Bytes einließt, jede +/- 0x4 kommen daher zustande
        printf "i.MX Container: "

        # get container size
        container_padded=$(($(($(("0x${head:4:2}${head:2:2}" / 0x400)) + 1)) * 0x400))

        # get container type
        container_flags=$(head -c $headersize | xxd -l $headersize -c $headersize -p)
        if [[ ${container_flags:0:2} -eq 01 ]]; then
            printf "type: NXP, "
        else
            printf "type: OEM, "
        fi

        # skip unnecessary data
        head -c 4 > /dev/null

        #get other relevant info
        container_signatureblock=$(head -c $headersize | xxd -l $headersize -c $headersize -p)
        signature_offset=0x${container_signatureblock:2:2}${container_signatureblock:0:2}
        
        # print relevant info
        printf "Container offset: %x, Signature block offset: %x\n" $(($globaloffs - 0x4)) $(($globaloffs + $signature_offset - 0x4)) #0x4 abzug weil die ersten vier bytes zuvor bereits abgezogen waren

        # skip container to search for another
        remaining=$((remaining - $container_padded + 0x4))   
        savedextra=$((savedextra - $container_padded + 0x4)) 
        head -c $(($container_padded - 0xC - 0x4)) > /dev/null # 0xC wegen den 0xC eingelesenen Bytes seid aufruf

        # get next head to either try again or resume with normal operation
        head=$(head -c $headersize | xxd -l $headersize -c $headersize -p)
        remaining=$((remaining - $headersize))   
        savedextra=$((savedextra - $headersize))
        globaloffs=$((globaloffs + container_padded))
}

# Main part of the script

# Parse command line arguments
cmd=list
outfile=
while [ $# -gt 0 ]; do
    case $1 in
	-x|--xtract)
	    cmd=xtract
	    ;;
	-j|--just-header)
	    cmd=justheader
	    ;;
	-c|--crc32)
	    cmd=crc32
	    ;;
	-l|--list)
	    cmd=list
	    ;;
	-i|--info)
	    cmd=info
	    ;;
	-o|--output)
	    outfile=$2
	    shift
	    ;;
	-s|--show)
	    if [[ "$2" =~ ^p.+\[.+\]$ ]]; then
		cmd=showp
	    elif [[ " $fields " =~ .*\ $2\ .* ]]; then
		cmd=show
	    else
		usage "Invalid argument '$2' for option $1"
	    fi
	    show=$2
	    shift
	    ;;
	-h|--help)
	    usage
	    ;;
	--)
	    shift
	    break
	    ;;
	-*)
	    usage "Unknown option $1"
	    ;;
	*)
	    break
	    ;;
    esac
    shift
done

# Check if input is from a terminal (as opposed to a pipe or input redirection)
if [ -t 0 ]; then
    # Yes, we need a file name
    if [ $# -eq 0 ]; then
	usage "Missing file name"
    fi

    # Redirect input file as stdin
    exec < $1
    shift
fi

# If selection is not given, assume 0; if it is a number, set selnum to it
sel=0
if [ $# -gt 0 ]; then
    sel=${1:-0}
    shift
fi
if ! selnum=$(printf "%d" "$sel" 2> /dev/null); then
    selnum=-1
fi

if [ $# -gt 0 ]; then
    usage "Too many arguments"
fi

# If an output file is given, redirect stdout to it
if [ -n "$outfile" ]; then
    exec > $outfile
fi

# Start reading the image
globaloffs=0
if ! get_header_info 64; then
    echo "File has no valid F&S header" >&2
    exit 1;
fi

index=0

# Get output width for offset and size values, set a format for hex and string
width=$(printf "%08x" $size)
wx="%0${#width}x"
ws="%-${#width}s"

if [[ $cmd = "list" ]]; then
    printf " #  $ws $ws flags type (description)\n" offset size
fi

# Handle each of possibly several concatenated F&S images
while true; do
    if [[ $cmd = "list" ]]; then
	printf "%s\n" "-------------------------------------------------------------------------------"
    fi

    parse_image $size 0
    if ! get_header_info 64; then
	break;
    fi
done

if [ $cmd != "list" ]; then
    echo "Image '$sel' not found"
    exit 1
fi
