" AUTOLOAD FUNCTION LIBRARY FOR VIM-FETCH
let s:cpo = &cpo
set cpo&vim

" Position specs Dictionary:
let s:specs = {}

" - trailing colon, i.e. ':lnum[:colnum[:]]'
"   trigger with '*:[0123456789]*' pattern
let s:specs.colon = {'pattern': '\m\%(:\d\+\)\{1,2}:\?$'}
function! s:specs.colon.parse(file) abort
  return [substitute(a:file, self.pattern, '', ''),
        \ split(matchstr(a:file, self.pattern), ':')]
endfunction

" - trailing parentheses, i.e. '(lnum[:colnum])'
"   trigger with '*([0123456789]*)' pattern
let s:specs.paren = {'pattern': '\m(\(\d\+\%(:\d\+\)\?\))$'}
function! s:specs.paren.parse(file) abort
  return [substitute(a:file, self.pattern, '', ''),
        \ split(matchlist(a:file, self.pattern)[1], ':')]
endfunction

" - Plan 9 type line spec, i.e. '[:]#lnum'
"   trigger with '*#[0123456789]*' pattern
let s:specs.plan9 = {'pattern': '\m:#\(\d\+\)$'}
function! s:specs.plan9.parse(file) abort
  return [substitute(a:file, self.pattern, '', ''),
        \ [matchlist(a:file, self.pattern)[1]]]
endfunction

" Detection methods for buffers that bypass `filereadable()`:
let s:ignore = []

" - non-file buffer types
call add(s:ignore, {'types': ['quickfix', 'acwrite', 'nofile']})
function! s:ignore[-1].detect(buffer) abort
  return index(self.types, getbufvar(a:buffer, '&buftype')) isnot -1
endfunction

" - non-document file types that do not trigger the above
"   not needed for: Unite / VimFiler / VimShell / CtrlP / Conque-Shell
call add(s:ignore, {'types': ['netrw']})
function! s:ignore[-1].detect(buffer) abort
  return index(self.types, getbufvar(a:buffer, '&filetype')) isnot -1
endfunction

" - redirected buffers
call add(s:ignore, {'bufvars': ['netrw_lastfile']})
function! s:ignore[-1].detect(buffer) abort
  for l:var in self.bufvars
    if !empty(getbufvar(a:buffer, l:var))
      return 1
    endif
  endfor
  return 0
endfunction

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
" @returns:    Boolean indicating if a spec path has been detected and processed
" @notes:      - won't work from a |BufReadCmd| event as it doesn't load non-spec'ed files
"              - won't work from events fired before the spec'ed file is loaded into
"                the buffer (i.e. before '%' is set to the spec'ed file) like |BufNew|
"                as it won't be able to wipe the spurious new spec'ed buffer
function! fetch#edit(file, spec) abort
  " naive early exit on obvious non-matches
  if filereadable(a:file) || match(a:file, s:specs[a:spec].pattern) is -1
    return 0
  endif

  " check for unspec'ed editable file
  let [l:file, l:pos] = s:specs[a:spec].parse(a:file)
  if !filereadable(l:file)
    return 0                " in doubt, end with invalid user input
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
    let l:argidx = index(argv(), a:file)
    if  l:argidx isnot -1   " substitute un-spec'ed file for spec'ed
      execute 'argdelete' fnameescape(a:file)
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
  silent! normal! zO
  silent doautocmd <nomodeline> User BufFetchPosPost
  return getpos('.')[1:2] == b:fetch_lastpos
endfunction

let &cpo = s:cpo
unlet! s:cpo

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
