" AUTOLOAD FUNCTION LIBRARY FOR VIM-FETCH
if &compatible || v:version < 700
  finish
endif

let s:cpoptions = &cpoptions
set cpoptions&vim

" Position specs Dictionary: {{{
let s:specs = {}

" - trailing colon, i.e. ':lnum[:colnum[:]]'
"   trigger with '?*:[0123456789]*' pattern
let s:specs.colon = {'pattern': '\m\%(:\d\+\)\{1,2}:\?'}
function! s:specs.colon.parse(file) abort
  let l:file = substitute(a:file, self.pattern, '', '')
  let l:pos  = split(matchstr(a:file, self.pattern), ':')
  return [l:file, ['cursor', [l:pos[0], get(l:pos, 1, 0)]]]
endfunction

" - trailing parentheses, i.e. '(lnum[:colnum])'
"   trigger with '?*([0123456789]*)' pattern
let s:specs.paren = {'pattern': '\m(\(\d\+\%(:\d\+\)\?\))'}
function! s:specs.paren.parse(file) abort
  let l:file = substitute(a:file, self.pattern, '', '')
  let l:pos  = split(matchlist(a:file, self.pattern)[1], ':')
  return [l:file, ['cursor', [l:pos[0], get(l:pos, 1, 0)]]]
endfunction

" - Plan 9 type line spec, i.e. '[:]#lnum'
"   trigger with '?*#[0123456789]*' pattern
let s:specs.plan9 = {'pattern': '\m:#\(\d\+\)'}
function! s:specs.plan9.parse(file) abort
  let l:file = substitute(a:file, self.pattern, '', '')
  let l:pos  = matchlist(a:file, self.pattern)[1]
  return [l:file, ['cursor', [l:pos, 0]]]
endfunction

" - Pytest type method spec, i.e. ::method
"   trigger with '?*::?*' pattern
let s:specs.pytest = {'pattern': '\m::\(\w\+\)'}
function! s:specs.pytest.parse(file) abort
  let l:file   = substitute(a:file, self.pattern, '', '')
  let l:name   = matchlist(a:file, self.pattern)[1]
  let l:method = '\m\C^\s*def\s\+\%(\\\n\s*\)*\zs'.l:name.'\s*('
  return [l:file, ['search', [l:method, 'cw']]]
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
"              -'pattern' String to match the spec in a file name
"              -'parse' Funcref taking a spec'ed file name
"                and returning a List of
"                0 unspec'ed path String
"                1 position setting |call()| arguments List
" @notes:      the autocommand match patterns are not included
function! fetch#specs() abort " {{{
  return deepcopy(s:specs)
endfunction " }}}

" Resolve {spec} for the current buffer, substituting the resolved
" file (if any) for it, with the cursor placed at the resolved position:
" @signature:  fetch#buffer({spec:String})
" @returns:    Boolean
function! fetch#buffer(spec) abort " {{{
  let l:bufname = expand('%')
  let l:spec    = s:specs[a:spec]

  " exclude obvious non-matches
  if matchend(l:bufname, l:spec.pattern) isnot len(l:bufname)
    return 0
  endif

  " only substitute if we have a valid resolved file
  " and a spurious unresolved buffer both
  let [l:file, l:jump] = l:spec.parse(l:bufname)
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
  let l:shortmess = &shortmess
  set shortmess+=oO " avoid "Press ENTER" prompt on switch
  try
    execute 'keepalt' get(l:, 'cmd', 'edit').v:cmdarg fnameescape(l:file)
  finally
    let &shortmess = l:shortmess
  endtry
  if !empty(v:swapcommand)
    execute 'normal' v:swapcommand
  endif
  return s:setpos(l:jump)
endfunction " }}}

