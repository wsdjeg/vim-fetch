" AUTOLOAD FUNCTION LIBRARY FOR VIM-FETCH
if &compatible || v:version < 700
  finish
endif

let s:cpoptions = &cpoptions
set cpoptions&vim

" Position specs Dictionary: {{{
let s:specs = {}

" - trailing colon, i.e. ':lnum[:colnum[:]]'
let s:specs.colon = {'pattern': '\m\%(:\d*\)\{1,2}\%(.*\)\?'}
function! s:specs.colon.parse(file) abort
  let l:file = substitute(a:file, self.pattern, '', '')
  let l:pos  = split(matchstr(a:file, self.pattern), ':')
  return [l:file, ['cursor', [get(l:pos, 0, 0), get(l:pos, 1, 0)]]]
endfunction

" - trailing parentheses, i.e. '(lnum[:colnum])'
let s:specs.paren = {'pattern': '\m(\(\d\+\%(:\d\+\)\?\))'}
function! s:specs.paren.parse(file) abort
  let l:file = substitute(a:file, self.pattern, '', '')
  let l:pos  = split(matchlist(a:file, self.pattern)[1], ':')
  return [l:file, ['cursor', [l:pos[0], get(l:pos, 1, 0)]]]
endfunction

" - trailing equals, i.e. '=lnum='
let s:specs.equals = {'pattern': '\m=\(\d\+\)=\%(.*\)\?'}
function! s:specs.equals.parse(file) abort
  let l:file = substitute(a:file, self.pattern, '', '')
  let l:pos  = matchlist(a:file, self.pattern)[1]
  return [l:file, ['cursor', [l:pos, 0]]]
endfunction

" - trailing dash, i.e. '-lnum-'
let s:specs.dash = {'pattern': '\m-\(\d\+\)-\%(.*\)\?'}
function! s:specs.dash.parse(file) abort
  let l:file = substitute(a:file, self.pattern, '', '')
  let l:pos  = matchlist(a:file, self.pattern)[1]
  return [l:file, ['cursor', [l:pos, 0]]]
endfunction

" - Plan 9 type line spec, i.e. '[:]#lnum'
let s:specs.plan9 = {'pattern': '\m:#\(\d\+\)'}
function! s:specs.plan9.parse(file) abort
  let l:file = substitute(a:file, self.pattern, '', '')
  let l:pos  = matchlist(a:file, self.pattern)[1]
  return [l:file, ['cursor', [l:pos, 0]]]
endfunction

" - Pytest type method spec, i.e. '::method'
let s:specs.pytest = {'pattern': '\m::\(\w\+\)'}
function! s:specs.pytest.parse(file) abort
  let l:file   = substitute(a:file, self.pattern, '', '')
  let l:name   = matchlist(a:file, self.pattern)[1]
  let l:method = '\m\C^\s*def\s\+\%(\\\n\s*\)*\zs'.l:name.'\s*('
  return [l:file, ['search', [l:method, 'cw']]]
endfunction " }}}

" - GitHub/GitLab line spec, i.e. '#Llnum'
let s:specs.github_line = {'pattern': '\m#L\(\d\+\)'}
function! s:specs.github_line.parse(file) abort
  let l:file = substitute(a:file, self.pattern, '', '')
  let l:pos  = matchlist(a:file, self.pattern)[1]
  return [l:file, ['cursor', [l:pos, 0]]]
endfunction

" - GitHub/GitLab line range, i.e. '#Llnum-Llnum'
let s:specs.github_range = {'pattern': '\m#L\(\d\+\)-L\?\(\d\+\)'}
function! s:specs.github_range.parse(file) abort
  let l:file = substitute(a:file, self.pattern, '', '')
  let [l:start, l:end]  = matchlist(a:file, self.pattern)[1:2]
  return [l:file, ['execute', ['normal! '.l:end.'GV'.l:start.'Ggv0']]]
endfunction

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
function! fetch#specs() abort " {{{
  return deepcopy(s:specs)
endfunction " }}}

