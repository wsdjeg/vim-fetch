" AUTOLOAD FUNCTION LIBRARY FOR VIM-FETCH
if &compatible || v:version < 700
  finish
endif

let s:cpo = &cpo
set cpo&vim

" Position specs Dictionary: {{{
let s:specs = {}

" - trailing colon, i.e. ':lnum[:colnum[:]]'
"   trigger with '?*:[0123456789]*' pattern
let s:specs.colon = {'pattern': '\m\%(:\d\+\)\{1,2}:\?$'}
function! s:specs.colon.parse(file) abort
  return [substitute(a:file, self.pattern, '', ''),
        \ split(matchstr(a:file, self.pattern), ':')]
endfunction

" - trailing parentheses, i.e. '(lnum[:colnum])'
"   trigger with '?*([0123456789]*)' pattern
let s:specs.paren = {'pattern': '\m(\(\d\+\%(:\d\+\)\?\))$'}
function! s:specs.paren.parse(file) abort
  return [substitute(a:file, self.pattern, '', ''),
        \ split(matchlist(a:file, self.pattern)[1], ':')]
endfunction

" - Plan 9 type line spec, i.e. '[:]#lnum'
"   trigger with '?*#[0123456789]*' pattern
let s:specs.plan9 = {'pattern': '\m:#\(\d\+\)$'}
function! s:specs.plan9.parse(file) abort
  return [substitute(a:file, self.pattern, '', ''),
        \ [matchlist(a:file, self.pattern)[1]]]
endfunction " }}}

" Detection heuristics for buffers that should not be resolved: {{{
let s:bufignore = {'freaks': []}
function! s:bufignore.detect(bufnr) abort
  for l:freak in self.freaks
    if l:freak.detect(a:bufnr) is 1
      return 1
    endif
  endfor
  return filereadable(bufname(a:bufnr))
endfunction

" - unlisted status as a catch-all for UI type buffers
call add(s:bufignore.freaks, {})
function! s:bufignore.freaks[-1].detect(buffer) abort
  return buflisted(a:buffer) is 0
endfunction

" - any 'buftype' but empty and "nowrite" as explicitly marked "not a file"
call add(s:bufignore.freaks, {'buftypes': ['', 'nowrite']})
function! s:bufignore.freaks[-1].detect(buffer) abort
  return index(self.buftypes, getbufvar(a:buffer, '&buftype')) is -1
endfunction

" - out-of-filesystem Netrw file buffers
call add(s:bufignore.freaks, {})
function! s:bufignore.freaks[-1].detect(buffer) abort
    return !empty(getbufvar(a:buffer, 'netrw_lastfile'))
endfunction " }}}

" Get a copy of vim-fetch's spec matchers:
" @signature:  fetch#specs()
" @returns:    Dictionary<Dictionary> of specs, keyed by name,
"              each spec Dictionary with the following keys:
"              - 'pattern' String to match the spec in a file name
"              - 'parse' Funcref taking a spec'ed file name and
"                 returning a two item List of
"                 {unspec'ed path:String}, {pos:List<Number[,Number]>}
" @notes:     the autocommand match patterns are not included
function! fetch#specs() abort
  return deepcopy(s:specs)
endfunction

" Resolve {spec} for the current buffer, substituting the resolved
" file (if any) for it, with the cursor placed at the resolved position:
" @signature:  fetch#buffer({spec:String})
" @returns:    Boolean
function! fetch#buffer(spec) abort
  let l:bufname = expand('%')
  let l:spec    = s:specs[a:spec]

  " exclude obvious non-matches
  if match(l:bufname, l:spec.pattern) is -1
    return 0
  endif

  " only substitute if we have a valid resolved file
  " and a spurious unresolved buffer both
  let [l:file, l:pos] = l:spec.parse(l:bufname)
  if !filereadable(l:file) || s:bufignore.detect(bufnr('%')) is 1
    return 0
  endif

  " we have a spurious unresolved buffer: set up for wiping
  set buftype=nowrite       " avoid issues voiding the buffer
  set bufhidden=wipe        " avoid issues with |bwipeout|

  " substitute resolved file for unresolved buffer on arglist
  if has('listcmds')
    let l:argidx = index(argv(), l:bufname)
    if  l:argidx isnot -1
      execute 'argdelete' fnameescape(l:bufname)
      execute l:argidx.'argadd' fnameescape(l:file)
    endif
  endif

  " set arglist index to resolved file if required
  " (needs to happen independently of arglist switching to work
  " with the double processing of the first -o/-O/-p window)
  if index(argv(), l:file) isnot -1
    let l:cmd = 'argedit'
  endif

  " edit resolved file and place cursor at position spec
  execute 'keepalt' get(l:, 'cmd', 'edit') fnameescape(l:file)
  return fetch#setpos(l:pos)
endfunction

" Place the current buffer's cursor at {pos}:
" @signature:  fetch#setpos({pos:List<Number[,Number]>})
" @returns:    Boolean
" @notes:      triggers the |User| events
"              - BufFetchPosPre before setting the position
"              - BufFetchPosPost after setting the position
function! fetch#setpos(pos) abort
  call s:doautocmd('BufFetchPosPre')
  let b:fetch_lastpos = [max([a:pos[0], 1]), max([get(a:pos, 1, 0), 1])]
  call cursor(b:fetch_lastpos[0], b:fetch_lastpos[1])
  silent! normal! zOzz
  call s:doautocmd('BufFetchPosPost')
  return getpos('.')[1:2] == b:fetch_lastpos
endfunction

" Private helper functions: {{{
" - apply User autocommands matching {pattern}, but only if there are any
"   1. avoids flooding message history with "No matching autocommands"
"   2. avoids re-applying modelines in Vim < 7.3.442, which doesn't honor |<nomodeline>|
"   see https://groups.google.com/forum/#!topic/vim_dev/DidKMDAsppw
function! s:doautocmd(pattern) abort
  if exists('#User#'.a:pattern)
    execute 'doautocmd <nomodeline> User' a:pattern
  endif
endfunction " }}}

let &cpo = s:cpo
unlet! s:cpo

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
