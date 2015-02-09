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

" Edit {file}, placing the cursor at the line and column indicated by {spec}:
" @signature:  fetch#edit({file:String}, {spec:String})
" @returns:    Boolean indicating if a spec has been succesfully resolved
" @notes:      - won't work from a |BufReadCmd| event as it doesn't load non-spec'ed files
"              - won't work from events fired before the spec'ed file is loaded into
"                the buffer (i.e. before '%' is set to the spec'ed file) like |BufNew|
"                as it won't be able to wipe the spurious new spec'ed buffer
function! fetch#edit(file, spec) abort
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

  " processing setup
  let l:pre = ''            " will be prefixed to edit command

  " if current buffer is spec'ed and invalid set it up for wiping
  if expand('%:p') is fnamemodify(a:file, ':p')
    for l:ignore in s:ignore
      if l:ignore.detect(bufnr('%')) is 1
        return 0
      endif
    endfor
    set buftype=nowrite     " avoid issues voiding the buffer
    set bufhidden=wipe      " avoid issues with |bwipeout|
    let l:pre .= 'keepalt ' " don't mess up alternate file on switch
  endif

  " clean up argument list
  if has('listcmds')
    let l:argidx = index(argv(), l:bufname)
    if  l:argidx isnot -1
      execute 'argdelete' fnameescape(l:bufname)
      execute l:argidx.'argadd' fnameescape(l:file)
    endif
  endif

  " edit on argument list if required
  if index(argv(), l:file) isnot -1
    let l:pre .= 'arg'    " set arglist index to edited file
  endif

  " open correct file and place cursor at position spec
  execute l:pre.'edit' fnameescape(l:file)
  return fetch#setpos(l:pos)
endfunction

" Place the current buffer's cursor at {pos}:
" @signature:  fetch#setpos({pos:List<Number[,Number]>})
" @returns:    Boolean
" @notes:      triggers the |User| events
"              - BufFetchPosPre before setting the position
"              - BufFetchPosPost after setting the position
function! fetch#setpos(pos) abort
  silent doautocmd <nomodeline> User BufFetchPosPre
  let b:fetch_lastpos = [max([a:pos[0], 1]), max([get(a:pos, 1, 0), 1])]
  call cursor(b:fetch_lastpos[0], b:fetch_lastpos[1])
  silent! normal! zOzz
  silent doautocmd <nomodeline> User BufFetchPosPost
  return getpos('.')[1:2] == b:fetch_lastpos
endfunction

let &cpo = s:cpo
unlet! s:cpo

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
