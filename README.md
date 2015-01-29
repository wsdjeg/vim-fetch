[![Project status][badge-status]][vimscripts]
[![Current release][badge-release]][releases]
[![Open issues][badge-issues]][issues]
[![License][badge-license]][license]

## Fetch that line and column, boy!

*vim-fetch* enables Vim to process line and column jump specifications in file paths as found in stack traces and similar output. When asked to open such a file, Vim with *vim-fetch* will jump to the specified line (and column, if given) instead of displaying an empty, new file.

If you have wished Vim would understand stack trace formats when opening files, *vim-fetch* is for you.

### Installation

1. The old way: download and source the vimball from the [releases page][releases], then run `:helptags {dir}` on your runtimepath/doc directory. Or,
2. The plug-in manager way: using a git-based plug-in manager (Pathogen, Vundle, NeoBundle etc.), simply add `kopischke/vim-fetch` to the list of plug-ins, source that and issue your manager's install command.

### Usage

TL;DR: `vim path/to/file.ext:12:3` in the shell to open `file.ext`on line 12 at column 3, or `:e[dit] path/to/file.ext:100:12` in Vim to edit `file.ext` on line 100 at column 12. For more, see the [documentation][doc].

### Rationale

Quickly jumping to the point indicated by common stack trace output should be a given in an editor; unluckily, Vim has no concept of this out of the box that does not involve a rather convoluted detour through an error file and the Quickfix window. As the one plug-in I found that aims to fix this, Victor Bogado’s [*file_line*][bogado-plugin], had a number of issues (at the time of this writing, it didn’t correctly process multiple files given with a window switch, i.e. [`-o`, `-O`][bogado-issue-winswitch] and [`-p`][bogado-issue-tabswitch], and I found it choked autocommand processing for the first loaded file on the arglist), I wrote my own.

### License

*vim-fetch* is licensed under [the terms of the MIT license according to the accompanying license file][license].

[badge-status]:           http://img.shields.io/badge/status-active-brightgreen.svg?style=flat-square
[badge-release]:          http://img.shields.io/github/release/kopischke/vim-fetch.svg?style=flat-square
[badge-issues]:           http://img.shields.io/github/issues/kopischke/vim-fetch.svg?style=flat-square
[badge-license]:          http://img.shields.io/badge/license-MIT-blue.svg?style=flat-square
[bogado-plugin]:          https://github.com/bogado/file-line
[bogado-issue-tabswitch]: https://github.com/bogado/file-line/issues/11
[bogado-issue-winswitch]: https://github.com/bogado/file-line/issues/36
[doc]:                    doc/vim-fetch.txt
[issues]:                 https://github.com/kopischke/vim-fetch/issues
[license]:                LICENSE.md
[releases]:               https://github.com/kopischke/vim-fetch/releases
[vimscripts]:             http://www.vim.org/scripts/script.php?script_id=5089