" Edit |<cfile>|, resolving a possible trailing spec:
" @signature:  fetch#cfile({count:Number})
" @returns:    Boolean
" @notes:      - will test all available specs for a match
"              - will fall back on Vim's |gF| when no spec matches
function! fetch#cfile(count) abort " {{{
  let l:cfile = expand('<cfile>')

  if !empty(l:cfile)
    " locate '<cfile>' in current line
    let l:pattern  = '\M'.escape(l:cfile, '\')
    let l:position = searchpos(l:pattern, 'bcn', line('.'))
    if l:position == [0, 0]
      let l:position = searchpos(l:pattern, 'cn', line('.'))
    endif

    " test for a trailing spec, accounting for multi-line '<cfile>' matches
    let l:lines  = split(l:cfile, "\n")
    let l:line   = getline(l:position[0] + len(l:lines) - 1)
    let l:offset = (len(l:lines) > 1 ? 0 : l:position[1]) + len(l:lines[-1]) - 1
    for l:spec in values(s:specs)
      if match(l:line, l:spec.pattern, l:offset) is l:offset
        let l:match = matchstr(l:line, l:spec.pattern, l:offset)
        " leverage Vim's own |gf| for opening the file
        execute 'normal!' a:count.'gf'
        return s:setpos(l:spec.parse(l:cfile.l:match)[1])
      endif
    endfor
  endif

  " fall back to Vim's |gF|
  execute 'normal!' a:count.'gF'
  return 1
endfunction " }}}

" Edit the visually selected file, resolving a possible trailing spec:
" @signature:  fetch#visual({count:Number})
" @returns:    Boolean
" @notes:      - will test all available specs for a match
"              - will fall back on Vim's |gF| when no spec matches
function! fetch#visual(count) abort " {{{
  " get text between last visual selection marks
  " adapted from http://stackoverflow.com/a/6271254/990363
  let [l:startline, l:startcol] = getpos("'<")[1:2]
  let [l:endline,   l:endcol]   = getpos("'>")[1:2]
  let l:endcol  = min([l:endcol, col([l:endline, '$'])]) " 'V' col nr. bug
  let l:endcol -= &selection is 'inclusive' ? 0 : 1
  let l:lines   = getline(l:startline, l:endline)
  if visualmode() isnot? 'v' " block-wise selection
    let l:endexpr = 'matchstr(v:val, "\\m^.*\\%'.string(l:endcol).'c.\\?")'
    call map(l:lines, 'strpart('.l:endexpr.', '.string(l:startcol-1).')')
  else
    let l:lines[-1] = matchstr(lines[-1], '\m^.*\%'.string(l:endcol).'c.\?')
    let l:lines[0]  = strpart(l:lines[0], l:startcol-1)
  endif
  let l:selection = join(l:lines, "\n")

  " test for a trailing spec
  if !empty(l:selection)
    let l:line = getline(l:endline)
    for l:spec in values(s:specs)
      if match(l:line, l:spec.pattern, l:endcol) is l:endcol
        let l:match = matchstr(l:line, l:spec.pattern, l:endcol)
        call s:dovisual(a:count.'gf') " leverage Vim's |gf| to get the file
        return s:setpos(l:spec.parse(l:selection.l:match)[1])
      endif
    endfor
  endif

  " fall back to Vim's |gF|
  call s:dovisual(a:count.'gF')
  return 1
endfunction " }}}

" Private helper functions: {{{
" - place the current buffer's cursor, triggering the "BufFetchPosX" events
"   see :h call() for the format of the {calldata} List
function! s:setpos(calldata) abort
  call s:doautocmd('BufFetchPosPre')
  keepjumps call call('call', a:calldata)
  let b:fetch_lastpos = getpos('.')[1:2]
  silent! normal! zOzz
  call s:doautocmd('BufFetchPosPost')
  return 1
endfunction

" - apply User autocommands matching {pattern}, but only if there are any
"   1. avoids flooding message history with "No matching autocommands"
"   2. avoids re-applying modelines in Vim < 7.3.442, which doesn't honor |<nomodeline>|
"   see https://groups.google.com/forum/#!topic/vim_dev/DidKMDAsppw
function! s:doautocmd(pattern) abort
  if exists('#User#'.a:pattern)
    execute 'doautocmd <nomodeline> User' a:pattern
  endif
endfunction

" - send command to the last visual selection
function! s:dovisual(command) abort
  let l:cmd = index(['v', 'V', ''], mode()) is -1 ? 'gv'.a:command : a:command
  execute 'normal!' l:cmd
endfunction
" }}}

let &cpoptions = s:cpoptions
unlet! s:cpoptions

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
