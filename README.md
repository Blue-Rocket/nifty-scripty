# nifty-scripty

A collection of nifty little scripts.

## xunused

The `xunused` script was designed to help hunt down image resources in
Xcode projects that are no longer actually used by the project. Images
might be referenced from various source files (such as C, HTML, or even
Xib) and they might be referenced without their extension and without
the Cocoa *@2x* high-DPI suffix modifier.

If you run `xunused` without any options, it will be default print out a
report on the resources it found and which onces it considers as
_unused_. For example: 

	Searching directory '.' ...

	===============================================================================
	The following 3 resources were found more than once:

	tray-bg-tile.png:
	  Resources/Images/tray-bg-tile.png
	  Resources/Images/tray-bg-tile@2x.png

	Default.png:
	  Resources/Images/Default.png
	  Resources/Images/Default@2x.png

	tray-bg-tile-dark.png:
	  Resources/Images/tray-bg-tile-dark@2x.png
	  Resources/Images/tray-bg-tile-dark.png

	===============================================================================
	The following 5 resources were not referenced exactly, but matched ignoring
	their file extensions. These are thus NOT considered unused:

	./Resources/Images/navbar-bg-tile.png
	./Resources/Images/Default.png
	./Resources/Images/tray-bg-tile-dark.png
	./Resources/Images/tray-bg-tile.png
	./NotesTests/test-image.png



	===============================================================================
	The following 2 resources were not referenced:

	./Resources/Images/icon-arrow-right.png
	./Resources/Images/icon-arrow-left.png


	Total wasted space: 3.09 Kb

This output basically says that *icon-arrow-right.png* and
*icon-arrow-left.png* are unused (as far as `xunused` is concerned) and
could be deleted from the project.

### xunused usage

Typical usage pattern is to run the script like

	xunused . >output.txt

or

	xunused --verbose . |tee output.txt

Then, after examining the output if you're satisfied with the results
and would like `xunused` to delete the unused resources for you, run

	xunused --delete

to delete the found resources from version control. By default
Subversion is used, but something else could be used by passing the
`--delete-cmd` argument. For example to delete using `git` you'd use:

	xunused --delete --delete-cmd="git rm"

If you're not using version control, you could use a simple `rm`
command, like:

	xunused --delete --delete-cmd=rm
	
### xunused search options

In a general sense, `xunused` searches a directory for a set of
*resouce* files, for example PNG images. It then searches that same
directory for a set of *source* files that might contain a reference to
any of the found resource files, for example Objective-C or HTML source
files. If no source file is found that references a given resource, that
resource is then considered _unused_ by `xunused`.

You can control which files `xunused` treats as *resources* with the
`--rsrc` argument. This argument takes a comma-delimited list of file
extensions. By default this value is set to `jpg,png` so JPEG and PNG
images are treated as resources to test for references to.

You can control which files `xunused` treats as *sources* with the
`--src` argument. This argument takes a comma-delimited list of file
extensions. By default this value is set to `h,c,m,xib,html,plist` which
are common source files in Xcode projects.

### xunused other options

Run `xunused` without any arguments, or with `--help` to get a complete
listing of the available arguments.
