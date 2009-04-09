#!/usr/bin/env ocaml
(* libguestfs
 * Copyright (C) 2009 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *
 * This script generates a large amount of code and documentation for
 * all the daemon actions.  To add a new action there are only two
 * files you need to change, this one to describe the interface, and
 * daemon/<somefile>.c to write the implementation.
 *)

#load "unix.cma";;

open Printf

type style = ret * args
and ret =
    (* "Err" as a return value means an int used as a simple error
     * indication, ie. 0 or -1.
     *)
  | Err
    (* "Int" as a return value means an int which is -1 for error
     * or any value >= 0 on success.
     *)
  | RInt of string
    (* "RBool" is a bool return value which can be true/false or
     * -1 for error.
     *)
  | RBool of string
    (* "RConstString" is a string that refers to a constant value.
     * Try to avoid using this.  In particular you cannot use this
     * for values returned from the daemon, because there is no
     * thread-safe way to return them in the C API.
     *)
  | RConstString of string
    (* "RString" and "RStringList" are caller-frees. *)
  | RString of string
  | RStringList of string
    (* Some limited tuples are possible: *)
  | RIntBool of string * string
    (* LVM PVs, VGs and LVs. *)
  | RPVList of string
  | RVGList of string
  | RLVList of string
and args =
    (* 0 arguments, 1 argument, etc. The guestfs_h param is implicit. *)
  | P0
  | P1 of argt
  | P2 of argt * argt
  | P3 of argt * argt * argt
and argt =
  | String of string	(* const char *name, cannot be NULL *)
  | OptString of string	(* const char *name, may be NULL *)
  | Bool of string	(* boolean *)
  | Int of string	(* int (smallish ints, signed, <= 31 bits) *)

type flags =
  | ProtocolLimitWarning  (* display warning about protocol size limits *)
  | FishAlias of string	  (* provide an alias for this cmd in guestfish *)
  | FishAction of string  (* call this function in guestfish *)
  | NotInFish		  (* do not export via guestfish *)

(* Note about long descriptions: When referring to another
 * action, use the format C<guestfs_other> (ie. the full name of
 * the C function).  This will be replaced as appropriate in other
 * language bindings.
 *
 * Apart from that, long descriptions are just perldoc paragraphs.
 *)

