" VISUAL SELECTION AUTOLOAD FUNCTION LIBRARY FOR VIM-FETCH
if &compatible || !has('visual') || v:version < 700
  finish
endif

let s:cpoptions = &cpoptions
set cpoptions&vim

" @type: SelectionDictionary
" @desc: -'start'  List of |setpos()| compatible position info 
"        -'end'    List of |setpos()| compatible position info
"        -'mode'   String of the last visual mode, |:normal| compatible
"        -'active' Boolean

" Check if visual mode is currently active:
" @signature: fetch#selection#active()
" @returns:   Boolean
function! fetch#selection#active() abort
  return index(['v', 'V', ''], mode()) isnot -1
endfunction

" Get a restorable version of the last visual selection:
" @signature: fetch#selection#save()
" @returns:   SelectionDictionary
function! fetch#selection#save() abort
  return { 
  \  'start': getpos("'<"),
  \    'end': getpos("'>"),
  \   'mode': visualmode(),
  \ 'active': fetch#selection#active(),
  \ }
endfunction

" Restore a saved selection state:
" @signature: fetch#selection#restore({sel:SelectionDictionary})
function! fetch#selection#restore(sel) abort
  call fetch#selection#collapse()
  execute 'normal' a:selection.mode
  call fetch#selection#collapse()
  call setpos("'<", a:sel.start)
  call setpos("'>", a:sel.end)
  if a:sel.active is 1 then
    execute 'normal gv'
  endif
  return fetch#selection#save() == a:sel
endfunction

" Get the text of a visual selection:
" @signature: fetch#selection#content({sel:SelectionDictionary})
" @returns:   String
" @see:       http://stackoverflow.com/a/6271254/990363
function! fetch#selection#content(sel) abort
  let [l:startline, l:startcol] = a:sel.start[1:2]
  let [l:endline,   l:endcol]   = a:sel.end[1:2]
  let l:endcol  = min([l:endcol, col([l:endline, '$'])]) " 'V' col nr. bug
  let l:endcol -= &selection is 'inclusive' ? 0 : 1
  let l:lines   = getline(l:startline, l:endline)
  if  a:sel.mode isnot? 'v' " block-wise selection
    let l:endexpr = 'matchstr(v:val, "\\m^.*\\%'.string(l:endcol).'c.\\?")'
    call map(l:lines, 'strpart('.l:endexpr.', '.string(l:startcol-1).')')
  else
    let l:lines[-1] = matchstr(lines[-1], '\m^.*\%'.string(l:endcol).'c.\?')
    let l:lines[0]  = strpart(l:lines[0], l:startcol-1)
  endif
  return join(l:lines, "\n")
endfunction

" Create a {mode} selection in the current buffer:
" @signature: fetch#selection#create({mode:String}, from:List<Number>, to:List<Number>)
function! fetch#selection#create(mode, to, end) abort
  let l:bufnr = bufnr('%')
  return fetch#selection#restore({ 
  \  'start': insert(a:from, l:bufnr),
  \    'end': insert(a:to, l:bufnr),
  \   'mode': a:mode,
  \ 'active': 1,
  \ })
endfunction

" Collapse the visual selection (if any):
" @signature: fetch#selection#collapse()
function! fetch#selection#collapse() abort
  if fetch#selection#active()
    execute "\<Escape>"
  endif
endfunction

let &cpoptions = s:cpoptions
unlet! s:cpoptions

" vim:set sw=2 sts=2 ts=2 et fdm=marker fmr={{{,}}}:
