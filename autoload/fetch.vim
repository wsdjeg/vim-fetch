" AUTOLOAD FUNCTION LIBRARY FOR VIM-FETCH
if &compatible || v:version < 700
  finish
endif

let s:cpoptions = &cpoptions
set cpoptions&vim

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

" Resolve {specs} for the current buffer, substituting the resolved
" file (if any) for it, with the cursor placed at the resolved position:
" @signature:  fetch#buffer({specs:List<SpecDictionary>})
" @returns:    Boolean
function! fetch#buffer(specs) abort " {{{
  let l:bufname = expand('%')
  if s:bufignore.detect(bufnr('%')) is 1
    return 0 " skip ignored buffers
  endif

  let l:specmatch = fetch#specs#match(l:bufname, a:specs, -1)
  if  l:specmatch.pos is -1
    return 0 " skip when no spec matches
  endif

  let l:file = substitute(l:bufname, '\V'.escape(l:match, '\').'\$', '', '')
  if !filereadable(l:file)
    return 0 " skip non-readable spec matches
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
  return s:setpos(l:spec.parse(l:match, l:file))
endfunction " }}}

" Edit |<cfile>|, resolving a possible trailing spec from {specs}:
" @signature:  fetch#cfile({count:Number}, {specs:List<SpecDictionary>})
" @returns:    Boolean
" @notes:      - see |gf| for the usage of {count}
"              - will fall back on Vim's |gF| when no spec matches
function! fetch#cfile(count, specs) abort " {{{
  let l:cfile = expand('<cfile>')

  " test for a trailing spec, accounting for multi-line '<cfile>' matches
  if !empty(l:cfile)
    " locate '<cfile>' in current line
    let l:cfilepos = s:cpos(l:cfile)

    " test for a trailing spec, accounting for multi-line '<cfile>' matches
    let [l:line, l:colindex]    = [getline(l:cfilepos.end[0]), l:cfilepos.end[1]]
    let [l:go, l:spec, l:match] = fetch#specs#matchatpos(a:specs, l:line, l:colindex)
    if l:go is 1 " leverage Vim's own |gf| for opening the file
      execute 'normal!' a:count.'gf'
      return s:setpos(l:spec.parse(l:match))
    endif
  endif

  " fall back to Vim's |gF|
  execute 'normal!' a:count.'gF'
  return 1
endfunction " }}}

" Edit the visually selected file, resolving a possible trailing spec from {specs}:
" @signature:  fetch#visual({count:Number}, {specs:List<SpecDictionary>})
" @returns:    Boolean
" @notes:      - see |gf| for the usage of {count}
"              - will fall back on Vim's |gF| when no spec matches
function! fetch#visual(count, specs) abort " {{{
  let l:selection = fetch#selection#save()
  let [l:endline, l:endcol] = l:selection.end[1:2]

  " test for a trailing spec
  if !empty(fetch#selection#content(l:selection))
    let [l:go, l:spec, l:match]
    \ = fetch#specs#matchatpos(a:specs, getline(l:endline), l:endcol)
    if l:go is 1 " leverage Vim's |gf| to get the file
        call s:dovisual(a:count.'gf')
        return s:setpos(l:spec.parse(l:match))
      endif
  endif

  " fall back to Vim's |gF|
  call s:dovisual(a:count.'gF')
  return 1
endfunction " }}}

" Private helper functions: {{{
" - find the start and end position of {string} under the cursor
function! s:cpos(string) abort
  let l:pattern    = '\V'.escape(a:string, '\')
  let l:cpos       = {'start' = [], 'end' = []}
  let l:cpos.start = searchpos(l:pattern, 'bcn', line('.'))
  if  l:cpos.start == [0, 0]
    let l:cpos.start = searchpos(l:pattern, 'cn', line('.'))
  endif
  let l:lines       = split(a:string, "\n")
  let l:linecount   = len(lines)
  let l:cpos.end[0] = l:cpos.start[0] + l:linecount - 1
  let l:cpos.end[1]
  \ = (l:linecount > 1 ? 0 : l:cpos.start[1]) + len(l:lines[-1]) - 1
  return l:cpos
endfunction

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

" - try to find a (shortened {cfile}).(spec from {specs}) match
function! s:cfileseek(cfile, specs) abort
  let l:cftail     = fnamemodify(l:cfile, ':p:t')
  let l:cftaillen  = len(l:cftail)
  let l:cftailpos  = s:cpos(l:cftail)
  let l:cftailcont = getline(l:cftailpos.end[0])[l:cftailpos.end[1], -1]

  let l:matches    = fetch#specs#matchlist(l:cftail.l:cftailcont, a:specs, l:endcol)
  call filter(l:matches, 'v:val.pos > 0'
  \ .' && v:val.pos < '.string(l:cftaillen)
  \ .' && v:val.pos + len(v:val.match) >= '.string(l:cftaillen))
  if empty(l:matches)
    return 0
  endif

  let l:oldsel = fetch#selection#save()
  try
    for l:specmatch in l:matches
      let l:cfpartpos = s:cpos(l:specmatch.match)
      call fetch#selection#create('v', l:cfpartpos.start, l:cfpartpos.end)
      try
        call fetch#visual(a:count, [l:specmatch.spec])
      catch /E447/
        if l:specmatch is l:matches[-1]
          return 0
        end if
      endtry
    endfor
  finally
    call fetch#selection#restore(l:oldsel)
  endtry
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