let non_daemon_functions = [
  ("launch", (Err, P0), -1, [FishAlias "run"; FishAction "launch"],
   "launch the qemu subprocess",
   "\
Internally libguestfs is implemented by running a virtual machine
using L<qemu(1)>.

You should call this after configuring the handle
(eg. adding drives) but before performing any actions.");

  ("wait_ready", (Err, P0), -1, [NotInFish],
   "wait until the qemu subprocess launches",
   "\
Internally libguestfs is implemented by running a virtual machine
using L<qemu(1)>.

You should call this after C<guestfs_launch> to wait for the launch
to complete.");

  ("kill_subprocess", (Err, P0), -1, [],
   "kill the qemu subprocess",
   "\
This kills the qemu subprocess.  You should never need to call this.");

  ("add_drive", (Err, P1 (String "filename")), -1, [FishAlias "add"],
   "add an image to examine or modify",
   "\
This function adds a virtual machine disk image C<filename> to the
guest.  The first time you call this function, the disk appears as IDE
disk 0 (C</dev/sda>) in the guest, the second time as C</dev/sdb>, and
so on.

You don't necessarily need to be root when using libguestfs.  However
you obviously do need sufficient permissions to access the filename
for whatever operations you want to perform (ie. read access if you
just want to read the image or write access if you want to modify the
image).

This is equivalent to the qemu parameter C<-drive file=filename>.");

  ("add_cdrom", (Err, P1 (String "filename")), -1, [FishAlias "cdrom"],
   "add a CD-ROM disk image to examine",
   "\
This function adds a virtual CD-ROM disk image to the guest.

This is equivalent to the qemu parameter C<-cdrom filename>.");

  ("config", (Err, P2 (String "qemuparam", OptString "qemuvalue")), -1, [],
   "add qemu parameters",
   "\
This can be used to add arbitrary qemu command line parameters
of the form C<-param value>.  Actually it's not quite arbitrary - we
prevent you from setting some parameters which would interfere with
parameters that we use.

The first character of C<param> string must be a C<-> (dash).

C<value> can be NULL.");

  ("set_path", (Err, P1 (String "path")), -1, [FishAlias "path"],
   "set the search path",
   "\
Set the path that libguestfs searches for kernel and initrd.img.

The default is C<$libdir/guestfs> unless overridden by setting
C<LIBGUESTFS_PATH> environment variable.

The string C<path> is stashed in the libguestfs handle, so the caller
must make sure it remains valid for the lifetime of the handle.

Setting C<path> to C<NULL> restores the default path.");

  ("get_path", (RConstString "path", P0), -1, [],
   "get the search path",
   "\
Return the current search path.

This is always non-NULL.  If it wasn't set already, then this will
return the default path.");

  ("set_autosync", (Err, P1 (Bool "autosync")), -1, [FishAlias "autosync"],
   "set autosync mode",
   "\
If C<autosync> is true, this enables autosync.  Libguestfs will make a
best effort attempt to run C<guestfs_sync> when the handle is closed
(also if the program exits without closing handles).");

  ("get_autosync", (RBool "autosync", P0), -1, [],
   "get autosync mode",
   "\
Get the autosync flag.");

  ("set_verbose", (Err, P1 (Bool "verbose")), -1, [FishAlias "verbose"],
   "set verbose mode",
   "\
If C<verbose> is true, this turns on verbose messages (to C<stderr>).

Verbose messages are disabled unless the environment variable
C<LIBGUESTFS_DEBUG> is defined and set to C<1>.");

  ("get_verbose", (RBool "verbose", P0), -1, [],
   "get verbose mode",
   "\
This returns the verbose messages flag.")
]

let daemon_functions = [
  ("mount", (Err, P2 (String "device", String "mountpoint")), 1, [],
   "mount a guest disk at a position in the filesystem",
   "\
Mount a guest disk at a position in the filesystem.  Block devices
are named C</dev/sda>, C</dev/sdb> and so on, as they were added to
the guest.  If those block devices contain partitions, they will have
the usual names (eg. C</dev/sda1>).  Also LVM C</dev/VG/LV>-style
names can be used.

The rules are the same as for L<mount(2)>:  A filesystem must
first be mounted on C</> before others can be mounted.  Other
filesystems can only be mounted on directories which already
exist.

The mounted filesystem is writable, if we have sufficient permissions
on the underlying device.

The filesystem options C<sync> and C<noatime> are set with this
call, in order to improve reliability.");

  ("sync", (Err, P0), 2, [],
   "sync disks, writes are flushed through to the disk image",
   "\
This syncs the disk, so that any writes are flushed through to the
underlying disk image.

You should always call this if you have modified a disk image, before
closing the handle.");

  ("touch", (Err, P1 (String "path")), 3, [],
   "update file timestamps or create a new file",
   "\
Touch acts like the L<touch(1)> command.  It can be used to
update the timestamps on a file, or, if the file does not exist,
to create a new zero-length file.");

  ("cat", (RString "content", P1 (String "path")), 4, [ProtocolLimitWarning],
   "list the contents of a file",
   "\
Return the contents of the file named C<path>.

Note that this function cannot correctly handle binary files
(specifically, files containing C<\\0> character which is treated
as end of string).  For those you need to use the C<guestfs_read_file>
function which has a more complex interface.");

  ("ll", (RString "listing", P1 (String "directory")), 5, [],
   "list the files in a directory (long format)",
   "\
List the files in C<directory> (relative to the root directory,
there is no cwd) in the format of 'ls -la'.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string.");

  ("ls", (RStringList "listing", P1 (String "directory")), 6, [],
   "list the files in a directory",
   "\
List the files in C<directory> (relative to the root directory,
there is no cwd).  The '.' and '..' entries are not returned, but
hidden files are shown.

This command is mostly useful for interactive sessions.  Programs
should probably use C<guestfs_readdir> instead.");

  ("list_devices", (RStringList "devices", P0), 7, [],
   "list the block devices",
   "\
List all the block devices.

The full block device names are returned, eg. C</dev/sda>");

  ("list_partitions", (RStringList "partitions", P0), 8, [],
   "list the partitions",
   "\
List all the partitions detected on all block devices.

The full partition device names are returned, eg. C</dev/sda1>

This does not return logical volumes.  For that you will need to
call C<guestfs_lvs>.");

  ("pvs", (RStringList "physvols", P0), 9, [],
   "list the LVM physical volumes (PVs)",
   "\
List all the physical volumes detected.  This is the equivalent
of the L<pvs(8)> command.

This returns a list of just the device names that contain
PVs (eg. C</dev/sda2>).

See also C<guestfs_pvs_full>.");

  ("vgs", (RStringList "volgroups", P0), 10, [],
   "list the LVM volume groups (VGs)",
   "\
List all the volumes groups detected.  This is the equivalent
of the L<vgs(8)> command.

This returns a list of just the volume group names that were
detected (eg. C<VolGroup00>).

See also C<guestfs_vgs_full>.");

  ("lvs", (RStringList "logvols", P0), 11, [],
   "list the LVM logical volumes (LVs)",
   "\
List all the logical volumes detected.  This is the equivalent
of the L<lvs(8)> command.

This returns a list of the logical volume device names
(eg. C</dev/VolGroup00/LogVol00>).

See also C<guestfs_lvs_full>.");

  ("pvs_full", (RPVList "physvols", P0), 12, [],
   "list the LVM physical volumes (PVs)",
   "\
List all the physical volumes detected.  This is the equivalent
of the L<pvs(8)> command.  The \"full\" version includes all fields.");

  ("vgs_full", (RVGList "volgroups", P0), 13, [],
   "list the LVM volume groups (VGs)",
   "\
List all the volumes groups detected.  This is the equivalent
of the L<vgs(8)> command.  The \"full\" version includes all fields.");

  ("lvs_full", (RLVList "logvols", P0), 14, [],
   "list the LVM logical volumes (LVs)",
   "\
List all the logical volumes detected.  This is the equivalent
of the L<lvs(8)> command.  The \"full\" version includes all fields.");

  ("read_lines", (RStringList "lines", P1 (String "path")), 15, [],
   "read file as lines",
   "\
Return the contents of the file named C<path>.

The file contents are returned as a list of lines.  Trailing
C<LF> and C<CRLF> character sequences are I<not> returned.

Note that this function cannot correctly handle binary files
(specifically, files containing C<\\0> character which is treated
as end of line).  For those you need to use the C<guestfs_read_file>
function which has a more complex interface.");

  ("aug_init", (Err, P2 (String "root", Int "flags")), 16, [],
   "create a new Augeas handle",
   "\
Create a new Augeas handle for editing configuration files.
If there was any previous Augeas handle associated with this
guestfs session, then it is closed.

You must call this before using any other C<guestfs_aug_*>
commands.

C<root> is the filesystem root.  C<root> must not be NULL,
use C</> instead.

The flags are the same as the flags defined in
E<lt>augeas.hE<gt>, the logical I<or> of the following
integers:

=over 4

=item C<AUG_SAVE_BACKUP> = 1

Keep the original file with a C<.augsave> extension.

=item C<AUG_SAVE_NEWFILE> = 2

Save changes into a file with extension C<.augnew>, and
do not overwrite original.  Overrides C<AUG_SAVE_BACKUP>.

=item C<AUG_TYPE_CHECK> = 4

Typecheck lenses (can be expensive).

=item C<AUG_NO_STDINC> = 8

Do not use standard load path for modules.

=item C<AUG_SAVE_NOOP> = 16

Make save a no-op, just record what would have been changed.

=item C<AUG_NO_LOAD> = 32

Do not load the tree in C<guestfs_aug_init>.

=back

To close the handle, you can call C<guestfs_aug_close>.

To find out more about Augeas, see L<http://augeas.net/>.");

  ("aug_close", (Err, P0), 26, [],
   "close the current Augeas handle",
   "\
Close the current Augeas handle and free up any resources
used by it.  After calling this, you have to call
C<guestfs_aug_init> again before you can use any other
Augeas functions.");

  ("aug_defvar", (RInt "nrnodes", P2 (String "name", OptString "expr")), 17, [],
   "define an Augeas variable",
   "\
Defines an Augeas variable C<name> whose value is the result
of evaluating C<expr>.  If C<expr> is NULL, then C<name> is
undefined.

On success this returns the number of nodes in C<expr>, or
C<0> if C<expr> evaluates to something which is not a nodeset.");

  ("aug_defnode", (RIntBool ("nrnodes", "created"), P3 (String "name", String "expr", String "val")), 18, [],
   "define an Augeas node",
   "\
Defines a variable C<name> whose value is the result of
evaluating C<expr>.

If C<expr> evaluates to an empty nodeset, a node is created,
equivalent to calling C<guestfs_aug_set> C<expr>, C<value>.
C<name> will be the nodeset containing that single node.

On success this returns a pair containing the
number of nodes in the nodeset, and a boolean flag
if a node was created.");

  ("aug_get", (RString "val", P1 (String "path")), 19, [],
   "look up the value of an Augeas path",
   "\
Look up the value associated with C<path>.  If C<path>
matches exactly one node, the C<value> is returned.");

  ("aug_set", (Err, P2 (String "path", String "val")), 20, [],
   "set Augeas path to value",
   "\
Set the value associated with C<path> to C<value>.");

  ("aug_insert", (Err, P3 (String "path", String "label", Bool "before")), 21, [],
   "insert a sibling Augeas node",
   "\
Create a new sibling C<label> for C<path>, inserting it into
the tree before or after C<path> (depending on the boolean
flag C<before>).

C<path> must match exactly one existing node in the tree, and
C<label> must be a label, ie. not contain C</>, C<*> or end
with a bracketed index C<[N]>.");

  ("aug_rm", (RInt "nrnodes", P1 (String "path")), 22, [],
   "remove an Augeas path",
   "\
Remove C<path> and all of its children.

On success this returns the number of entries which were removed.");

  ("aug_mv", (Err, P2 (String "src", String "dest")), 23, [],
   "move Augeas node",
   "\
Move the node C<src> to C<dest>.  C<src> must match exactly
one node.  C<dest> is overwritten if it exists.");

  ("aug_match", (RStringList "matches", P1 (String "path")), 24, [],
   "return Augeas nodes which match path",
   "\
Returns a list of paths which match the path expression C<path>.
The returned paths are sufficiently qualified so that they match
exactly one node in the current tree.");

  ("aug_save", (Err, P0), 25, [],
   "write all pending Augeas changes to disk",
   "\
This writes all pending changes to disk.

The flags which were passed to C<guestfs_aug_init> affect exactly
how files are saved.");

  ("aug_load", (Err, P0), 27, [],
   "load files into the tree",
   "\
Load files into the tree.

See C<aug_load> in the Augeas documentation for the full gory
details.");

  ("aug_ls", (RStringList "matches", P1 (String "path")), 28, [],
   "list Augeas nodes under a path",
   "\
This is just a shortcut for listing C<guestfs_aug_match>
C<path/*> and sorting the files into alphabetical order.");
]

let all_functions = non_daemon_functions @ daemon_functions

(* In some places we want the functions to be displayed sorted
 * alphabetically, so this is useful:
 *)
let all_functions_sorted =
  List.sort (fun (n1,_,_,_,_,_) (n2,_,_,_,_,_) -> compare n1 n2) all_functions

(* Column names and types from LVM PVs/VGs/LVs. *)
let pv_cols = [
  "pv_name", `String;
  "pv_uuid", `UUID;
  "pv_fmt", `String;
  "pv_size", `Bytes;
  "dev_size", `Bytes;
  "pv_free", `Bytes;
  "pv_used", `Bytes;
  "pv_attr", `String (* XXX *);
  "pv_pe_count", `Int;
  "pv_pe_alloc_count", `Int;
  "pv_tags", `String;
  "pe_start", `Bytes;
  "pv_mda_count", `Int;
  "pv_mda_free", `Bytes;
(* Not in Fedora 10:
  "pv_mda_size", `Bytes;
*)
]
let vg_cols = [
  "vg_name", `String;
  "vg_uuid", `UUID;
  "vg_fmt", `String;
  "vg_attr", `String (* XXX *);
  "vg_size", `Bytes;
  "vg_free", `Bytes;
  "vg_sysid", `String;
  "vg_extent_size", `Bytes;
  "vg_extent_count", `Int;
  "vg_free_count", `Int;
  "max_lv", `Int;
  "max_pv", `Int;
  "pv_count", `Int;
  "lv_count", `Int;
  "snap_count", `Int;
  "vg_seqno", `Int;
  "vg_tags", `String;
  "vg_mda_count", `Int;
  "vg_mda_free", `Bytes;
(* Not in Fedora 10:
  "vg_mda_size", `Bytes;
*)
]
let lv_cols = [
  "lv_name", `String;
  "lv_uuid", `UUID;
  "lv_attr", `String (* XXX *);
  "lv_major", `Int;
  "lv_minor", `Int;
  "lv_kernel_major", `Int;
  "lv_kernel_minor", `Int;
  "lv_size", `Bytes;
  "seg_count", `Int;
  "origin", `String;
  "snap_percent", `OptPercent;
  "copy_percent", `OptPercent;
  "move_pv", `String;
  "lv_tags", `String;
  "mirror_log", `String;
  "modules", `String;
]

(* Useful functions.
 * Note we don't want to use any external OCaml libraries which
 * makes this a bit harder than it should be.
 *)
let failwithf fs = ksprintf failwith fs

let replace_char s c1 c2 =
  let s2 = String.copy s in
  let r = ref false in
  for i = 0 to String.length s2 - 1 do
    if String.unsafe_get s2 i = c1 then (
      String.unsafe_set s2 i c2;
      r := true
    )
  done;
  if not !r then s else s2

let rec find s sub =
  let len = String.length s in
  let sublen = String.length sub in
  let rec loop i =
    if i <= len-sublen then (
      let rec loop2 j =
	if j < sublen then (
	  if s.[i+j] = sub.[j] then loop2 (j+1)
	  else -1
	) else
	  i (* found *)
      in
      let r = loop2 0 in
      if r = -1 then loop (i+1) else r
    ) else
      -1 (* not found *)
  in
  loop 0

let rec replace_str s s1 s2 =
  let len = String.length s in
  let sublen = String.length s1 in
  let i = find s s1 in
  if i = -1 then s
  else (
    let s' = String.sub s 0 i in
    let s'' = String.sub s (i+sublen) (len-i-sublen) in
    s' ^ s2 ^ replace_str s'' s1 s2
  )

let rec find_map f = function
  | [] -> raise Not_found
  | x :: xs ->
      match f x with
      | Some y -> y
      | None -> find_map f xs

let iteri f xs =
  let rec loop i = function
    | [] -> ()
    | x :: xs -> f i x; loop (i+1) xs
  in
  loop 0 xs

(* 'pr' prints to the current output file. *)
let chan = ref stdout
let pr fs = ksprintf (output_string !chan) fs

let iter_args f = function
  | P0 -> ()
  | P1 arg1 -> f arg1
  | P2 (arg1, arg2) -> f arg1; f arg2
  | P3 (arg1, arg2, arg3) -> f arg1; f arg2; f arg3

let iteri_args f = function
  | P0 -> ()
  | P1 arg1 -> f 0 arg1
  | P2 (arg1, arg2) -> f 0 arg1; f 1 arg2
  | P3 (arg1, arg2, arg3) -> f 0 arg1; f 1 arg2; f 2 arg3

let map_args f = function
  | P0 -> []
  | P1 arg1 -> [f arg1]
  | P2 (arg1, arg2) ->
      let n1 = f arg1 in let n2 = f arg2 in [n1; n2]
  | P3 (arg1, arg2, arg3) ->
      let n1 = f arg1 in let n2 = f arg2 in let n3 = f arg3 in [n1; n2; n3]

let nr_args = function | P0 -> 0 | P1 _ -> 1 | P2 _ -> 2 | P3 _ -> 3

let name_of_argt = function String n | OptString n | Bool n | Int n -> n

(* Check function names etc. for consistency. *)
let check_functions () =
  List.iter (
    fun (name, _, _, _, _, longdesc) ->
      if String.contains name '-' then
	failwithf "function name '%s' should not contain '-', use '_' instead."
	  name;
      if longdesc.[String.length longdesc-1] = '\n' then
	failwithf "long description of %s should not end with \\n." name
  ) all_functions;

  List.iter (
    fun (name, _, proc_nr, _, _, _) ->
      if proc_nr <= 0 then
	failwithf "daemon function %s should have proc_nr > 0" name
  ) daemon_functions;

  List.iter (
    fun (name, _, proc_nr, _, _, _) ->
      if proc_nr <> -1 then
	failwithf "non-daemon function %s should have proc_nr -1" name
  ) non_daemon_functions;

  let proc_nrs =
    List.map (fun (name, _, proc_nr, _, _, _) -> name, proc_nr)
      daemon_functions in
  let proc_nrs =
    List.sort (fun (_,nr1) (_,nr2) -> compare nr1 nr2) proc_nrs in
  let rec loop = function
    | [] -> ()
    | [_] -> ()
    | (name1,nr1) :: ((name2,nr2) :: _ as rest) when nr1 < nr2 ->
	loop rest
    | (name1,nr1) :: (name2,nr2) :: _ ->
	failwithf "'%s' and '%s' have conflicting procedure numbers (%d, %d)"
	  name1 name2 nr1 nr2
  in
  loop proc_nrs

type comment_style = CStyle | HashStyle | OCamlStyle
type license = GPLv2 | LGPLv2

(* Generate a header block in a number of standard styles. *)
let rec generate_header comment license =
  let c = match comment with
    | CStyle ->     pr "/* "; " *"
    | HashStyle ->  pr "# ";  "#"
    | OCamlStyle -> pr "(* "; " *" in
  pr "libguestfs generated file\n";
  pr "%s WARNING: THIS FILE IS GENERATED BY 'src/generator.ml'.\n" c;
  pr "%s ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.\n" c;
  pr "%s\n" c;
  pr "%s Copyright (C) 2009 Red Hat Inc.\n" c;
  pr "%s\n" c;
  (match license with
   | GPLv2 ->
       pr "%s This program is free software; you can redistribute it and/or modify\n" c;
       pr "%s it under the terms of the GNU General Public License as published by\n" c;
       pr "%s the Free Software Foundation; either version 2 of the License, or\n" c;
       pr "%s (at your option) any later version.\n" c;
       pr "%s\n" c;
       pr "%s This program is distributed in the hope that it will be useful,\n" c;
       pr "%s but WITHOUT ANY WARRANTY; without even the implied warranty of\n" c;
       pr "%s MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\n" c;
       pr "%s GNU General Public License for more details.\n" c;
       pr "%s\n" c;
       pr "%s You should have received a copy of the GNU General Public License along\n" c;
       pr "%s with this program; if not, write to the Free Software Foundation, Inc.,\n" c;
       pr "%s 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.\n" c;

   | LGPLv2 ->
       pr "%s This library is free software; you can redistribute it and/or\n" c;
       pr "%s modify it under the terms of the GNU Lesser General Public\n" c;
       pr "%s License as published by the Free Software Foundation; either\n" c;
       pr "%s version 2 of the License, or (at your option) any later version.\n" c;
       pr "%s\n" c;
       pr "%s This library is distributed in the hope that it will be useful,\n" c;
       pr "%s but WITHOUT ANY WARRANTY; without even the implied warranty of\n" c;
       pr "%s MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU\n" c;
       pr "%s Lesser General Public License for more details.\n" c;
       pr "%s\n" c;
       pr "%s You should have received a copy of the GNU Lesser General Public\n" c;
       pr "%s License along with this library; if not, write to the Free Software\n" c;
       pr "%s Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA\n" c;
  );
  (match comment with
   | CStyle -> pr " */\n"
   | HashStyle -> ()
   | OCamlStyle -> pr " *)\n"
  );
  pr "\n"

(* Generate the pod documentation for the C API. *)
and generate_actions_pod () =
  List.iter (
    fun (shortname, style, _, flags, _, longdesc) ->
      let name = "guestfs_" ^ shortname in
      pr "=head2 %s\n\n" name;
      pr " ";
      generate_prototype ~extern:false ~handle:"handle" name style;
      pr "\n\n";
      pr "%s\n\n" longdesc;
      (match fst style with
       | Err ->
	   pr "This function returns 0 on success or -1 on error.\n\n"
       | RInt _ ->
	   pr "On error this function returns -1.\n\n"
       | RBool _ ->
	   pr "This function returns a C truth value on success or -1 on error.\n\n"
       | RConstString _ ->
	   pr "This function returns a string or NULL on error.
The string is owned by the guest handle and must I<not> be freed.\n\n"
       | RString _ ->
	   pr "This function returns a string or NULL on error.
I<The caller must free the returned string after use>.\n\n"
       | RStringList _ ->
	   pr "This function returns a NULL-terminated array of strings
(like L<environ(3)>), or NULL if there was an error.
I<The caller must free the strings and the array after use>.\n\n"
       | RIntBool _ ->
	   pr "This function returns a C<struct guestfs_int_bool *>.
I<The caller must call C<guestfs_free_int_bool> after use.>.\n\n"
       | RPVList _ ->
	   pr "This function returns a C<struct guestfs_lvm_pv_list *>.
I<The caller must call C<guestfs_free_lvm_pv_list> after use.>.\n\n"
       | RVGList _ ->
	   pr "This function returns a C<struct guestfs_lvm_vg_list *>.
I<The caller must call C<guestfs_free_lvm_vg_list> after use.>.\n\n"
       | RLVList _ ->
	   pr "This function returns a C<struct guestfs_lvm_lv_list *>.
I<The caller must call C<guestfs_free_lvm_lv_list> after use.>.\n\n"
      );
      if List.mem ProtocolLimitWarning flags then
	pr "Because of the message protocol, there is a transfer limit 
of somewhere between 2MB and 4MB.  To transfer large files you should use
FTP.\n\n";
  ) all_functions_sorted

and generate_structs_pod () =
  (* LVM structs documentation. *)
  List.iter (
    fun (typ, cols) ->
      pr "=head2 guestfs_lvm_%s\n" typ;
      pr "\n";
      pr " struct guestfs_lvm_%s {\n" typ;
      List.iter (
	function
	| name, `String -> pr "  char *%s;\n" name
	| name, `UUID ->
	    pr "  /* The next field is NOT nul-terminated, be careful when printing it: */\n";
	    pr "  char %s[32];\n" name
	| name, `Bytes -> pr "  uint64_t %s;\n" name
	| name, `Int -> pr "  int64_t %s;\n" name
	| name, `OptPercent ->
	    pr "  /* The next field is [0..100] or -1 meaning 'not present': */\n";
	    pr "  float %s;\n" name
      ) cols;
      pr " \n";
      pr " struct guestfs_lvm_%s_list {\n" typ;
      pr "   uint32_t len; /* Number of elements in list. */\n";
      pr "   struct guestfs_lvm_%s *val; /* Elements. */\n" typ;
      pr " };\n";
      pr " \n";
      pr " void guestfs_free_lvm_%s_list (struct guestfs_free_lvm_%s_list *);\n"
	typ typ;
      pr "\n"
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols]

(* Generate the protocol (XDR) file, 'guestfs_protocol.x' and
 * indirectly 'guestfs_protocol.h' and 'guestfs_protocol.c'.  We
 * have to use an underscore instead of a dash because otherwise
 * rpcgen generates incorrect code.
 *
 * This header is NOT exported to clients, but see also generate_structs_h.
 *)
and generate_xdr () =
  generate_header CStyle LGPLv2;

  (* This has to be defined to get around a limitation in Sun's rpcgen. *)
  pr "typedef string str<>;\n";
  pr "\n";

  (* LVM internal structures. *)
  List.iter (
    function
    | typ, cols ->
	pr "struct guestfs_lvm_int_%s {\n" typ;
	List.iter (function
		   | name, `String -> pr "  string %s<>;\n" name
		   | name, `UUID -> pr "  opaque %s[32];\n" name
		   | name, `Bytes -> pr "  hyper %s;\n" name
		   | name, `Int -> pr "  hyper %s;\n" name
		   | name, `OptPercent -> pr "  float %s;\n" name
		  ) cols;
	pr "};\n";
	pr "\n";
	pr "typedef struct guestfs_lvm_int_%s guestfs_lvm_int_%s_list<>;\n" typ typ;
	pr "\n";
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols];

  List.iter (
    fun(shortname, style, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in

      (match snd style with
       | P0 -> ()
       | args ->
	   pr "struct %s_args {\n" name;
	   iter_args (
	     function
	     | String n -> pr "  string %s<>;\n" n
	     | OptString n -> pr "  str *%s;\n" n
	     | Bool n -> pr "  bool %s;\n" n
	     | Int n -> pr "  int %s;\n" n
	   ) args;
	   pr "};\n\n"
      );
      (match fst style with
       | Err -> ()
       | RInt n ->
	   pr "struct %s_ret {\n" name;
	   pr "  int %s;\n" n;
	   pr "};\n\n"
       | RBool n ->
	   pr "struct %s_ret {\n" name;
	   pr "  bool %s;\n" n;
	   pr "};\n\n"
       | RConstString _ ->
	   failwithf "RConstString cannot be returned from a daemon function"
       | RString n ->
	   pr "struct %s_ret {\n" name;
	   pr "  string %s<>;\n" n;
	   pr "};\n\n"
       | RStringList n ->
	   pr "struct %s_ret {\n" name;
	   pr "  str %s<>;\n" n;
	   pr "};\n\n"
       | RIntBool (n,m) ->
	   pr "struct %s_ret {\n" name;
	   pr "  int %s;\n" n;
	   pr "  bool %s;\n" m;
	   pr "};\n\n"
       | RPVList n ->
	   pr "struct %s_ret {\n" name;
	   pr "  guestfs_lvm_int_pv_list %s;\n" n;
	   pr "};\n\n"
       | RVGList n ->
	   pr "struct %s_ret {\n" name;
	   pr "  guestfs_lvm_int_vg_list %s;\n" n;
	   pr "};\n\n"
       | RLVList n ->
	   pr "struct %s_ret {\n" name;
	   pr "  guestfs_lvm_int_lv_list %s;\n" n;
	   pr "};\n\n"
      );
  ) daemon_functions;

  (* Table of procedure numbers. *)
  pr "enum guestfs_procedure {\n";
  List.iter (
    fun (shortname, _, proc_nr, _, _, _) ->
      pr "  GUESTFS_PROC_%s = %d,\n" (String.uppercase shortname) proc_nr
  ) daemon_functions;
  pr "  GUESTFS_PROC_dummy\n"; (* so we don't have a "hanging comma" *)
  pr "};\n";
  pr "\n";

  (* Having to choose a maximum message size is annoying for several
   * reasons (it limits what we can do in the API), but it (a) makes
   * the protocol a lot simpler, and (b) provides a bound on the size
   * of the daemon which operates in limited memory space.  For large
   * file transfers you should use FTP.
   *)
  pr "const GUESTFS_MESSAGE_MAX = %d;\n" (4 * 1024 * 1024);
  pr "\n";

  (* Message header, etc. *)
  pr "\
const GUESTFS_PROGRAM = 0x2000F5F5;
const GUESTFS_PROTOCOL_VERSION = 1;

enum guestfs_message_direction {
  GUESTFS_DIRECTION_CALL = 0,        /* client -> daemon */
  GUESTFS_DIRECTION_REPLY = 1        /* daemon -> client */
};

enum guestfs_message_status {
  GUESTFS_STATUS_OK = 0,
  GUESTFS_STATUS_ERROR = 1
};

const GUESTFS_ERROR_LEN = 256;

struct guestfs_message_error {
  string error<GUESTFS_ERROR_LEN>;   /* error message */
};

struct guestfs_message_header {
  unsigned prog;                     /* GUESTFS_PROGRAM */
  unsigned vers;                     /* GUESTFS_PROTOCOL_VERSION */
  guestfs_procedure proc;            /* GUESTFS_PROC_x */
  guestfs_message_direction direction;
  unsigned serial;                   /* message serial number */
  guestfs_message_status status;
};
"

(* Generate the guestfs-structs.h file. *)
and generate_structs_h () =
  generate_header CStyle LGPLv2;

  (* This is a public exported header file containing various
   * structures.  The structures are carefully written to have
   * exactly the same in-memory format as the XDR structures that
   * we use on the wire to the daemon.  The reason for creating
   * copies of these structures here is just so we don't have to
   * export the whole of guestfs_protocol.h (which includes much
   * unrelated and XDR-dependent stuff that we don't want to be
   * public, or required by clients).
   *
   * To reiterate, we will pass these structures to and from the
   * client with a simple assignment or memcpy, so the format
   * must be identical to what rpcgen / the RFC defines.
   *)

  (* guestfs_int_bool structure. *)
  pr "struct guestfs_int_bool {\n";
  pr "  int32_t i;\n";
  pr "  int32_t b;\n";
  pr "};\n";
  pr "\n";

  (* LVM public structures. *)
  List.iter (
    function
    | typ, cols ->
	pr "struct guestfs_lvm_%s {\n" typ;
	List.iter (
	  function
	  | name, `String -> pr "  char *%s;\n" name
	  | name, `UUID -> pr "  char %s[32]; /* this is NOT nul-terminated, be careful when printing */\n" name
	  | name, `Bytes -> pr "  uint64_t %s;\n" name
	  | name, `Int -> pr "  int64_t %s;\n" name
	  | name, `OptPercent -> pr "  float %s; /* [0..100] or -1 */\n" name
	) cols;
	pr "};\n";
	pr "\n";
	pr "struct guestfs_lvm_%s_list {\n" typ;
	pr "  uint32_t len;\n";
	pr "  struct guestfs_lvm_%s *val;\n" typ;
	pr "};\n";
	pr "\n"
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols]

(* Generate the guestfs-actions.h file. *)
and generate_actions_h () =
  generate_header CStyle LGPLv2;
  List.iter (
    fun (shortname, style, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in
      generate_prototype ~single_line:true ~newline:true ~handle:"handle"
	name style
  ) all_functions

(* Generate the client-side dispatch stubs. *)
and generate_client_actions () =
  generate_header CStyle LGPLv2;

  (* Client-side stubs for each function. *)
  List.iter (
    fun (shortname, style, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in

      (* Generate the return value struct. *)
      pr "struct %s_rv {\n" shortname;
      pr "  int cb_done;  /* flag to indicate callback was called */\n";
      pr "  struct guestfs_message_header hdr;\n";
      pr "  struct guestfs_message_error err;\n";
      (match fst style with
       | Err -> ()
       | RConstString _ ->
	   failwithf "RConstString cannot be returned from a daemon function"
       | RInt _
       | RBool _ | RString _ | RStringList _
       | RIntBool _
       | RPVList _ | RVGList _ | RLVList _ ->
	   pr "  struct %s_ret ret;\n" name
      );
      pr "};\n\n";

      (* Generate the callback function. *)
      pr "static void %s_cb (guestfs_h *g, void *data, XDR *xdr)\n" shortname;
      pr "{\n";
      pr "  struct %s_rv *rv = (struct %s_rv *) data;\n" shortname shortname;
      pr "\n";
      pr "  if (!xdr_guestfs_message_header (xdr, &rv->hdr)) {\n";
      pr "    error (g, \"%s: failed to parse reply header\");\n" name;
      pr "    return;\n";
      pr "  }\n";
      pr "  if (rv->hdr.status == GUESTFS_STATUS_ERROR) {\n";
      pr "    if (!xdr_guestfs_message_error (xdr, &rv->err)) {\n";
      pr "      error (g, \"%s: failed to parse reply error\");\n" name;
      pr "      return;\n";
      pr "    }\n";
      pr "    goto done;\n";
      pr "  }\n";

      (match fst style with
       | Err -> ()
       | RConstString _ ->
	   failwithf "RConstString cannot be returned from a daemon function"
       | RInt _
       | RBool _ | RString _ | RStringList _
       | RIntBool _
       | RPVList _ | RVGList _ | RLVList _ ->
	    pr "  if (!xdr_%s_ret (xdr, &rv->ret)) {\n" name;
	    pr "    error (g, \"%s: failed to parse reply\");\n" name;
	    pr "    return;\n";
	    pr "  }\n";
      );

      pr " done:\n";
      pr "  rv->cb_done = 1;\n";
      pr "  main_loop.main_loop_quit (g);\n";
      pr "}\n\n";

      (* Generate the action stub. *)
      generate_prototype ~extern:false ~semicolon:false ~newline:true
	~handle:"g" name style;

      let error_code =
	match fst style with
	| Err | RInt _ | RBool _ -> "-1"
	| RConstString _ ->
	    failwithf "RConstString cannot be returned from a daemon function"
	| RString _ | RStringList _ | RIntBool _
	| RPVList _ | RVGList _ | RLVList _ ->
	    "NULL" in

      pr "{\n";

      (match snd style with
       | P0 -> ()
       | _ -> pr "  struct %s_args args;\n" name
      );

      pr "  struct %s_rv rv;\n" shortname;
      pr "  int serial;\n";
      pr "\n";
      pr "  if (g->state != READY) {\n";
      pr "    error (g, \"%s called from the wrong state, %%d != READY\",\n"
	name;
      pr "      g->state);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";
      pr "  memset (&rv, 0, sizeof rv);\n";
      pr "\n";

      (match snd style with
       | P0 ->
	   pr "  serial = dispatch (g, GUESTFS_PROC_%s, NULL, NULL);\n"
	     (String.uppercase shortname)
       | args ->
	   iter_args (
	     function
	     | String n ->
		 pr "  args.%s = (char *) %s;\n" n n
	     | OptString n ->
		 pr "  args.%s = %s ? (char **) &%s : NULL;\n" n n n
	     | Bool n ->
		 pr "  args.%s = %s;\n" n n
	     | Int n ->
		 pr "  args.%s = %s;\n" n n
	   ) args;
	   pr "  serial = dispatch (g, GUESTFS_PROC_%s,\n"
	     (String.uppercase shortname);
	   pr "                     (xdrproc_t) xdr_%s_args, (char *) &args);\n"
	     name;
      );
      pr "  if (serial == -1)\n";
      pr "    return %s;\n" error_code;
      pr "\n";

      pr "  rv.cb_done = 0;\n";
      pr "  g->reply_cb_internal = %s_cb;\n" shortname;
      pr "  g->reply_cb_internal_data = &rv;\n";
      pr "  main_loop.main_loop_run (g);\n";
      pr "  g->reply_cb_internal = NULL;\n";
      pr "  g->reply_cb_internal_data = NULL;\n";
      pr "  if (!rv.cb_done) {\n";
      pr "    error (g, \"%s failed, see earlier error messages\");\n" name;
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      pr "  if (check_reply_header (g, &rv.hdr, GUESTFS_PROC_%s, serial) == -1)\n"
	(String.uppercase shortname);
      pr "    return %s;\n" error_code;
      pr "\n";

      pr "  if (rv.hdr.status == GUESTFS_STATUS_ERROR) {\n";
      pr "    error (g, \"%%s\", rv.err.error);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      (match fst style with
       | Err -> pr "  return 0;\n"
       | RInt n
       | RBool n -> pr "  return rv.ret.%s;\n" n
       | RConstString _ ->
	   failwithf "RConstString cannot be returned from a daemon function"
       | RString n ->
	   pr "  return rv.ret.%s; /* caller will free */\n" n
       | RStringList n ->
	   pr "  /* caller will free this, but we need to add a NULL entry */\n";
	   pr "  rv.ret.%s.%s_val =" n n;
	   pr "    safe_realloc (g, rv.ret.%s.%s_val,\n" n n;
	   pr "                  sizeof (char *) * (rv.ret.%s.%s_len + 1));\n"
	     n n;
	   pr "  rv.ret.%s.%s_val[rv.ret.%s.%s_len] = NULL;\n" n n n n;
	   pr "  return rv.ret.%s.%s_val;\n" n n
       | RIntBool _ ->
	   pr "  /* caller with free this */\n";
	   pr "  return safe_memdup (g, &rv.ret, sizeof (rv.ret));\n"
       | RPVList n ->
	   pr "  /* caller will free this */\n";
	   pr "  return safe_memdup (g, &rv.ret.%s, sizeof (rv.ret.%s));\n" n n
       | RVGList n ->
	   pr "  /* caller will free this */\n";
	   pr "  return safe_memdup (g, &rv.ret.%s, sizeof (rv.ret.%s));\n" n n
       | RLVList n ->
	   pr "  /* caller will free this */\n";
	   pr "  return safe_memdup (g, &rv.ret.%s, sizeof (rv.ret.%s));\n" n n
      );

      pr "}\n\n"
  ) daemon_functions

(* Generate daemon/actions.h. *)
and generate_daemon_actions_h () =
  generate_header CStyle GPLv2;

  pr "#include \"../src/guestfs_protocol.h\"\n";
  pr "\n";

  List.iter (
    fun (name, style, _, _, _, _) ->
	generate_prototype
	  ~single_line:true ~newline:true ~in_daemon:true ~prefix:"do_"
	  name style;
  ) daemon_functions

(* Generate the server-side stubs. *)
and generate_daemon_actions () =
  generate_header CStyle GPLv2;

  pr "#define _GNU_SOURCE // for strchrnul\n";
  pr "\n";
  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "#include <inttypes.h>\n";
  pr "#include <ctype.h>\n";
  pr "#include <rpc/types.h>\n";
  pr "#include <rpc/xdr.h>\n";
  pr "\n";
  pr "#include \"daemon.h\"\n";
  pr "#include \"../src/guestfs_protocol.h\"\n";
  pr "#include \"actions.h\"\n";
  pr "\n";

  List.iter (
    fun (name, style, _, _, _, _) ->
      (* Generate server-side stubs. *)
      pr "static void %s_stub (XDR *xdr_in)\n" name;
      pr "{\n";
      let error_code =
	match fst style with
	| Err | RInt _ -> pr "  int r;\n"; "-1"
	| RBool _ -> pr "  int r;\n"; "-1"
	| RConstString _ ->
	    failwithf "RConstString cannot be returned from a daemon function"
	| RString _ -> pr "  char *r;\n"; "NULL"
	| RStringList _ -> pr "  char **r;\n"; "NULL"
	| RIntBool _ -> pr "  guestfs_%s_ret *r;\n" name; "NULL"
	| RPVList _ -> pr "  guestfs_lvm_int_pv_list *r;\n"; "NULL"
	| RVGList _ -> pr "  guestfs_lvm_int_vg_list *r;\n"; "NULL"
	| RLVList _ -> pr "  guestfs_lvm_int_lv_list *r;\n"; "NULL" in

      (match snd style with
       | P0 -> ()
       | args ->
	   pr "  struct guestfs_%s_args args;\n" name;
	   iter_args (
	     function
	     | String n
	     | OptString n -> pr "  const char *%s;\n" n
	     | Bool n -> pr "  int %s;\n" n
	     | Int n -> pr "  int %s;\n" n
	   ) args
      );
      pr "\n";

      (match snd style with
       | P0 -> ()
       | args ->
	   pr "  memset (&args, 0, sizeof args);\n";
	   pr "\n";
	   pr "  if (!xdr_guestfs_%s_args (xdr_in, &args)) {\n" name;
	   pr "    reply_with_error (\"%%s: daemon failed to decode procedure arguments\", \"%s\");\n" name;
	   pr "    return;\n";
	   pr "  }\n";
	   iter_args (
	     function
	     | String n -> pr "  %s = args.%s;\n" n n
	     | OptString n -> pr "  %s = args.%s ? *args.%s : NULL;\n" n n n
	     | Bool n -> pr "  %s = args.%s;\n" n n
	     | Int n -> pr "  %s = args.%s;\n" n n
	   ) args;
	   pr "\n"
      );

      pr "  r = do_%s " name;
      generate_call_args style;
      pr ";\n";

      pr "  if (r == %s)\n" error_code;
      pr "    /* do_%s has already called reply_with_error, so just return */\n" name;
      pr "    return;\n";
      pr "\n";

      (match fst style with
       | Err -> pr "  reply (NULL, NULL);\n"
       | RInt n ->
	   pr "  struct guestfs_%s_ret ret;\n" name;
	   pr "  ret.%s = r;\n" n;
	   pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n" name
       | RBool n ->
	   pr "  struct guestfs_%s_ret ret;\n" name;
	   pr "  ret.%s = r;\n" n;
	   pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n" name
       | RConstString _ ->
	   failwithf "RConstString cannot be returned from a daemon function"
       | RString n ->
	   pr "  struct guestfs_%s_ret ret;\n" name;
	   pr "  ret.%s = r;\n" n;
	   pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n" name;
	   pr "  free (r);\n"
       | RStringList n ->
	   pr "  struct guestfs_%s_ret ret;\n" name;
	   pr "  ret.%s.%s_len = count_strings (r);\n" n n;
	   pr "  ret.%s.%s_val = r;\n" n n;
	   pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n" name;
	   pr "  free_strings (r);\n"
       | RIntBool _ ->
	   pr "  reply ((xdrproc_t) xdr_guestfs_%s_ret, (char *) r);\n" name;
	   pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) r);\n" name
       | RPVList n ->
	   pr "  struct guestfs_%s_ret ret;\n" name;
	   pr "  ret.%s = *r;\n" n;
	   pr "  reply ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n" name;
	   pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n" name
       | RVGList n ->
	   pr "  struct guestfs_%s_ret ret;\n" name;
	   pr "  ret.%s = *r;\n" n;
	   pr "  reply ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n" name;
	   pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n" name
       | RLVList n ->
	   pr "  struct guestfs_%s_ret ret;\n" name;
	   pr "  ret.%s = *r;\n" n;
	   pr "  reply ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n" name;
	   pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n" name
      );

      pr "}\n\n";
  ) daemon_functions;

  (* Dispatch function. *)
  pr "void dispatch_incoming_message (XDR *xdr_in)\n";
  pr "{\n";
  pr "  switch (proc_nr) {\n";

  List.iter (
    fun (name, style, _, _, _, _) ->
	pr "    case GUESTFS_PROC_%s:\n" (String.uppercase name);
	pr "      %s_stub (xdr_in);\n" name;
	pr "      break;\n"
  ) daemon_functions;

  pr "    default:\n";
  pr "      reply_with_error (\"dispatch_incoming_message: unknown procedure number %%d\", proc_nr);\n";
  pr "  }\n";
  pr "}\n";
  pr "\n";

  (* LVM columns and tokenization functions. *)
  (* XXX This generates crap code.  We should rethink how we
   * do this parsing.
   *)
  List.iter (
    function
    | typ, cols ->
	pr "static const char *lvm_%s_cols = \"%s\";\n"
	  typ (String.concat "," (List.map fst cols));
	pr "\n";

	pr "static int lvm_tokenize_%s (char *str, struct guestfs_lvm_int_%s *r)\n" typ typ;
	pr "{\n";
	pr "  char *tok, *p, *next;\n";
	pr "  int i, j;\n";
	pr "\n";
	(*
	pr "  fprintf (stderr, \"%%s: <<%%s>>\\n\", __func__, str);\n";
	pr "\n";
	*)
	pr "  if (!str) {\n";
	pr "    fprintf (stderr, \"%%s: failed: passed a NULL string\\n\", __func__);\n";
	pr "    return -1;\n";
	pr "  }\n";
	pr "  if (!*str || isspace (*str)) {\n";
	pr "    fprintf (stderr, \"%%s: failed: passed a empty string or one beginning with whitespace\\n\", __func__);\n";
	pr "    return -1;\n";
	pr "  }\n";
	pr "  tok = str;\n";
	List.iter (
	  fun (name, coltype) ->
	    pr "  if (!tok) {\n";
	    pr "    fprintf (stderr, \"%%s: failed: string finished early, around token %%s\\n\", __func__, \"%s\");\n" name;
	    pr "    return -1;\n";
	    pr "  }\n";
	    pr "  p = strchrnul (tok, ',');\n";
	    pr "  if (*p) next = p+1; else next = NULL;\n";
	    pr "  *p = '\\0';\n";
	    (match coltype with
	     | `String ->
		 pr "  r->%s = strdup (tok);\n" name;
		 pr "  if (r->%s == NULL) {\n" name;
		 pr "    perror (\"strdup\");\n";
		 pr "    return -1;\n";
		 pr "  }\n"
	     | `UUID ->
		 pr "  for (i = j = 0; i < 32; ++j) {\n";
		 pr "    if (tok[j] == '\\0') {\n";
		 pr "      fprintf (stderr, \"%%s: failed to parse UUID from '%%s'\\n\", __func__, tok);\n";
		 pr "      return -1;\n";
		 pr "    } else if (tok[j] != '-')\n";
		 pr "      r->%s[i++] = tok[j];\n" name;
		 pr "  }\n";
	     | `Bytes ->
		 pr "  if (sscanf (tok, \"%%\"SCNu64, &r->%s) != 1) {\n" name;
		 pr "    fprintf (stderr, \"%%s: failed to parse size '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
		 pr "    return -1;\n";
		 pr "  }\n";
	     | `Int ->
		 pr "  if (sscanf (tok, \"%%\"SCNi64, &r->%s) != 1) {\n" name;
		 pr "    fprintf (stderr, \"%%s: failed to parse int '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
		 pr "    return -1;\n";
		 pr "  }\n";
	     | `OptPercent ->
		 pr "  if (tok[0] == '\\0')\n";
		 pr "    r->%s = -1;\n" name;
		 pr "  else if (sscanf (tok, \"%%f\", &r->%s) != 1) {\n" name;
		 pr "    fprintf (stderr, \"%%s: failed to parse float '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
		 pr "    return -1;\n";
		 pr "  }\n";
	    );
	    pr "  tok = next;\n";
	) cols;

	pr "  if (tok != NULL) {\n";
	pr "    fprintf (stderr, \"%%s: failed: extra tokens at end of string\\n\", __func__);\n";
	pr "    return -1;\n";
	pr "  }\n";
	pr "  return 0;\n";
	pr "}\n";
	pr "\n";

	pr "guestfs_lvm_int_%s_list *\n" typ;
	pr "parse_command_line_%ss (void)\n" typ;
	pr "{\n";
	pr "  char *out, *err;\n";
	pr "  char *p, *pend;\n";
	pr "  int r, i;\n";
	pr "  guestfs_lvm_int_%s_list *ret;\n" typ;
	pr "  void *newp;\n";
	pr "\n";
	pr "  ret = malloc (sizeof *ret);\n";
	pr "  if (!ret) {\n";
	pr "    reply_with_perror (\"malloc\");\n";
	pr "    return NULL;\n";
	pr "  }\n";
	pr "\n";
	pr "  ret->guestfs_lvm_int_%s_list_len = 0;\n" typ;
	pr "  ret->guestfs_lvm_int_%s_list_val = NULL;\n" typ;
	pr "\n";
	pr "  r = command (&out, &err,\n";
	pr "	       \"/sbin/lvm\", \"%ss\",\n" typ;
	pr "	       \"-o\", lvm_%s_cols, \"--unbuffered\", \"--noheadings\",\n" typ;
	pr "	       \"--nosuffix\", \"--separator\", \",\", \"--units\", \"b\", NULL);\n";
	pr "  if (r == -1) {\n";
	pr "    reply_with_error (\"%%s\", err);\n";
	pr "    free (out);\n";
	pr "    free (err);\n";
	pr "    return NULL;\n";
	pr "  }\n";
	pr "\n";
	pr "  free (err);\n";
	pr "\n";
	pr "  /* Tokenize each line of the output. */\n";
	pr "  p = out;\n";
	pr "  i = 0;\n";
	pr "  while (p) {\n";
	pr "    pend = strchr (p, '\\n');	/* Get the next line of output. */\n";
	pr "    if (pend) {\n";
	pr "      *pend = '\\0';\n";
	pr "      pend++;\n";
	pr "    }\n";
	pr "\n";
	pr "    while (*p && isspace (*p))	/* Skip any leading whitespace. */\n";
	pr "      p++;\n";
	pr "\n";
	pr "    if (!*p) {			/* Empty line?  Skip it. */\n";
	pr "      p = pend;\n";
	pr "      continue;\n";
	pr "    }\n";
	pr "\n";
	pr "    /* Allocate some space to store this next entry. */\n";
	pr "    newp = realloc (ret->guestfs_lvm_int_%s_list_val,\n" typ;
	pr "		    sizeof (guestfs_lvm_int_%s) * (i+1));\n" typ;
	pr "    if (newp == NULL) {\n";
	pr "      reply_with_perror (\"realloc\");\n";
	pr "      free (ret->guestfs_lvm_int_%s_list_val);\n" typ;
	pr "      free (ret);\n";
	pr "      free (out);\n";
	pr "      return NULL;\n";
	pr "    }\n";
	pr "    ret->guestfs_lvm_int_%s_list_val = newp;\n" typ;
	pr "\n";
	pr "    /* Tokenize the next entry. */\n";
	pr "    r = lvm_tokenize_%s (p, &ret->guestfs_lvm_int_%s_list_val[i]);\n" typ typ;
	pr "    if (r == -1) {\n";
	pr "      reply_with_error (\"failed to parse output of '%ss' command\");\n" typ;
        pr "      free (ret->guestfs_lvm_int_%s_list_val);\n" typ;
        pr "      free (ret);\n";
	pr "      free (out);\n";
	pr "      return NULL;\n";
	pr "    }\n";
	pr "\n";
	pr "    ++i;\n";
	pr "    p = pend;\n";
	pr "  }\n";
	pr "\n";
	pr "  ret->guestfs_lvm_int_%s_list_len = i;\n" typ;
	pr "\n";
	pr "  free (out);\n";
	pr "  return ret;\n";
	pr "}\n"

  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols]

(* Generate a lot of different functions for guestfish. *)
and generate_fish_cmds () =
  generate_header CStyle GPLv2;

  let all_functions =
    List.filter (
      fun (_, _, _, flags, _, _) -> not (List.mem NotInFish flags)
    ) all_functions in
  let all_functions_sorted =
    List.filter (
      fun (_, _, _, flags, _, _) -> not (List.mem NotInFish flags)
    ) all_functions_sorted in

  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "#include <inttypes.h>\n";
  pr "\n";
  pr "#include <guestfs.h>\n";
  pr "#include \"fish.h\"\n";
  pr "\n";

  (* list_commands function, which implements guestfish -h *)
  pr "void list_commands (void)\n";
  pr "{\n";
  pr "  printf (\"    %%-16s     %%s\\n\", \"Command\", \"Description\");\n";
  pr "  list_builtin_commands ();\n";
  List.iter (
    fun (name, _, _, flags, shortdesc, _) ->
      let name = replace_char name '_' '-' in
      pr "  printf (\"%%-20s %%s\\n\", \"%s\", \"%s\");\n"
	name shortdesc
  ) all_functions_sorted;
  pr "  printf (\"    Use -h <cmd> / help <cmd> to show detailed help for a command.\\n\");\n";
  pr "}\n";
  pr "\n";

  (* display_command function, which implements guestfish -h cmd *)
  pr "void display_command (const char *cmd)\n";
  pr "{\n";
  List.iter (
    fun (name, style, _, flags, shortdesc, longdesc) ->
      let name2 = replace_char name '_' '-' in
      let alias =
	try find_map (function FishAlias n -> Some n | _ -> None) flags
	with Not_found -> name in
      let longdesc = replace_str longdesc "C<guestfs_" "C<" in
      let synopsis =
	match snd style with
	| P0 -> name2
	| args ->
	    sprintf "%s <%s>"
	      name2 (String.concat "> <" (map_args name_of_argt args)) in

      let warnings =
	if List.mem ProtocolLimitWarning flags then
	  "\n\nBecause of the message protocol, there is a transfer limit 
of somewhere between 2MB and 4MB.  To transfer large files you should use
FTP."
	else "" in

      let describe_alias =
	if name <> alias then
	  sprintf "\n\nYou can use '%s' as an alias for this command." alias
	else "" in

      pr "  if (";
      pr "strcasecmp (cmd, \"%s\") == 0" name;
      if name <> name2 then
	pr " || strcasecmp (cmd, \"%s\") == 0" name2;
      if name <> alias then
	pr " || strcasecmp (cmd, \"%s\") == 0" alias;
      pr ")\n";
      pr "    pod2text (\"%s - %s\", %S);\n"
	name2 shortdesc
	(" " ^ synopsis ^ "\n\n" ^ longdesc ^ warnings ^ describe_alias);
      pr "  else\n"
  ) all_functions;
  pr "    display_builtin_command (cmd);\n";
  pr "}\n";
  pr "\n";

  (* print_{pv,vg,lv}_list functions *)
  List.iter (
    function
    | typ, cols ->
	pr "static void print_%s (struct guestfs_lvm_%s *%s)\n" typ typ typ;
	pr "{\n";
	pr "  int i;\n";
	pr "\n";
	List.iter (
	  function
	  | name, `String ->
	      pr "  printf (\"%s: %%s\\n\", %s->%s);\n" name typ name
	  | name, `UUID ->
	      pr "  printf (\"%s: \");\n" name;
	      pr "  for (i = 0; i < 32; ++i)\n";
	      pr "    printf (\"%%c\", %s->%s[i]);\n" typ name;
	      pr "  printf (\"\\n\");\n"
	  | name, `Bytes ->
	      pr "  printf (\"%s: %%\" PRIu64 \"\\n\", %s->%s);\n" name typ name
	  | name, `Int ->
	      pr "  printf (\"%s: %%\" PRIi64 \"\\n\", %s->%s);\n" name typ name
	  | name, `OptPercent ->
	      pr "  if (%s->%s >= 0) printf (\"%s: %%g %%%%\\n\", %s->%s);\n"
		typ name name typ name;
	      pr "  else printf (\"%s: \\n\");\n" name
	) cols;
	pr "}\n";
	pr "\n";
	pr "static void print_%s_list (struct guestfs_lvm_%s_list *%ss)\n"
	  typ typ typ;
	pr "{\n";
	pr "  int i;\n";
	pr "\n";
	pr "  for (i = 0; i < %ss->len; ++i)\n" typ;
	pr "    print_%s (&%ss->val[i]);\n" typ typ;
	pr "}\n";
	pr "\n";
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols];

  (* run_<action> actions *)
  List.iter (
    fun (name, style, _, flags, _, _) ->
      pr "static int run_%s (const char *cmd, int argc, char *argv[])\n" name;
      pr "{\n";
      (match fst style with
       | Err
       | RInt _
       | RBool _ -> pr "  int r;\n"
       | RConstString _ -> pr "  const char *r;\n"
       | RString _ -> pr "  char *r;\n"
       | RStringList _ -> pr "  char **r;\n"
       | RIntBool _ -> pr "  struct guestfs_int_bool *r;\n"
       | RPVList _ -> pr "  struct guestfs_lvm_pv_list *r;\n"
       | RVGList _ -> pr "  struct guestfs_lvm_vg_list *r;\n"
       | RLVList _ -> pr "  struct guestfs_lvm_lv_list *r;\n"
      );
      iter_args (
	function
	| String n -> pr "  const char *%s;\n" n
	| OptString n -> pr "  const char *%s;\n" n
	| Bool n -> pr "  int %s;\n" n
	| Int n -> pr "  int %s;\n" n
      ) (snd style);

      (* Check and convert parameters. *)
      let argc_expected = nr_args (snd style) in
      pr "  if (argc != %d) {\n" argc_expected;
      pr "    fprintf (stderr, \"%%s should have %d parameter(s)\\n\", cmd);\n"
	argc_expected;
      pr "    fprintf (stderr, \"type 'help %%s' for help on %%s\\n\", cmd, cmd);\n";
      pr "    return -1;\n";
      pr "  }\n";
      iteri_args (
	fun i ->
	  function
	  | String name -> pr "  %s = argv[%d];\n" name i
	  | OptString name ->
	      pr "  %s = strcmp (argv[%d], \"\") != 0 ? argv[%d] : NULL;\n"
		name i i
	  | Bool name ->
	      pr "  %s = is_true (argv[%d]) ? 1 : 0;\n" name i
	  | Int name ->
	      pr "  %s = atoi (argv[%d]);\n" name i
      ) (snd style);

      (* Call C API function. *)
      let fn =
	try find_map (function FishAction n -> Some n | _ -> None) flags
	with Not_found -> sprintf "guestfs_%s" name in
      pr "  r = %s " fn;
      generate_call_args ~handle:"g" style;
      pr ";\n";

      (* Check return value for errors and display command results. *)
      (match fst style with
       | Err -> pr "  return r;\n"
       | RInt _ ->
	   pr "  if (r == -1) return -1;\n";
	   pr "  if (r) printf (\"%%d\\n\", r);\n";
	   pr "  return 0;\n"
       | RBool _ ->
	   pr "  if (r == -1) return -1;\n";
	   pr "  if (r) printf (\"true\\n\"); else printf (\"false\\n\");\n";
	   pr "  return 0;\n"
       | RConstString _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  printf (\"%%s\\n\", r);\n";
	   pr "  return 0;\n"
       | RString _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  printf (\"%%s\\n\", r);\n";
	   pr "  free (r);\n";
	   pr "  return 0;\n"
       | RStringList _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_strings (r);\n";
	   pr "  free_strings (r);\n";
	   pr "  return 0;\n"
       | RIntBool _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  printf (\"%%d, %%s\\n\", r->i,\n";
	   pr "    r->b ? \"true\" : \"false\");\n";
	   pr "  guestfs_free_int_bool (r);\n";
	   pr "  return 0;\n"
       | RPVList _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_pv_list (r);\n";
	   pr "  guestfs_free_lvm_pv_list (r);\n";
	   pr "  return 0;\n"
       | RVGList _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_vg_list (r);\n";
	   pr "  guestfs_free_lvm_vg_list (r);\n";
	   pr "  return 0;\n"
       | RLVList _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_lv_list (r);\n";
	   pr "  guestfs_free_lvm_lv_list (r);\n";
	   pr "  return 0;\n"
      );
      pr "}\n";
      pr "\n"
  ) all_functions;

  (* run_action function *)
  pr "int run_action (const char *cmd, int argc, char *argv[])\n";
  pr "{\n";
  List.iter (
    fun (name, _, _, flags, _, _) ->
      let name2 = replace_char name '_' '-' in
      let alias =
	try find_map (function FishAlias n -> Some n | _ -> None) flags
	with Not_found -> name in
      pr "  if (";
      pr "strcasecmp (cmd, \"%s\") == 0" name;
      if name <> name2 then
	pr " || strcasecmp (cmd, \"%s\") == 0" name2;
      if name <> alias then
	pr " || strcasecmp (cmd, \"%s\") == 0" alias;
      pr ")\n";
      pr "    return run_%s (cmd, argc, argv);\n" name;
      pr "  else\n";
  ) all_functions;
  pr "    {\n";
  pr "      fprintf (stderr, \"%%s: unknown command\\n\", cmd);\n";
  pr "      return -1;\n";
  pr "    }\n";
  pr "  return 0;\n";
  pr "}\n";
  pr "\n"

(* Generate the POD documentation for guestfish. *)
and generate_fish_actions_pod () =
  let all_functions_sorted =
    List.filter (
      fun (_, _, _, flags, _, _) -> not (List.mem NotInFish flags)
    ) all_functions_sorted in

  List.iter (
    fun (name, style, _, flags, _, longdesc) ->
      let longdesc = replace_str longdesc "C<guestfs_" "C<" in
      let name = replace_char name '_' '-' in
      let alias =
	try find_map (function FishAlias n -> Some n | _ -> None) flags
	with Not_found -> name in

      pr "=head2 %s" name;
      if name <> alias then
	pr " | %s" alias;
      pr "\n";
      pr "\n";
      pr " %s" name;
      iter_args (
	function
	| String n -> pr " %s" n
	| OptString n -> pr " %s" n
	| Bool _ -> pr " true|false"
	| Int n -> pr " %s" n
      ) (snd style);
      pr "\n";
      pr "\n";
      pr "%s\n\n" longdesc
  ) all_functions_sorted

(* Generate a C function prototype. *)
and generate_prototype ?(extern = true) ?(static = false) ?(semicolon = true)
    ?(single_line = false) ?(newline = false) ?(in_daemon = false)
    ?(prefix = "")
    ?handle name style =
  if extern then pr "extern ";
  if static then pr "static ";
  (match fst style with
   | Err -> pr "int "
   | RInt _ -> pr "int "
   | RBool _ -> pr "int "
   | RConstString _ -> pr "const char *"
   | RString _ -> pr "char *"
   | RStringList _ -> pr "char **"
   | RIntBool _ ->
       if not in_daemon then pr "struct guestfs_int_bool *"
       else pr "guestfs_%s_ret *" name
   | RPVList _ ->
       if not in_daemon then pr "struct guestfs_lvm_pv_list *"
       else pr "guestfs_lvm_int_pv_list *"
   | RVGList _ ->
       if not in_daemon then pr "struct guestfs_lvm_vg_list *"
       else pr "guestfs_lvm_int_vg_list *"
   | RLVList _ ->
       if not in_daemon then pr "struct guestfs_lvm_lv_list *"
       else pr "guestfs_lvm_int_lv_list *"
  );
  pr "%s%s (" prefix name;
  if handle = None && nr_args (snd style) = 0 then
    pr "void"
  else (
    let comma = ref false in
    (match handle with
     | None -> ()
     | Some handle -> pr "guestfs_h *%s" handle; comma := true
    );
    let next () =
      if !comma then (
	if single_line then pr ", " else pr ",\n\t\t"
      );
      comma := true
    in
    iter_args (
      function
      | String n -> next (); pr "const char *%s" n
      | OptString n -> next (); pr "const char *%s" n
      | Bool n -> next (); pr "int %s" n
      | Int n -> next (); pr "int %s" n
    ) (snd style);
  );
  pr ")";
  if semicolon then pr ";";
  if newline then pr "\n"

(* Generate C call arguments, eg "(handle, foo, bar)" *)
and generate_call_args ?handle style =
  pr "(";
  let comma = ref false in
  (match handle with
   | None -> ()
   | Some handle -> pr "%s" handle; comma := true
  );
  iter_args (
    fun arg ->
      if !comma then pr ", ";
      comma := true;
      match arg with
      | String n -> pr "%s" n
      | OptString n -> pr "%s" n
      | Bool n -> pr "%s" n
      | Int n -> pr "%s" n
  ) (snd style);
  pr ")"

(* Generate the OCaml bindings interface. *)
and generate_ocaml_mli () =
  generate_header OCamlStyle LGPLv2;

  pr "\
(** For API documentation you should refer to the C API
    in the guestfs(3) manual page.  The OCaml API uses almost
    exactly the same calls. *)

type t
(** A [guestfs_h] handle. *)

exception Error of string
(** This exception is raised when there is an error. *)

val create : unit -> t

val close : t -> unit
(** Handles are closed by the garbage collector when they become
    unreferenced, but callers can also call this in order to
    provide predictable cleanup. *)

";
  generate_ocaml_lvm_structure_decls ();

  (* The actions. *)
  List.iter (
    fun (name, style, _, _, shortdesc, _) ->
      generate_ocaml_prototype name style;
      pr "(** %s *)\n" shortdesc;
      pr "\n"
  ) all_functions

(* Generate the OCaml bindings implementation. *)
and generate_ocaml_ml () =
  generate_header OCamlStyle LGPLv2;

  pr "\
type t
exception Error of string
external create : unit -> t = \"ocaml_guestfs_create\"
external close : t -> unit = \"ocaml_guestfs_close\"

let () =
  Callback.register_exception \"ocaml_guestfs_error\" (Error \"\")

";

  generate_ocaml_lvm_structure_decls ();

  (* The actions. *)
  List.iter (
    fun (name, style, _, _, shortdesc, _) ->
      generate_ocaml_prototype ~is_external:true name style;
  ) all_functions

(* Generate the OCaml bindings C implementation. *)
and generate_ocaml_c () =
  generate_header CStyle LGPLv2;

  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "\n";
  pr "#include <caml/config.h>\n";
  pr "#include <caml/alloc.h>\n";
  pr "#include <caml/callback.h>\n";
  pr "#include <caml/fail.h>\n";
  pr "#include <caml/memory.h>\n";
  pr "#include <caml/mlvalues.h>\n";
  pr "#include <caml/signals.h>\n";
  pr "\n";
  pr "#include <guestfs.h>\n";
  pr "\n";
  pr "#include \"guestfs_c.h\"\n";
  pr "\n";

  (* LVM struct copy functions. *)
  List.iter (
    fun (typ, cols) ->
      let has_optpercent_col =
	List.exists (function (_, `OptPercent) -> true | _ -> false) cols in

      pr "static CAMLprim value\n";
      pr "copy_lvm_%s (const struct guestfs_lvm_%s *%s)\n" typ typ typ;
      pr "{\n";
      pr "  CAMLparam0 ();\n";
      if has_optpercent_col then
	pr "  CAMLlocal3 (rv, v, v2);\n"
      else
	pr "  CAMLlocal2 (rv, v);\n";
      pr "\n";
      pr "  rv = caml_alloc (%d, 0);\n" (List.length cols);
      iteri (
	fun i col ->
	  (match col with
	   | name, `String ->
	       pr "  v = caml_copy_string (%s->%s);\n" typ name
	   | name, `UUID ->
	       pr "  v = caml_alloc_string (32);\n";
	       pr "  memcpy (String_val (v), %s->%s, 32);\n" typ name
	   | name, `Bytes
	   | name, `Int ->
	       pr "  v = caml_copy_int64 (%s->%s);\n" typ name
	   | name, `OptPercent ->
	       pr "  if (%s->%s >= 0) { /* Some %s */\n" typ name name;
	       pr "    v2 = caml_copy_double (%s->%s);\n" typ name;
	       pr "    v = caml_alloc (1, 0);\n";
	       pr "    Store_field (v, 0, v2);\n";
	       pr "  } else /* None */\n";
	       pr "    v = Val_int (0);\n";
	  );
	  pr "  Store_field (rv, %d, v);\n" i
      ) cols;
      pr "  CAMLreturn (rv);\n";
      pr "}\n";
      pr "\n";

      pr "static CAMLprim value\n";
      pr "copy_lvm_%s_list (const struct guestfs_lvm_%s_list *%ss)\n"
	typ typ typ;
      pr "{\n";
      pr "  CAMLparam0 ();\n";
      pr "  CAMLlocal2 (rv, v);\n";
      pr "  int i;\n";
      pr "\n";
      pr "  if (%ss->len == 0)\n" typ;
      pr "    CAMLreturn (Atom (0));\n";
      pr "  else {\n";
      pr "    rv = caml_alloc (%ss->len, 0);\n" typ;
      pr "    for (i = 0; i < %ss->len; ++i) {\n" typ;
      pr "      v = copy_lvm_%s (&%ss->val[i]);\n" typ typ;
      pr "      caml_modify (&Field (rv, i), v);\n";
      pr "    }\n";
      pr "    CAMLreturn (rv);\n";
      pr "  }\n";
      pr "}\n";
      pr "\n";
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols];

  List.iter (
    fun (name, style, _, _, _, _) ->
      pr "CAMLprim value\n";
      pr "ocaml_guestfs_%s (value gv" name;
      iter_args (
	fun arg -> pr ", value %sv" (name_of_argt arg)
      ) (snd style);
      pr ")\n";
      pr "{\n";
      pr "  CAMLparam%d (gv" (1 + (nr_args (snd style)));
      iter_args (
	fun arg -> pr ", %sv" (name_of_argt arg)
      ) (snd style);
      pr ");\n";
      pr "  CAMLlocal1 (rv);\n";
      pr "\n";

      pr "  guestfs_h *g = Guestfs_val (gv);\n";
      pr "  if (g == NULL)\n";
      pr "    caml_failwith (\"%s: used handle after closing it\");\n" name;
      pr "\n";

      iter_args (
	function
	| String n ->
	    pr "  const char *%s = String_val (%sv);\n" n n
	| OptString n ->
	    pr "  const char *%s =\n" n;
	    pr "    %sv != Val_int (0) ? String_val (Field (%sv, 0)) : NULL;\n"
	      n n
	| Bool n ->
	    pr "  int %s = Bool_val (%sv);\n" n n
	| Int n ->
	    pr "  int %s = Int_val (%sv);\n" n n
      ) (snd style);
      let error_code =
	match fst style with
	| Err -> pr "  int r;\n"; "-1"
	| RInt _ -> pr "  int r;\n"; "-1"
	| RBool _ -> pr "  int r;\n"; "-1"
	| RConstString _ -> pr "  const char *r;\n"; "NULL"
	| RString _ -> pr "  char *r;\n"; "NULL"
	| RStringList _ ->
	    pr "  int i;\n";
	    pr "  char **r;\n";
	    "NULL"
	| RIntBool _ ->
	    pr "  struct guestfs_int_bool *r;\n";
	    "NULL"
	| RPVList _ ->
	    pr "  struct guestfs_lvm_pv_list *r;\n";
	    "NULL"
	| RVGList _ ->
	    pr "  struct guestfs_lvm_vg_list *r;\n";
	    "NULL"
	| RLVList _ ->
	    pr "  struct guestfs_lvm_lv_list *r;\n";
	    "NULL" in
      pr "\n";

      pr "  caml_enter_blocking_section ();\n";
      pr "  r = guestfs_%s " name;
      generate_call_args ~handle:"g" style;
      pr ";\n";
      pr "  caml_leave_blocking_section ();\n";
      pr "  if (r == %s)\n" error_code;
      pr "    ocaml_guestfs_raise_error (g, \"%s\");\n" name;
      pr "\n";

      (match fst style with
       | Err -> pr "  rv = Val_unit;\n"
       | RInt _ -> pr "  rv = Val_int (r);\n"
       | RBool _ -> pr "  rv = Val_bool (r);\n"
       | RConstString _ -> pr "  rv = caml_copy_string (r);\n"
       | RString _ ->
	   pr "  rv = caml_copy_string (r);\n";
	   pr "  free (r);\n"
       | RStringList _ ->
	   pr "  rv = caml_copy_string_array ((const char **) r);\n";
	   pr "  for (i = 0; r[i] != NULL; ++i) free (r[i]);\n";
	   pr "  free (r);\n"
       | RIntBool _ ->
	   pr "  rv = caml_alloc (2, 0);\n";
	   pr "  Store_field (rv, 0, Val_int (r->i));\n";
	   pr "  Store_field (rv, 1, Val_bool (r->b));\n";
	   pr "  guestfs_free_int_bool (r);\n";
       | RPVList _ ->
	   pr "  rv = copy_lvm_pv_list (r);\n";
	   pr "  guestfs_free_lvm_pv_list (r);\n";
       | RVGList _ ->
	   pr "  rv = copy_lvm_vg_list (r);\n";
	   pr "  guestfs_free_lvm_vg_list (r);\n";
       | RLVList _ ->
	   pr "  rv = copy_lvm_lv_list (r);\n";
	   pr "  guestfs_free_lvm_lv_list (r);\n";
      );

      pr "  CAMLreturn (rv);\n";
      pr "}\n";
      pr "\n"
  ) all_functions

and generate_ocaml_lvm_structure_decls () =
  List.iter (
    fun (typ, cols) ->
      pr "type lvm_%s = {\n" typ;
      List.iter (
	function
	| name, `String -> pr "  %s : string;\n" name
	| name, `UUID -> pr "  %s : string;\n" name
	| name, `Bytes -> pr "  %s : int64;\n" name
	| name, `Int -> pr "  %s : int64;\n" name
	| name, `OptPercent -> pr "  %s : float option;\n" name
      ) cols;
      pr "}\n";
      pr "\n"
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols]

and generate_ocaml_prototype ?(is_external = false) name style =
  if is_external then pr "external " else pr "val ";
  pr "%s : t -> " name;
  iter_args (
    function
    | String _ -> pr "string -> "
    | OptString _ -> pr "string option -> "
    | Bool _ -> pr "bool -> "
    | Int _ -> pr "int -> "
  ) (snd style);
  (match fst style with
   | Err -> pr "unit" (* all errors are turned into exceptions *)
   | RInt _ -> pr "int"
   | RBool _ -> pr "bool"
   | RConstString _ -> pr "string"
   | RString _ -> pr "string"
   | RStringList _ -> pr "string array"
   | RIntBool _ -> pr "int * bool"
   | RPVList _ -> pr "lvm_pv array"
   | RVGList _ -> pr "lvm_vg array"
   | RLVList _ -> pr "lvm_lv array"
  );
  if is_external then pr " = \"ocaml_guestfs_%s\"" name;
  pr "\n"

(* Generate Perl xs code, a sort of crazy variation of C with macros. *)
and generate_perl_xs () =
  generate_header CStyle LGPLv2;

  pr "\
#include \"EXTERN.h\"
#include \"perl.h\"
#include \"XSUB.h\"

#include <guestfs.h>

#ifndef PRId64
#define PRId64 \"lld\"
#endif

static SV *
my_newSVll(long long val) {
#ifdef USE_64_BIT_ALL
  return newSViv(val);
#else
  char buf[100];
  int len;
  len = snprintf(buf, 100, \"%%\" PRId64, val);
  return newSVpv(buf, len);
#endif
}

#ifndef PRIu64
#define PRIu64 \"llu\"
#endif

static SV *
my_newSVull(unsigned long long val) {
#ifdef USE_64_BIT_ALL
  return newSVuv(val);
#else
  char buf[100];
  int len;
  len = snprintf(buf, 100, \"%%\" PRIu64, val);
  return newSVpv(buf, len);
#endif
}

/* XXX Not thread-safe, and in general not safe if the caller is
 * issuing multiple requests in parallel (on different guestfs
 * handles).  We should use the guestfs_h handle passed to the
 * error handle to distinguish these cases.
 */
static char *last_error = NULL;

static void
error_handler (guestfs_h *g,
	       void *data,
	       const char *msg)
{
  if (last_error != NULL) free (last_error);
  last_error = strdup (msg);
}

MODULE = Sys::Guestfs  PACKAGE = Sys::Guestfs

guestfs_h *
_create ()
   CODE:
      RETVAL = guestfs_create ();
      if (!RETVAL)
        croak (\"could not create guestfs handle\");
      guestfs_set_error_handler (RETVAL, error_handler, NULL);
 OUTPUT:
      RETVAL

void
DESTROY (g)
      guestfs_h *g;
 PPCODE:
      guestfs_close (g);

";

  List.iter (
    fun (name, style, _, _, _, _) ->
      (match fst style with
       | Err -> pr "void\n"
       | RInt _ -> pr "SV *\n"
       | RBool _ -> pr "SV *\n"
       | RConstString _ -> pr "SV *\n"
       | RString _ -> pr "SV *\n"
       | RStringList _
       | RIntBool _
       | RPVList _ | RVGList _ | RLVList _ ->
	   pr "void\n" (* all lists returned implictly on the stack *)
      );
      (* Call and arguments. *)
      pr "%s " name;
      generate_call_args ~handle:"g" style;
      pr "\n";
      pr "      guestfs_h *g;\n";
      iter_args (
	function
	| String n -> pr "      char *%s;\n" n
	| OptString n -> pr "      char *%s;\n" n
	| Bool n -> pr "      int %s;\n" n
	| Int n -> pr "      int %s;\n" n
      ) (snd style);
      (* Code. *)
      (match fst style with
       | Err ->
	   pr " PPCODE:\n";
	   pr "      if (guestfs_%s " name;
	   generate_call_args ~handle:"g" style;
	   pr " == -1)\n";
	   pr "        croak (\"%s: %%s\", last_error);\n" name
       | RInt n
       | RBool n ->
	   pr "PREINIT:\n";
	   pr "      int %s;\n" n;
	   pr "   CODE:\n";
	   pr "      %s = guestfs_%s " n name;
	   generate_call_args ~handle:"g" style;
	   pr ";\n";
	   pr "      if (%s == -1)\n" n;
	   pr "        croak (\"%s: %%s\", last_error);\n" name;
	   pr "      RETVAL = newSViv (%s);\n" n;
	   pr " OUTPUT:\n";
	   pr "      RETVAL\n"
       | RConstString n ->
	   pr "PREINIT:\n";
	   pr "      const char *%s;\n" n;
	   pr "   CODE:\n";
	   pr "      %s = guestfs_%s " n name;
	   generate_call_args ~handle:"g" style;
	   pr ";\n";
	   pr "      if (%s == NULL)\n" n;
	   pr "        croak (\"%s: %%s\", last_error);\n" name;
	   pr "      RETVAL = newSVpv (%s, 0);\n" n;
	   pr " OUTPUT:\n";
	   pr "      RETVAL\n"
       | RString n ->
	   pr "PREINIT:\n";
	   pr "      char *%s;\n" n;
	   pr "   CODE:\n";
	   pr "      %s = guestfs_%s " n name;
	   generate_call_args ~handle:"g" style;
	   pr ";\n";
	   pr "      if (%s == NULL)\n" n;
	   pr "        croak (\"%s: %%s\", last_error);\n" name;
	   pr "      RETVAL = newSVpv (%s, 0);\n" n;
	   pr "      free (%s);\n" n;
	   pr " OUTPUT:\n";
	   pr "      RETVAL\n"
       | RStringList n ->
	   pr "PREINIT:\n";
	   pr "      char **%s;\n" n;
	   pr "      int i, n;\n";
	   pr " PPCODE:\n";
	   pr "      %s = guestfs_%s " n name;
	   generate_call_args ~handle:"g" style;
	   pr ";\n";
	   pr "      if (%s == NULL)\n" n;
	   pr "        croak (\"%s: %%s\", last_error);\n" name;
	   pr "      for (n = 0; %s[n] != NULL; ++n) /**/;\n" n;
	   pr "      EXTEND (SP, n);\n";
	   pr "      for (i = 0; i < n; ++i) {\n";
	   pr "        PUSHs (sv_2mortal (newSVpv (%s[i], 0)));\n" n;
	   pr "        free (%s[i]);\n" n;
	   pr "      }\n";
	   pr "      free (%s);\n" n;
       | RIntBool _ ->
	   pr "PREINIT:\n";
	   pr "      struct guestfs_int_bool *r;\n";
	   pr " PPCODE:\n";
	   pr "      r = guestfs_%s " name;
	   generate_call_args ~handle:"g" style;
	   pr ";\n";
	   pr "      if (r == NULL)\n";
	   pr "        croak (\"%s: %%s\", last_error);\n" name;
	   pr "      EXTEND (SP, 2);\n";
	   pr "      PUSHs (sv_2mortal (newSViv (r->i)));\n";
	   pr "      PUSHs (sv_2mortal (newSViv (r->b)));\n";
	   pr "      guestfs_free_int_bool (r);\n";
       | RPVList n ->
	   generate_perl_lvm_code "pv" pv_cols name style n;
       | RVGList n ->
	   generate_perl_lvm_code "vg" vg_cols name style n;
       | RLVList n ->
	   generate_perl_lvm_code "lv" lv_cols name style n;
      );
      pr "\n"
  ) all_functions

and generate_perl_lvm_code typ cols name style n =
  pr "PREINIT:\n";
  pr "      struct guestfs_lvm_%s_list *%s;\n" typ n;
  pr "      int i;\n";
  pr "      HV *hv;\n";
  pr " PPCODE:\n";
  pr "      %s = guestfs_%s " n name;
  generate_call_args ~handle:"g" style;
  pr ";\n";
  pr "      if (%s == NULL)\n" n;
  pr "        croak (\"%s: %%s\", last_error);\n" name;
  pr "      EXTEND (SP, %s->len);\n" n;
  pr "      for (i = 0; i < %s->len; ++i) {\n" n;
  pr "        hv = newHV ();\n";
  List.iter (
    function
    | name, `String ->
	pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (%s->val[i].%s, 0), 0);\n"
	  name (String.length name) n name
    | name, `UUID ->
	pr "        (void) hv_store (hv, \"%s\", %d, newSVpv (%s->val[i].%s, 32), 0);\n"
	  name (String.length name) n name
    | name, `Bytes ->
	pr "        (void) hv_store (hv, \"%s\", %d, my_newSVull (%s->val[i].%s), 0);\n"
	  name (String.length name) n name
    | name, `Int ->
	pr "        (void) hv_store (hv, \"%s\", %d, my_newSVll (%s->val[i].%s), 0);\n"
	  name (String.length name) n name
    | name, `OptPercent ->
	pr "        (void) hv_store (hv, \"%s\", %d, newSVnv (%s->val[i].%s), 0);\n"
	  name (String.length name) n name
  ) cols;
  pr "        PUSHs (sv_2mortal ((SV *) hv));\n";
  pr "      }\n";
  pr "      guestfs_free_lvm_%s_list (%s);\n" typ n

(* Generate Sys/Guestfs.pm. *)
and generate_perl_pm () =
  generate_header HashStyle LGPLv2;

  pr "\
=pod

=head1 NAME

Sys::Guestfs - Perl bindings for libguestfs

=head1 SYNOPSIS

 use Sys::Guestfs;
 
 my $h = Sys::Guestfs->new ();
 $h->add_drive ('guest.img');
 $h->launch ();
 $h->wait_ready ();
 $h->mount ('/dev/sda1', '/');
 $h->touch ('/hello');
 $h->sync ();

=head1 DESCRIPTION

The C<Sys::Guestfs> module provides a Perl XS binding to the
libguestfs API for examining and modifying virtual machine
disk images.

Amongst the things this is good for: making batch configuration
changes to guests, getting disk used/free statistics (see also:
virt-df), migrating between virtualization systems (see also:
virt-p2v), performing partial backups, performing partial guest
clones, cloning guests and changing registry/UUID/hostname info, and
much else besides.

Libguestfs uses Linux kernel and qemu code, and can access any type of
guest filesystem that Linux and qemu can, including but not limited
to: ext2/3/4, btrfs, FAT and NTFS, LVM, many different disk partition
schemes, qcow, qcow2, vmdk.

Libguestfs provides ways to enumerate guest storage (eg. partitions,
LVs, what filesystem is in each LV, etc.).  It can also run commands
in the context of the guest.  Also you can access filesystems over FTP.

=head1 ERRORS

All errors turn into calls to C<croak> (see L<Carp(3)>).

=head1 METHODS

=over 4

=cut

package Sys::Guestfs;

use strict;
use warnings;

require XSLoader;
XSLoader::load ('Sys::Guestfs');

=item $h = Sys::Guestfs->new ();

Create a new guestfs handle.

=cut

sub new {
  my $proto = shift;
  my $class = ref ($proto) || $proto;

  my $self = Sys::Guestfs::_create ();
  bless $self, $class;
  return $self;
}

";

  (* Actions.  We only need to print documentation for these as
   * they are pulled in from the XS code automatically.
   *)
  List.iter (
    fun (name, style, _, flags, _, longdesc) ->
      let longdesc = replace_str longdesc "C<guestfs_" "C<$h-E<gt>" in
      pr "=item ";
      generate_perl_prototype name style;
      pr "\n\n";
      pr "%s\n\n" longdesc;
      if List.mem ProtocolLimitWarning flags then
	pr "Because of the message protocol, there is a transfer limit 
of somewhere between 2MB and 4MB.  To transfer large files you should use
FTP.\n\n";
  ) all_functions_sorted;

  (* End of file. *)
  pr "\
=cut

1;

=back

=head1 COPYRIGHT

Copyright (C) 2009 Red Hat Inc.

=head1 LICENSE

Please see the file COPYING.LIB for the full license.

=head1 SEE ALSO

L<guestfs(3)>, L<guestfish(1)>.

=cut
"

and generate_perl_prototype name style =
  (match fst style with
   | Err -> ()
   | RBool n
   | RInt n
   | RConstString n
   | RString n -> pr "$%s = " n
   | RIntBool (n, m) -> pr "($%s, $%s) = " n m
   | RStringList n
   | RPVList n
   | RVGList n
   | RLVList n -> pr "@%s = " n
  );
  pr "$h->%s (" name;
  let comma = ref false in
  iter_args (
    fun arg ->
      if !comma then pr ", ";
      comma := true;
      pr "%s" (name_of_argt arg)
  ) (snd style);
  pr ");"

let output_to filename =
  let filename_new = filename ^ ".new" in
  chan := open_out filename_new;
  let close () =
    close_out !chan;
    chan := stdout;
    Unix.rename filename_new filename;
    printf "written %s\n%!" filename;
  in
  close

(* Main program. *)
let () =
  check_functions ();

  let close = output_to "src/guestfs_protocol.x" in
  generate_xdr ();
  close ();

  let close = output_to "src/guestfs-structs.h" in
  generate_structs_h ();
  close ();

  let close = output_to "src/guestfs-actions.h" in
  generate_actions_h ();
  close ();

  let close = output_to "src/guestfs-actions.c" in
  generate_client_actions ();
  close ();

  let close = output_to "daemon/actions.h" in
  generate_daemon_actions_h ();
  close ();

  let close = output_to "daemon/stubs.c" in
  generate_daemon_actions ();
  close ();

  let close = output_to "fish/cmds.c" in
  generate_fish_cmds ();
  close ();

  let close = output_to "guestfs-structs.pod" in
  generate_structs_pod ();
  close ();

  let close = output_to "guestfs-actions.pod" in
  generate_actions_pod ();
  close ();

  let close = output_to "guestfish-actions.pod" in
  generate_fish_actions_pod ();
  close ();

  let close = output_to "ocaml/guestfs.mli" in
  generate_ocaml_mli ();
  close ();

  let close = output_to "ocaml/guestfs.ml" in
  generate_ocaml_ml ();
  close ();

  let close = output_to "ocaml/guestfs_c_actions.c" in
  generate_ocaml_c ();
  close ();

  let close = output_to "perl/Guestfs.xs" in
  generate_perl_xs ();
  close ();

  let close = output_to "perl/lib/Sys/Guestfs.pm" in
  generate_perl_pm ();
  close ();