" Resolve the buffer {bufname}, substituting the resolved file (if any) for
" it, with the cursor placed at the resolved position:
" @signature:  fetch#buffer({spec:String})
" @returns:    Boolean
" @note:       only buffers visible in the current tab page are resolved
" @vimlint(EVL103, 1, a:bufname)
function! fetch#buffer(bufname) abort " ({{{
  " no need for switching if the buffer is not on display
  let l:bufwinnr = bufwinnr(a:bufname)
  if l:bufwinnr is -1 | return 0 | endif

  " check for a matching spec, return if none matches
  for l:spec in values(s:specs)
    if matchend(a:bufname, l:spec.pattern) is len(a:bufname)
      break
    endif
    unlet! l:spec
  endfor
  " @vimlint(EVL104, 1, l:spec)
  if exists('l:spec') isnot 1 | return 0 | endif

  " only substitute if we have a valid resolved file
  " and a bona fide spurious unresolved buffer both
  let [l:file, l:jump] = l:spec.parse(a:bufname)
  if !filereadable(l:file) || s:bufignore.detect(bufnr(a:bufname)) is 1
    return 0
  endif

  " activate the correct window (if needed)
  let l:oldwinnr = s:gotowin(l:bufwinnr)

  try
    " we have a spurious unresolved buffer: set up for wiping
    set buftype=nowrite       " avoid issues voiding the buffer
    set bufhidden=wipe        " avoid issues with |bwipeout|

    " substitute resolved file for unresolved buffer on arglist
    let l:argidx = index(argv(), a:bufname)
    if l:argidx isnot -1
      if has('listcmds')
        " execute l:argidx.'argadd' fnameescape(l:file)
        execute 'argdelete' fnameescape(a:bufname)
      endif
      " set arglist index to resolved file if required
      let l:cmd = l:argidx.'argedit'
    endif

    " edit resolved file and place cursor at position spec; we need to
    " suppress regular error handling or files after the offending one will
    " not be processed in VimEnter
    let l:shortmess = &shortmess
    set shortmess+=oO " avoid "Press ENTER" prompt on switch
    try
      execute 'keepalt' get(l:, 'cmd', 'edit').v:cmdarg fnameescape(l:file)
    catch
      echohl ErrorMsg | echomsg v:errmsg | echohl None
      if bufname('%') isnot l:file " do not return on unrelated errors
        return 0
      endif
    finally
      let &shortmess = l:shortmess
    endtry

    if !empty(v:swapcommand)
      execute 'normal' v:swapcommand
    endif
    return s:setpos(l:jump)

  finally
    call s:gotowin(l:oldwinnr)
  endtry
endfunction " }}}
" @vimlint(EVL103, 0, a:bufname)
" @vimlint(EVL104, 0, l:spec)

if has('file_in_path') " {{{
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

  if has('visual') " {{{
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
  endif " }}}
endif " }}}

" Private helper functions: {{{
" - go to window {winnr} without affecting editor state
"   returns the original window number
function! s:gotowin(winnr) abort
  let l:curwinnr = bufwinnr('%')
  if a:winnr isnot -1 && l:curwinnr isnot a:winnr
    execute 'silent keepjumps noautocmd '.a:winnr.'wincmd w'
  endif
  return l:curwinnr
endfunction

" - place the current buffer's cursor, triggering the "BufFetchPosX" events
"   see :h call() for the format of the {calldata} List
function! s:setpos(calldata) abort
  call s:doautocmd('BufFetchPosPre')
  keepjumps call call('call', a:calldata)
  let b:fetch_lastpos = getpos('.')[1:2]
  silent! foldopen!
  silent! normal! zz
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

if has('visual')
  " - send command to the last visual selection
  function! s:dovisual(command) abort
    let l:cmd = index(['v', 'V', ''], mode()) is -1 ? 'gv'.a:command : a:command
    execute 'normal!' l:cmd
  endfunction
endif
" }}}

let &cpoptions = s:cpoptions
unlet! s:cpoptions

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
